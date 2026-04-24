#!/usr/bin/env python3
"""versus CLI chat client.

Connects to a running CogServer's telnet endpoint, enters the Scheme
REPL, and serves a prompt/response loop backed by the `versus-respond`
procedure that the atomspace module generates into
/opt/versus/inference.scm and that CogServer loads at startup.

Run after `terraform apply`:

    python3 chat.py

Every prompt auto-teaches itself as a new observation: the system
learns from conversation without an explicit `:teach` command.

Commands:
    :stats               show walker statistics (fragment / pair counts, top pairs)
    :quit                exit (Ctrl-D or Ctrl-C also work)
    <anything else>      prompt; returns a matching fragment with provenance

Connection config comes from environment variables (with defaults that
match the state-fragment defaults in states/core.yaml):

    COGSERVER_HOST          default: localhost
    COGSERVER_TELNET_PORT   default: 17001

Or pass --host and --port as CLI arguments. CLI args win over env vars.
"""

from __future__ import annotations

import argparse
import os
import re
import socket
import sys
import time

DEFAULT_HOST = "localhost"
DEFAULT_PORT = 17001

# CogServer's Guile REPL emits ANSI-colored prompts (`\x1b[0;34mguile\x1b[1;34m> \x1b[0m`
# or similar). Strip escape sequences before any marker detection or user display.
ANSI_ESCAPE_RE = re.compile(rb"\x1b\[[0-9;]*[A-Za-z]")

# Markers retained only for cosmetic cleanup in clean_response, not for
# response-end detection (see read_response).
PROMPT_MARKERS = (b"scheme@", b"guile> ", b"guile>\n")

# Tunables.
CONNECT_TIMEOUT = 10.0
INITIAL_DRAIN_TIMEOUT = 0.3
# Response detection: read until the server has been idle for IDLE_TIMEOUT,
# capped at MAX_WAIT. A burst-then-idle pattern is exactly what a REPL
# produces per evaluation, so idle-detection is faster and more reliable
# than counting prompt markers.
IDLE_TIMEOUT = 0.15
MAX_WAIT = 5.0
RECONNECT_RETRIES = 2


def strip_ansi(buf: bytes) -> bytes:
    return ANSI_ESCAPE_RE.sub(b"", buf)


def drain(sock: socket.socket, timeout: float) -> bytes:
    """Read from sock until it stops producing data for `timeout` seconds."""
    sock.settimeout(timeout)
    buf = b""
    try:
        while True:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            buf += chunk
    finally:
        sock.settimeout(None)
    return buf


def read_response(sock: socket.socket, max_wait: float, idle_timeout: float) -> bytes:
    """Read until the server has been idle for `idle_timeout` (response
    done) or `max_wait` elapses (safety bound). Idle detection works
    because the REPL emits the echo, value, and next prompt as a single
    burst per evaluation; after that it waits for us."""
    sock.settimeout(idle_timeout)
    buf = b""
    deadline = time.monotonic() + max_wait
    try:
        while time.monotonic() < deadline:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                # No data for idle_timeout. If we have something, the
                # response is complete; otherwise keep waiting for the
                # first byte.
                if buf:
                    break
                continue
            if not chunk:
                break
            buf += chunk
    finally:
        sock.settimeout(None)
    return buf


def connect_and_enter_scheme(host: str, port: int) -> socket.socket:
    sock = socket.create_connection((host, port), timeout=CONNECT_TIMEOUT)
    drain(sock, INITIAL_DRAIN_TIMEOUT)
    sock.sendall(b"scheme\n")
    drain(sock, INITIAL_DRAIN_TIMEOUT)
    return sock


LEADING_PROMPT_RE = re.compile(r"^(scheme@\S*>\s*|guile>\s*)+")


