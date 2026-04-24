# Historical Lessons

*Two specific prior failures shape versus's design. Naming them out loud
prevents repeating them.*

## URE as design brief

The OpenCog wiki documents why the Unified Rule Engine failed and was
formally deprecated. Its stated failure modes are not generic "complex
systems are hard" observations; they are four specific diagnoses. Each
one maps, line for line, onto a thing versus is designed to address.

| URE failure (per the wiki)                                       | Versus response                                                      |
|------------------------------------------------------------------|----------------------------------------------------------------------|
| "A simple syntax for creating rules was never developed; hand-authoring proved difficult and error prone" | `states/*.yaml` is the simple syntax; HCL generates Atomese at apply time |
| "Implementation never made use of Atomese, so systems could not automatically learn new rules" | Rules are atom properties; the system updates them in-atomspace during sleep cycles |
| "Related systems like RelEx and Ghost were never ported to URE, creating incompatibility" | Every subsystem enters through the same state-fragment pattern; one composition mechanism |
| "Forward and backward chaining implemented, but not the algorithms probabilistic logic requires" | Scoped out; pattern-matcher plus hand-rolled updates are sufficient for MVP |

Versus is narrow on purpose. URE died from unbounded ambition (trying to
solve inference, rule-authoring, rule-learning, and integration all at
once, none finished). Versus's MVP is smaller than versus's full design.
The walker ships before the ingest worker; the ingest worker ships before
chat; chat ships before tiny transformers. Scope discipline is the answer.

## The Eve lesson

`/home/crow/repos/eve` is the user's 2023 Atomspace attempt. Reading its
code in April 2026, two facts stood out:

1. **Every subsystem was individually present.** Docker was configured.
   CogServer ran on port 18080. Python bindings were imported. Link
   Grammar was wired. A Telegram chat loop was running. Atom creation code
   existed in `lab/atomspace.py`.
2. **The semantic core was never connected.** `atomspace.load_brain()` was
   commented out. The Telegram bot ran shell subprocesses instead of
   reasoning. The "connect these subsystems into a learning loop" step
   never happened.

Eve died of an integration gap, not of missing components. The failure was
structural: the wiring between subsystems was a separate, manual, fragile
task that never reached "finished."

### Versus's mitigation

Terraform-generated integration is declarative, not manual. "Forgot to
wire up X" becomes structurally difficult to produce: if the chat state
fragment is present, the resolver auto-enables atomspace and walker; the
docker-compose includes all three containers; the inter-container
wiring (ports, volumes, environment) is declared in the generated compose
file.

A bug is still possible, but it would be a bug in Terraform code that can
be fixed and re-applied idempotently. It cannot be "the wiring was never
written in the first place."

### The single-flow discipline

The mitigation above is necessary but not sufficient. We also commit to:

> Pick one concrete end-to-end data flow (corpus bytes in -> generated
> text out -> provenance intact) and wire that **before** any subsystem
> is "complete."

No subsystem perfectionism until the loop runs. A half-functional walker
feeding a half-functional generator producing stilted-but-real output
beats a perfect walker with no generator and a perfect generator with no
walker.

This is why [walker.md](./walker.md) is the immediate next build target,
and ingest + chat come after: the walker alone does not close the loop,
but walker + toy corpus + telnet-to-CogServer is enough for a first
integration test.
