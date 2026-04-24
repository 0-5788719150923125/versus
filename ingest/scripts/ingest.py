#!/usr/bin/env python3
"""versus ingest worker.

Streams a HuggingFace dataset, splits each document into word-window
fragments, and feeds them to the cogserver's scheme REPL via a persistent
telnet session. Rate-limited and bounded so a hands-off run does not
hammer the host.

Runs inside a container managed by docker-compose (see the generated
docker-compose.yml). Configuration comes from environment variables set
by the compose file, matching the ingest module's resolved_config output.

    COGSERVER_HOST              hostname of the cog container (docker DNS)
    COGSERVER_TELNET_PORT       telnet port on cog
    INGEST_DATASET              HuggingFace dataset identifier
    INGEST_DATASET_CONFIG       dataset config / subset name (may be empty)
    INGEST_DATASET_SPLIT        dataset split (typically "train")
    INGEST_FRAGMENT_MIN_WORDS   min words per fragment
    INGEST_FRAGMENT_MAX_WORDS   max words per fragment
    INGEST_RATE                 target fragments per second (float)
    INGEST_MAX_FRAGMENTS        stop after this many (0 = unbounded)
    INGEST_ROLE_TAG             if set, every fragment is tagged with a
                                ConceptAtom of this name (future; unused
                                by trivial inference)
"""

from __future__ import annotations

import os
import re
import socket
import sys
import time
from typing import Iterator

HOST = os.environ.get("COGSERVER_HOST", "cog")
PORT = int(os.environ.get("COGSERVER_TELNET_PORT", "17001"))

DATASET = os.environ.get("INGEST_DATASET", "HuggingFaceFW/fineweb-edu")
DATASET_CONFIG = os.environ.get("INGEST_DATASET_CONFIG", "sample-10BT")
DATASET_SPLIT = os.environ.get("INGEST_DATASET_SPLIT", "train")

MIN_WORDS = int(os.environ.get("INGEST_FRAGMENT_MIN_WORDS", "3"))
MAX_WORDS = int(os.environ.get("INGEST_FRAGMENT_MAX_WORDS", "8"))
RATE = float(os.environ.get("INGEST_RATE", "5"))
MAX_FRAGMENTS = int(os.environ.get("INGEST_MAX_FRAGMENTS", "1000"))
ROLE_TAG = os.environ.get("INGEST_ROLE_TAG", "").strip()

CONNECT_RETRIES = 30
CONNECT_BACKOFF = 1.0
SCHEME_DRAIN_TIMEOUT = 0.3
SEND_DRAIN_TIMEOUT = 0.05
PROGRESS_EVERY = 50

# Simple sentence splitter. Not linguistically perfect, but fine for MVP.
SENTENCE_END_RE = re.compile(r"(?<=[.!?])\s+(?=[A-Z])")


def log(msg: str) -> None:
    print(f"[ingest] {msg}", flush=True)


def wait_for_cogserver(host: str, port: int) -> None:
    log(f"waiting for cogserver at {host}:{port}...")
    for attempt in range(1, CONNECT_RETRIES + 1):
        try:
            s = socket.create_connection((host, port), timeout=2)
            s.close()
            log(f"cogserver reachable after {attempt} attempt(s)")
            return
        except OSError:
            time.sleep(CONNECT_BACKOFF)
    raise RuntimeError(f"cogserver not reachable at {host}:{port} after {CONNECT_RETRIES} attempts")


def open_scheme_session(host: str, port: int) -> socket.socket:
    sock = socket.create_connection((host, port), timeout=10)
    drain(sock, SCHEME_DRAIN_TIMEOUT)
    sock.sendall(b"scheme\n")
    drain(sock, SCHEME_DRAIN_TIMEOUT)
    return sock


def drain(sock: socket.socket, timeout: float) -> bytes:
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


def escape_for_scheme(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def send_teach(sock: socket.socket, fragment: str) -> None:
    """Fire-and-forget teach call. Drains briefly so the socket buffer
    does not fill, but does not wait for the response value - throughput
    matters here more than per-call confirmation."""
    expr = f'(versus-teach "{escape_for_scheme(fragment)}")'
    sock.sendall((expr + "\n").encode("utf-8"))
    drain(sock, SEND_DRAIN_TIMEOUT)


def sentences(text: str) -> Iterator[str]:
    """Yield whitespace-normalized sentences from a document."""
    text = text.replace("\n", " ").replace("\r", " ")
    for raw in SENTENCE_END_RE.split(text):
        stripped = raw.strip()
        if stripped:
            yield stripped


def fragments(sentence: str, min_w: int, max_w: int) -> Iterator[str]:
    """Yield contiguous word-window fragments from a sentence. Windows
    are of size max_w where possible, shrinking to a minimum of min_w
    at the tail. Shorter tails are dropped."""
    words = [w for w in sentence.split() if w]
    i = 0
    n = len(words)
    while i < n:
        remaining = n - i
        if remaining < min_w:
            break
        window = min(max_w, remaining)
        yield " ".join(words[i : i + window])
        i += window


def ingest_loop(sock: socket.socket) -> int:
    # Deferred import so docker logs show the pip-install phase in order
    # before any HuggingFace-specific output.
    from datasets import load_dataset

    log(f"loading dataset: {DATASET} config={DATASET_CONFIG or '(default)'} split={DATASET_SPLIT}")

    ds_kwargs = {"streaming": True, "split": DATASET_SPLIT}
    if DATASET_CONFIG:
        ds_kwargs["name"] = DATASET_CONFIG
    ds = load_dataset(DATASET, **ds_kwargs)

    log(f"streaming started. rate={RATE}/s cap={MAX_FRAGMENTS or 'unbounded'} window=[{MIN_WORDS},{MAX_WORDS}]")

    interval = 1.0 / RATE if RATE > 0 else 0.0
    next_send = time.monotonic()
    count = 0
    start = time.monotonic()

    for record in ds:
        text = record.get("text") or ""
        if not text:
            continue
        for sentence in sentences(text):
            for frag in fragments(sentence, MIN_WORDS, MAX_WORDS):
                if MAX_FRAGMENTS and count >= MAX_FRAGMENTS:
                    elapsed = time.monotonic() - start
                    log(f"reached MAX_FRAGMENTS={MAX_FRAGMENTS} in {elapsed:.1f}s; exiting")
                    return 0

                now = time.monotonic()
                if now < next_send:
                    time.sleep(next_send - now)
                next_send = time.monotonic() + interval

                try:
                    send_teach(sock, frag)
                except (BrokenPipeError, ConnectionResetError) as e:
                    log(f"cogserver disconnected at count={count}: {e}")
                    return 1
                except OSError as e:
                    log(f"socket error at count={count}: {e}")
                    return 1

                count += 1
                if count % PROGRESS_EVERY == 0:
                    elapsed = time.monotonic() - start
                    actual_rate = count / elapsed if elapsed > 0 else 0
                    log(f"sent {count} fragments in {elapsed:.1f}s ({actual_rate:.2f}/s actual)")

    log(f"dataset exhausted at count={count}")
    return 0


def main() -> int:
    log(f"starting. host={HOST} port={PORT} dataset={DATASET}")
    if ROLE_TAG:
        log(f"note: role_tag='{ROLE_TAG}' is set but not applied (trivial inference ignores it)")

    try:
        wait_for_cogserver(HOST, PORT)
    except RuntimeError as e:
        log(f"giving up: {e}")
        return 1

    sock = open_scheme_session(HOST, PORT)
    log("scheme session opened")

    try:
        return ingest_loop(sock)
    finally:
        try:
            sock.close()
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