def clean_response(raw: bytes, expression: str) -> str:
    """Strip ANSI, echoed expressions, scheme prompts, and bannery noise."""
    text = strip_ansi(raw).decode("utf-8", errors="replace")
    kept: list[str] = []
    expression_stripped = expression.strip()
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        # Strip any leading prompt fragments ("guile> ", "scheme@(guile-user)> "),
        # which can appear at the head of lines when the REPL emits a prompt
        # concatenated with its next output.
        stripped = LEADING_PROMPT_RE.sub("", stripped).strip()
        if not stripped:
            continue
        if stripped == expression_stripped:
            continue
        if "scheme@" in stripped:
            continue
        if "Entering scheme shell" in stripped or "^D or a single" in stripped:
            continue
        # Strings come back quoted; unquote.
        if len(stripped) >= 2 and stripped.startswith('"') and stripped.endswith('"'):
            stripped = stripped[1:-1].replace('\\"', '"').replace("\\\\", "\\")
        # `$N = value` REPL echo; strip the `$N = ` prefix.
        if stripped.startswith("$") and " = " in stripped:
            stripped = stripped.split(" = ", 1)[1]
            if len(stripped) >= 2 and stripped.startswith('"') and stripped.endswith('"'):
                stripped = stripped[1:-1].replace('\\"', '"').replace("\\\\", "\\")
        kept.append(stripped)
    return "\n".join(kept) if kept else "<empty response>"


def escape_for_scheme(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def send_with_retry(sock_holder: list[socket.socket | None], host: str, port: int, expression: str) -> str:
    """Send an expression; if the socket died, reconnect and retry."""
    last_err: Exception | None = None
    for attempt in range(RECONNECT_RETRIES + 1):
        sock = sock_holder[0]
        if sock is None:
            try:
                sock_holder[0] = connect_and_enter_scheme(host, port)
                sock = sock_holder[0]
            except OSError as e:
                last_err = e
                time.sleep(0.5)
                continue
        try:
            # Clear any stray bytes (rare, but cheap insurance) then send,
            # then read until the REPL goes idle.
            drain(sock, 0.02)
            sock.sendall((expression + "\n").encode("utf-8"))
            raw = read_response(sock, MAX_WAIT, IDLE_TIMEOUT)
            return clean_response(raw, expression)
        except (BrokenPipeError, ConnectionResetError, OSError) as e:
            last_err = e
            try:
                sock.close()
            except OSError:
                pass
            sock_holder[0] = None
    raise RuntimeError(f"cogserver connection failed after {RECONNECT_RETRIES + 1} attempts: {last_err}")


def main() -> int:
    parser = argparse.ArgumentParser(description="versus CLI chat client")
    parser.add_argument(
        "--host",
        default=os.environ.get("COGSERVER_HOST", DEFAULT_HOST),
        help=f"cogserver host (env COGSERVER_HOST, default {DEFAULT_HOST})",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("COGSERVER_TELNET_PORT", DEFAULT_PORT)),
        help=f"cogserver telnet port (env COGSERVER_TELNET_PORT, default {DEFAULT_PORT})",
    )
    args = parser.parse_args()

    print(f"versus> connecting to cogserver at {args.host}:{args.port}...")
    try:
        sock = connect_and_enter_scheme(args.host, args.port)
    except (ConnectionRefusedError, socket.gaierror, socket.timeout) as e:
        print(f"versus> connection failed: {e}", file=sys.stderr)
        print("versus> is the cogserver container running? try `docker ps | grep cog`", file=sys.stderr)
        return 1

    sock_holder: list[socket.socket | None] = [sock]
    print("versus> connected. commands: :stats, :quit. everything else is a prompt.")

    try:
        while True:
            try:
                line = input("you> ").strip()
            except (KeyboardInterrupt, EOFError):
                print()
                break
            if not line:
                continue
            if line == ":quit":
                break
            if line == ":stats":
                expr = "(versus-walker-stats)"
            else:
                expr = f'(versus-respond "{escape_for_scheme(line)}")'
            try:
                response = send_with_retry(sock_holder, args.host, args.port, expr)
            except RuntimeError as e:
                print(f"bot> <connection error: {e}>", file=sys.stderr)
                break
            print(f"bot> {response}")
    finally:
        s = sock_holder[0]
        if s is not None:
            try:
                s.close()
            except OSError:
                pass
    print("versus> bye.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
