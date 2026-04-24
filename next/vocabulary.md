# Vocabulary

*Terms used across versus's design. When in doubt, definitions here win
over intuition from the field at large (these are versus-specific
meanings).*

## Atom types

**FragmentAtom** - an ordered sequence of WordNodes representing a
surface-text span, e.g. "the quick brown fox" is a FragmentAtom whose
content is `[WordNode "the", WordNode "quick", WordNode "brown", WordNode
"fox"]`. Granularity target for the MVP: 3-8 words per fragment.

Default properties:
- `count`: how often this fragment was observed (slow decay, long memory)
- `activation`: walker-induced activation level (fast decay, short memory)

**ConceptAtom** - a versus-specific ConceptNode used to tag FragmentAtoms
with topical or semantic labels. Concept membership is learned, not
hand-authored.

Default properties:
- `gate`: learnable selection weight used in soft-gated walker choices
- `stability`: how log-decay-resistant the gate is (very slow decay; this
  is itself a long-memory signal)

**DisjunctAtom** - a Link Grammar disjunct induced from MST-parsing
corpus sentences. A disjunct is a word's "connector pattern" encoding
what it can link to on its left and right.

Default properties:
- `count`: observation count

**PairAtom** - observed co-occurrence of two WordNodes within some window.
The raw input to mutual-information calculation.

Default properties:
- `count`: raw co-occurrence count
- `mi`: computed mutual information (updated during sleep)

**SelectorAtom** *(deferred)* - a first-class atom whose content is a
tiny transformer (n_dim ~= 4 micro-network) trained locally on a specific
next-hop selection task. Not in MVP scope. When added, every location
that calls tiny-transformer selection must have a soft-gate fallback so
the system degrades gracefully if the SelectorAtom is absent or untrained.

## Mechanisms

**Walker** - a loop that traverses the atom graph, carrying and
transforming a hidden state at each step. One mechanism, three modes:

- **Learning walk:** reads corpus tokens, updates atom properties,
  accumulates structure.
- **Inference walk:** starts at query atoms, walks to an answer, the
  trajectory is the provenance.
- **Generation walk:** starts at seed concepts, walks through
  FragmentAtoms emitting surface text on each transition.

**Wake phase** - walker reads corpus and writes new atoms or increments
property values. No clustering, no MI computation, no decay.

**Sleep phase** - walker does not read corpus. It consolidates: applies
log decay, computes mutual information on PairAtoms, clusters words into
WordClassAtoms, extracts disjuncts from accumulated parses, promotes
stabilized properties to "principle" status.

The wake/sleep alternation is pragmatic: counting and marginal computation
cannot happen simultaneously without corrupting the counts. See `learn`
V1 for the prior art.

**Modulus programming** - hash/modulus-indexed selection from atom lists.
User's term for the native data-structure operation of "pick item at
index `hash(key) mod N`." Maps cleanly onto the Atomspace's own hash-keyed
atom storage.

**Soft-gated selection** - probabilistic selection from a candidate list
weighted by softmax over learnable gate values. Gate values are updated
by direct increment/decrement based on observed outcomes. Differentiable-
style without backpropagation.

## Properties and primitives

**Log decay** - the update rule applied to decay-enabled properties
during sleep: `value_{t+1} = value_t * (1 - decay_rate * log(1 + elapsed))`,
clamped at zero. Different properties have different decay rates,
producing multi-timescale dynamics.

**Principle** *(operational definition)* - any atom property, gate value,
or SelectorAtom parameter set whose value has stabilized under log decay
over multiple sleep phases. Principles emerge; they are not extracted by
a separate subsystem. See [evaluation.md](./evaluation.md) for how
stabilization is measured (metric M3).

## Process roles

**CogServer** - the running OpenCog process. Serves HTTP/WebSocket on
port 18080 and telnet on 17001. Hosts the Atomspace in RAM, loads the
generated Scheme on startup, and accepts walker / ingest / chat
connections.

**Walker process** *(not yet built)* - a Guile process driving wake/sleep
cycles against the CogServer. Runs as a separate container; connects via
CogServer's WebSocket or runs in-process depending on implementation
choice.

**Ingest worker** *(not yet built)* - a Guile process (possibly with a
Python subprocess for HuggingFace datasets) that streams corpus text and
emits tokens to the walker.

**Chat endpoint** *(not yet built)* - an HTTP server that turns user
prompts into inference walks and returns fragment-stitched responses with
provenance attached.

## Document conventions

**State fragment** - a YAML file under `states/`. Contains top-level
`services:` and/or `matrix:` keys. Deep-merged with other selected
fragments at apply time.

**Template** - a `.tftpl` file consumed by `templatefile()`. Emits
Atomese, Scheme, docker-compose, or other engine-layer artifacts at apply
time.

**Engine artifact** - any file under `.versus/`. Generated; gitignored;
consumed by runtime processes (CogServer, walker, ingest, chat).
