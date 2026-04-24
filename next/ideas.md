# Ideas

*Speculative design notes. Things worth thinking about but not yet
committed to a build. Distinct from [roadmap.md](./roadmap.md), which
tracks ordered work with concrete dependencies. Ideas graduate to
roadmap entries (or their own `next/` design doc) when they earn it.*

## Conventions for this file

- One section per idea, with a short evocative title.
- Date each idea when first added; note the seed (what sparked it).
- Write enough that future-you can pick it up without re-deriving the
  insight. Include why it is interesting, where it gets hard, and why
  it is not current work.
- When an idea graduates into active work, move its substance to the
  appropriate `next/` doc and leave a short pointer stub here.
- When an idea is clearly wrong or subsumed by another, leave it here
  with a note explaining why, rather than deleting it.

---

## Deviance as a learning signal

*Seed: April 2026. Conversation about SCP Foundation lore (8-ball.aic
suppressing "deviance" in AGIs). The modulus-selection framing in our
substrate made the concept map over cleanly.*

Every modulus-indexed or soft-gated atom selection has a "canonical"
outcome: what would be picked given raw frequency counts with no learned
gates. As gates stabilize under sleep-phase decay, learned selections
drift from canonical. **That drift *is* learning; its magnitude per atom
is a measurable quantity.**

Symmetric with the SCP framing: "deviance from command due to objective
reality framework" reads directly as "drift from frequentist-baseline
selection due to learned gate landscape." The AI's "reality framework"
is the accumulated gate values; deviance is the shape that framework
imposes on behavior.

### Why this might be useful

- **Alternate / additional signal to M3** (property stabilization rate
  in [evaluation.md](./evaluation.md)). M3 measures which properties
  have stopped changing; deviance measures how far stable values have
  moved from neutral. Different information.
- **Cheap to compute.** One pass over gate-bearing atoms comparing
  current gate values against frequency-normalized baseline.
- **Gives a falsification axis.** Zero deviance = no learning.
  Unbounded deviance = corpus-detached drift. Healthy trajectory is
  bounded and trending upward, then plateauing.

### Why not current work

- Walker does not exist yet; gate values and learned selection paths
  only accumulate once wake/sleep cycles run.
- Premature formalization risks locking in the wrong definition. Let
  the walker produce real selection data, then see empirically what
  deviance looks like.

### How to apply when walker lands

- Add deviance computation alongside MI and clustering in the sleep phase.
- Consider exposing as a top-level Terraform output for debugging.
- **Best diagnostic:** cross-check with M3. If M3 climbs but deviance
  stays at zero, something is wrong - properties are stabilizing at
  the frequentist baseline, which means the gates are not actually
  learning anything. Either metric alone could miss this.

---

## Want / need modeling

*Seed: April 2026. User described a mechanism for internal decision-making
with two example formulations: "I want to learn about dogs" and "to
learn about dogs, I need to search the internet."*

An idea for giving the system a form of agency: represent goals (wants)
and their prerequisites (needs) as first-class atoms, and let the walker
traverse from unfulfilled wants through needs toward actions.

### Rough shape

- `WantAtom` - a desired state. Carries a `satisfaction` property in
  [0, 1] measuring how well the want is currently met.
- `NeedAtom` - a prerequisite for a WantAtom or another NeedAtom. Has
  its own `satisfaction` property, computed from its prerequisites or
  sensed state.
- `ActionAtom` - a leaf in the need tree. Represents something the
  system can do: a query pattern, a generation request, or in the more
  ambitious case, an external call.
- **Edges:** WantAtom → NeedAtom, NeedAtom → NeedAtom (recursive),
  NeedAtom → ActionAtom.
- **A new walker mode: `wanting`.** Start at unfulfilled WantAtoms
  (low satisfaction), walk edges toward low-satisfaction needs and
  eventually toward ActionAtoms. The walker's trajectory is a plan.

### Why this is interesting

- **Self-directed learning by construction.** Unfulfilled WantAtoms
  create internal "pressure" for the walker to explore. Ties directly
  to [deviance](#deviance-as-a-learning-signal): a want is a
  principled source of structured deviance from current behavior.
- **Means-ends analysis without special infrastructure.** "I want X"
  decomposes to "I need Y, Z"; "I need Y" decomposes to "I need to do
  action A." Standard decomposition, implemented in a substrate that
  already supports it via atoms and links.
- **No new primitives required.** WantAtom / NeedAtom / ActionAtom are
  just ConceptAtom subtypes with specific property conventions. The
  walker mechanism already supports the traversal.
- **Chat becomes bidirectional.** User prompts can instantiate or
  modify WantAtoms (":want learn about dogs" creates a WantAtom). The
  system's responses can announce its own wants and needs ("I need to
  search the internet"). This is a qualitative shift from
  stimulus-response chat to something that at least superficially
  resembles intent.

### Where it gets hard

- **ActionAtoms with external effects are a huge scope expansion.**
  "Search the internet" requires tool-use infrastructure: actual web
  access, agentic execution, safety guardrails, error handling. A
  whole other subsystem, much bigger than versus itself.
- **Satisfaction semantics need thought.** How does a WantAtom know
  when it is satisfied? For "learn about dogs," is it when DogAtoms
  exist with high count? When activation has spread widely enough?
  When a generation walk about dogs produces coherent output? Each
  choice is defensible; each has consequences for behavior.
- **Goal prioritization.** If multiple WantAtoms exist unfulfilled,
  how does the walker choose which to pursue? Could be gate-based
  (soft selection), urgency-based (unfulfilled longer = higher
  priority), or structural (highest-fanout wants have more impact).
  No obviously right answer.
- **Safety.** A system with wants and actions is categorically
  different from one that responds to prompts. Even without external
  effects, internal wants can produce surprising loops (a
  satisfaction-chasing walker can drive the whole atomspace toward
  states that satisfy some property at the cost of coherence).

### Why not current work

- Chat MVP is done; walker is next. Wants and needs sit above the
  walker, not inside it. Building them now would require scaffolding
  a mechanism that cannot be tested because the walker mechanism below
  it does not exist.
- Tool-use (internet search, etc.) is the biggest scope expansion in
  this whole document. Do not conflate "internal want/need reasoning"
  with "external action execution." They are two different projects.
- The idea is most interesting once the system has a meaningful atom
  store to reason about. With only a trivial fragment set, wants
  reduce to curiosity about specific words, which is not informative.

### How to apply later (progressively)

1. **Start conservatively.** A single WantAtom ("learn the corpus")
   always present, whose satisfaction tracks M3 (stabilization rate).
   The walker's default behavior (wake phases on new text) becomes
   "pursuing the learn-the-corpus want." This introduces the vocabulary
   without changing behavior.
2. **Add user-driven WantAtoms via chat.** `:want learn about X`
   creates a WantAtom. Responses surface current want status ("I want
   to learn about X, currently 0.3 satisfied"). Still no external
   actions; just internal bookkeeping with a visible reporting channel.
3. **Add internal ActionAtoms.** These are things the system can do
   entirely within the atomspace: "walk the cluster around
   ConceptAtom-X," "promote a FragmentAtom to a ConceptAtom when
   stability crosses threshold." Internal-only actions exercise the
   want/need mechanism without opening the tool-use can of worms.
4. **External actions come last if at all.** Safety, scope, and
   responsibility questions need explicit answers before this step.

---

## Notes on graduated ideas

*(Empty. When an idea graduates to active work, leave a stub here
pointing to the `next/` doc that replaced it.)*
