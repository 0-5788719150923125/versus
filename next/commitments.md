# Design Commitments

*The unchanging core. These are settled, not up for re-debate in routine
iteration. If one genuinely needs revisiting, do so explicitly as a design
event, not a drive-by edit.*

## 1. Classic OpenCog Atomspace, not Hyperon

Production-tested for 15+ years, architect-maintained by Linas Vepstas,
chosen on both practical and aesthetic grounds.

Hyperon (SingularityNET's MeTTa-based successor) is rejected on ecosystem
grounds: crypto-adjacent funding, flashy-but-unfinished implementation, and
a community orientation that does not match this project's.

If classic Atomspace proves structurally unworkable, the fallback is a
typed graph DB (Kuzu, Neo4j, DuckDB property graphs) with a hand-rolled
atom-like layer. **Not** Hyperon.

## 2. No neural component at MVP scope

Chat, inference, and learning run through Atomspace primitives only:
pattern matcher, graph rewriting, iterative loops that transform state
across pointer traversals, information-theoretic updates over atom float
properties.

Tiny transformer SelectorAtoms (n_dim ~= 4 micro-networks as first-class
atoms) are a planned enhancement but deferred. The substrate must work with
soft-gate fallback selection before any neural content is introduced.

## 3. Guile primary, Python only where unavoidable

Walker, wake/sleep driver, inference loop, and generation loop are Scheme.

- Guile runs in-process with CogServer (no IPC overhead).
- Native Atomspace bindings are faster than the Python wrapper.
- `learn` V1 is already Scheme-primary.
- Fewer integration points = fewer brittle seams.

The foreseeable Python exception is the ingest worker (HuggingFace
datasets client). Even there, prefer thin subprocess boundaries with a
narrow interface, not deep Python integration.

## 4. Autonomous structure discovery, not hand-curated ontology

"Principles" is an intentionally general term for whatever the system
needs to extract: concepts, features, grammatical structure, semantic
clusters, transition patterns.

Operationally, a principle is an atom property value that has stabilized
under log decay over multiple sleep cycles. Principles emerge; they are
not extracted by a separate subsystem. No hand-labeled training data. No
hand-authored ontology. No taxonomies imported from elsewhere.

## 5. Hash-maps, pointers, and loops

The substrate is atoms (hash-keyed entries), links (literal pointers
between atoms), and iterative loops that update state tick by tick.

This is not metaphor; it is how the Atomspace is implemented.

Design constraint: every atom is inspectable, every link is traceable,
every state change happens inside a named loop we can point at. No opaque
cognitive-architecture magic; no hidden update paths; no black boxes.

## 6. YAML authoring surface, Atomese engine surface, nothing between

Operators edit only `states/*.yaml` (and occasionally `terraform.tfvars`).
Terraform generates all Atomese / Scheme / docker-compose artifacts at
apply time.

If hand-authoring Scheme feels tempting during some task, the HCL layer is
failing to earn its weight and must be fixed, not worked around.

## 7. Walker mechanism unifies three loops

One recurrent graph-walker, three modes:

- **Learning walk:** walks corpus, updates atom properties, drives
  wake/sleep phases.
- **Inference walk:** starts at query atoms, walks to an answer, the
  trajectory is the provenance.
- **Generation walk:** starts at seed concepts, walks through
  FragmentAtoms emitting surface text as transitions.

One mechanism, three jobs. Integration-by-design, not integration-by-glue.
This is the architectural answer to the eve lesson (see
[historical.md](./historical.md)).
