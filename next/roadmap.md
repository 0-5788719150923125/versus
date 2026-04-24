# Roadmap

*Build order and why. Scope discipline is the design: URE died from
trying to build everything at once (see [historical.md](./historical.md)).*

## Where we are

Scaffolding is complete and end-to-end verified. `terraform apply` generates
Atomese and docker-compose from YAML; CogServer runs on localhost:18080;
generated Scheme loads cleanly; `versus-init-atom` and `versus-apply-decay`
are callable and produce correct values.

The substrate is live. Nothing else is built.

## Near-term (next two build targets)

### 1. Walker module

Concrete design in [walker.md](./walker.md).

The walker is the immediate next target because:

- It is the one mechanism that, once working, unifies learning,
  inference, and generation (see [commitments.md](./commitments.md) § 7).
- Without it, the substrate has nothing to consume or update the atoms
  we generate.
- It can be demonstrated with a toy corpus before ingest is built, which
  lets us evaluate the wake/sleep architecture in isolation.

### 2. Ingest worker

Streams fineweb-edu tokens into FragmentAtoms. Probably a Guile driver
with a Python subprocess calling HuggingFace datasets.

Not before the walker. A walker with a toy in-memory corpus is
demonstrable; a walker with a real ingest pipeline but no learning loop
is just data movement.

## Mid-term

### 3. Chat endpoint

HTTP server on port 8080. Turns prompts into inference walks; returns
fragment-stitched responses with provenance attached.

Not before the walker can do generation walks. Chat is just "an HTTP
wrapper around a generation walk"; the walk has to work first.

### 4. Storage module

Explicit atomspace-rocks volume lifecycle, snapshots, retention policy.
Currently the Docker volume is implicit in the compose file.

Not before ingest is producing enough atoms for persistence to matter.
A fresh-start-every-apply loop is fine for the first few build iterations.

## Later (deferred but planned)

### 5. Tiny transformer SelectorAtoms

n_dim=4 micro-networks as first-class atoms. Used at decision points
where soft-gate selection is inadequate (e.g. grammatical compatibility
checks during generation).

Deferred per user direction during Phase 3 scoping. Requires the
walker's soft-gate-fallback selection to be working and
evaluatable first. Adding tiny transformers before that is premature
optimization.

### 6. Platformer integration (Shape B)

Extract Platformer's `config/` module into a shared `platformer-framework`
package, depended on by both versus and platformer. Not needed until
versus has to be distributed independently. See [coupling.md](./coupling.md).

### 7. Distributed / networked Atomspace

Currently single-writer, local-only via atomspace-rocks. Eventual targets:
AtomSpace-Bridge for multi-process access; possibly cloud deployment via
Platformer's compute modules.

Not a day-one concern. Get the local prototype working with visible
learning before worrying about scale.

## Principles for adding items to this list

- **One thing demonstrable end-to-end is worth more than two things half-built.** See the eve lesson.
- **A new subsystem is allowed only if it is enabled by state-fragment YAML.** If adding a subsystem requires editing main.tf beyond wiring, the HCL surface has failed to abstract it. Fix the HCL surface, not the subsystem.
- **"I could imagine adding X" is not a build target.** Items on this roadmap have a concrete reason they come after the item before them. If a new idea does not have that reason, it lives in a note, not on the roadmap.

## Non-goals (for now)

- Multi-turn conversational state. Single-shot prompt-response for MVP.
- Long-form generation. Short-form grounded responses are the goal.
- Cross-language corpus support. English only for MVP.
- GPU acceleration. CPU only; tractable for n_dim=4 selectors.
- Web UI. CogServer's telnet/HTTP is the interface.
