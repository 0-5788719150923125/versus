# Gotchas

*Concrete issues that bit us during scaffolding or will bite us during
iteration. Check here before re-debugging something from scratch.*

## From the initial scaffold

### Docker-compose volume mount paths must be absolute

Relative paths in `volumes:` get resolved relative to the compose file's
own directory. For versus, the compose file lives at `.versus/docker-compose.yml`,
so a relative mount source like `./.versus` resolves to `.versus/.versus/`,
which does not exist. Docker then auto-creates it (empty, owned by root)
and mounts nothing useful. The container starts but every `(load ...)`
call fails with "No such file or directory."

**Fix:** wrap `generated_dir` in `abspath()` in `atomspace/main.tf`:

```hcl
generated_dir = abspath("${path.root}/.versus")
```

Embedded into the compose template, this produces an absolute mount source
like `/home/crow/repos/versus/.versus:/opt/versus:ro`.

### `(opencog atom-types)` is not a valid module in `opencog/learn:latest`

The image rolls atom-type primitives (`FloatValue`, `Predicate`,
`cog-set-value!`, etc.) into `(opencog)` directly. A `use-modules` line
that tries to import `(opencog atom-types)` separately will fail with
"no code for module (opencog atom-types)."

**Fix:** import just `(opencog)` and, if networking is needed,
`(opencog cogserver)`. That is enough for atom creation, value manipulation,
pattern matching, and CogServer control.

### CogServer's `start-cogserver` is non-blocking

`(start-cogserver)` spawns the server in a separate thread and returns.
If the Guile process is doing nothing else, it exits, Docker sees the
container done, and restarts it (or reports exit). The current compose
command ends with `(while #t (sleep 3600))` to keep Guile alive.

A cleaner pattern will emerge when the walker exists: the walker's own
loop keeps the process alive, and `start-cogserver` is just one
initialization step on the way to that loop.

### Platformer's `config` module resolves `states_dirs` relative to itself

`path.module` inside the imported `config` module points at
`../platformer/config`, so a passed `states_dirs = ["./states"]` would
look for `../platformer/config/states/*.yaml`, not versus's states.

**Fix (in Platformer):** detect absolute paths in `states_dirs` and use
them verbatim. See [coupling.md](./coupling.md) for the patch.

**Fix (in versus):** pass absolute paths:

```hcl
states_dirs = [abspath("${path.root}/states")]
```

### `aws_region` was a required input with no default

Platformer's `config` module required `aws_region` even though it only
uses it in error messages that never fire for versus.

**Fix (in Platformer):** add `default = "us-east-2"` to the variable.
Versus now imports without passing anything.

## Things to watch for going forward

### Root-owned files in `.versus/`

Docker bind mounts can produce root-owned files if the container writes
through the mount. If a later iteration has the walker writing outputs
to `/opt/versus/`, those files will be root-owned on the host. Plan for
either:

- Read-only mounts (current): walker can't write there.
- A separate writable mount at `/opt/versus-out/` with a named volume,
  not a bind mount.
- Running the container with `user: ${UID}:${GID}` to match the host
  user.

Pick one deliberately when the walker lands.

### `terraform destroy` and lingering containers

If `docker compose` was invoked outside Terraform (e.g., for debugging)
and created or modified containers, `terraform destroy`'s destroy
provisioner may not clean them all up. The fallback is always:

```bash
docker compose -f .versus/docker-compose.yml down
docker volume rm versus_atomspace    # if you really want a clean slate
```

### Changes to generated Scheme do not automatically reload

The CogServer loads `atom-schema.scm` and `decay-rules.scm` on startup.
Editing the state fragment and re-applying changes those files, and the
`null_resource.cogserver` trigger on file hashes causes the container to
be recreated. But if you edit a template file while the container is up
and do NOT re-apply, the running CogServer still has the old Scheme.

Always `terraform apply` after state fragment or template changes, and
watch for the `null_resource.cogserver` line in the plan (it should say
"replaced" or "will be created" if the content changed).

### Port 18080 collisions

CogServer's HTTP/WebSocket port is a common dev port. If another service
is using it, `docker compose up` fails with "bind: address already in
use." Change the port in `states/core.yaml`:

```yaml
services:
  atomspace:
    core:
      cogserver:
        port: 18081
```

Re-apply. The generated docker-compose picks up the change.

## From the chat MVP build

### `timestamp()` in templates defeats idempotence

Terraform's `timestamp()` changes on every plan, which changes
`templatefile()` output, which changes `content_sha256` on `local_file`
resources, which invalidates `null_resource.cogserver` triggers, which
forces container recreation on every `terraform apply`. The substrate
should only recreate when state fragments actually change, so templates
must not include `timestamp()`. A static "GENERATED by ..." header is
plenty.

### Docker compose's `version:` key is obsolete

Modern `docker compose` warns that `version: '3.9'` is ignored and
should be removed. Dropped from the template.

### CogServer's Scheme REPL prompts arrive colored and fragmented

Guile's REPL inside the container emits ANSI-colored prompts
(`\x1b[0;34mguile\x1b[1;34m> \x1b[0m`). Three pitfalls:

1. **Byte-level marker detection fails on colored prompts.** `guile> `
   is split by color codes in the raw stream; `"guile> " in buf` never
   matches. Fix: strip ANSI escapes before doing marker detection.
2. **Single-prompt detection fires too early.** After sending a command,
   the REPL echoes it and emits a prompt BEFORE computing the value.
   Reading "until prompt" returns the echo + prompt, leaving the value
   still in the socket buffer. The next iteration's read then picks up
   the previous iteration's value, causing responses to shift by one.
   Fix: read until TWO new prompt markers have appeared (one for echo,
   one for value-done).
3. **Leading prompt fragments at the start of response lines.** Even
   with proper marker-counting, the response often begins with
   `guile> <actual-value>` on the same line. Strip leading prompt
   prefixes from every line in the response, not just line-matching.

All three fixes live in `chat.py`. If you write another REPL-driver,
expect to rediscover these.

### Container startup race after `terraform apply`

The cogserver needs a couple of seconds to finish loading Scheme files
before the telnet port is ready for commands. Running `chat.py`
immediately after `apply` often hits a `BrokenPipeError` on the first
send. Fix: `chat.py` already has connect-retry with a short backoff;
if that is not enough, `sleep 3` before running.
