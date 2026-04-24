# Ingest Module

*Streams corpus data into the atomspace as FragmentAtoms at a
configurable (deliberately slow) rate. Runs as a separate container
alongside cog, connecting via docker's internal network.*

## Scope for this build

Build a minimally-useful ingest worker that:

- Streams a HuggingFace dataset (default: `HuggingFaceFW/fineweb-edu`,
  `sample-10BT` config) using `datasets.load_dataset(..., streaming=True)`.
- Splits each document into sentences, then into small word-window
  fragments (default 3-8 words per fragment).
- Calls `versus-teach` once per fragment via a persistent telnet session
  to `cog:17001`.
- Rate-limits globally to a configurable fragments-per-second value.
  Defaults to 5/sec (deliberately low).
- Stops after a max-fragment cap (default 1000) so a hands-off run does
  not accumulate atoms indefinitely.
- Logs progress to stdout so `docker compose logs ingest` is the
  observability hook.

Explicitly out of scope:

- Wake/sleep cycles (walker module's job).
- Clustering, MI, disjunct induction (walker module's job).
- Real atomspace-rocks persistence (storage module's job; atoms live in
  RAM until then).
- praxis-style role tagging (see below for the future extension path).
- Anything per-document that is not "chop into fragments and teach."

## Architecture

```
                                  docker compose network
    +-----------+   ingest-tokens-via-telnet    +-----------+
    | ingest    | ----------------------------> | cog       |
    | python    |     (scheme REPL calls        | cogserver |
    | container |      to versus-teach)         | container |
    +-----------+                                +-----------+
         |
         v
    streaming pull
    from HuggingFace
    (rate-limited)
```

Both containers are defined in the same docker-compose.yml (generated
by the atomspace module). The ingest service is included conditionally
based on the resolver's `ingest_enabled` flag, which is true when the
`ingest` key exists in merged service_configs.

### Why a separate container

- Resource isolation: the HuggingFace datasets library pulls heavy
  dependencies (pyarrow, numpy, pandas); keeping them out of the cog
  container keeps cog lean.
- Independent lifecycle: restart / stop / swap ingest without
  recreating cog, which would lose in-RAM atoms.
- Natural rate control: ingest's CPU/memory caps and its own rate-limit
  do not interfere with cog's responsiveness to the chat client.
- Matches the Platformer-style pattern of one service per concern.

### Why rate-limiting matters early

The user's system is the first validation target. A laptop running
cog + ingest + regular desktop load cannot absorb a 50K-tokens-per-
second HF stream without becoming unresponsive, and at this MVP stage
the atomspace has no structure for the tokens anyway - they pile up as
FragmentAtoms whose counts rise but whose relationships are not yet
computed. So there is no upside to going fast.

The rate limit is expressed in fragments per second (not tokens per
second) because the unit of work is a telnet round-trip plus an
atomspace mutation. Five/sec is a deliberately gentle default; the
user can raise it once it is boring.

## Dataset choice and structure

### Defaults

- `dataset.source`: `HuggingFaceFW/fineweb-edu`
- `dataset.config`: `sample-10BT` (smallest sampled config, ~10B tokens)
- `dataset.split`: `train`

`sample-10BT` streams quickly enough that the first fragment appears
within a few seconds of ingest startup. The full `fineweb-edu` default
config is ~1.3T tokens and overkill for any POC.

### What praxis does with the same dataset

Praxis wraps each fineweb-edu document in a `{system, developer,
assistant}` message triplet where the raw text becomes the assistant's
content. This teaches its model text-continuation behavior. Literally:

```python
messages = [
    {"role": "system", "content": SYSTEM_PROMPT},
    {"role": "developer", "content": sample_developer_prompt("continue_text")},
    {"role": "assistant", "content": text_formatter(text)},
]
```

For versus MVP, we do **not** replicate this structure. The trivial
inference does not use role information, and baking it into ingest
before there is anything that consumes it would be premature
infrastructure.

### Future role-tagging extension

When it becomes useful (walker + richer generation), each ingested
FragmentAtom could be tagged with a role ConceptAtom:

- `Concept "role:assistant"` for fragments from document bodies (the
  praxis framing: "this is what an assistant would produce").
- `Concept "role:user"` for fragments from user-side corpora (chat
  datasets, question banks).

Generation walks could then prefer fragments tagged with the "currently
generating" role (usually assistant), producing role-appropriate
output. This is a small extension to ingest (add an env var for
role-to-tag, a single extra `MemberLink` per fragment) and is
explicitly noted in the state fragment as a future option.

## Module structure

    ingest/
    |-- main.tf
    |-- variables.tf
    |-- outputs.tf
    `-- scripts/
        `-- ingest.py        # static Python, not templated

The ingest.py is a static script - same principle as chat.py. The
Terraform module's job is to expose its path and configuration to the
atomspace module so the generated docker-compose can mount it and set
the right environment variables.

No templates. Python code does not benefit from state-fragment
composition, and templating Python is error-prone.

## State fragment (states/fineweb-edu.yaml)

```yaml
services:
  ingest:
    core:
      dataset:
        source: HuggingFaceFW/fineweb-edu
        config: sample-10BT      # smallest subsample for POC
        split: train

      fragments:
        min_words: 3             # inclusive lower bound
        max_words: 8             # inclusive upper bound

      rate:
        fragments_per_second: 5  # gentle trickle
        max_fragments: 1000      # 0 = unbounded; stop after this many

      # role_tag: assistant       # future: tag each fragment with a
                                  # role ConceptAtom. Leave unset
                                  # until generation uses it.
```

## Success criteria

From a clean `terraform destroy`:

1. `terraform apply -var='states=["core","fineweb-edu"]'` succeeds.
2. Both containers come up: `versus-cog-1` and `versus-ingest-1`.
3. Ingest logs show: waiting for cogserver, installing datasets,
   connecting, streaming, then per-N-fragment progress lines.
4. After ~30 seconds, fragments are present in the cogserver. Query
   any common word via `python3 chat.py` and get a match with
   provenance.
5. `docker stats` shows the system is not being hammered - ingest
   container at low CPU, low memory pressure.
6. `terraform destroy` tears down both containers cleanly.

## Gotchas to watch for

- **First-run pip install is slow** (~30 seconds). The generated
  compose mounts a pip cache volume so subsequent starts are fast.
- **HuggingFace rate limits** exist if you hammer the hub. The 5-per-
  second default is well below anything that would trigger them.
- **Network flakiness.** HF datasets streaming can hit transient
  network errors. The script handles reconnection to cogserver; HF
  client has its own retry logic.
- **Fragment count explosion.** 1M tokens at fragment_size=5 means
  200k FragmentAtoms. At the 5-per-second default that takes ~11 hours
  to ingest - the `max_fragments` cap prevents a runaway ingestion.
- **No deduplication.** The same fragment seen twice increments `count`
  but still triggers a telnet round-trip. For MVP this is fine (counts
  are meaningful). Walker-era, consider local dedup before sending.
