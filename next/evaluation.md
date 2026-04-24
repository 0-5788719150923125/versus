# Evaluation and Falsifiability

*How we know it is working, or when to admit it is not.*

## Realistic success bar

Pure-symbolic systems have never produced GPT-class fluency. Fragment
stitching (keeping fluent substrings intact rather than regenerating from
logical form) may beat classical NLG's ceiling, but that is a research
bet, not a known recipe.

The realistic near-term target is:

- **Coherent, grounded, short-form responses** on topics the system has ingested.
- **Full provenance traceability:** every emitted phrase links back to source atoms, which link back to source corpus documents.
- **Visible structural learning over time:** ingesting more text produces visibly different and better responses.

Not realistic at prototype scale:

- Matching 7B+ LLM fluency.
- Arbitrary creative generation beyond what the corpus supports.
- Broad world-knowledge breadth.

Versus will lose to GraphRAG on fluency and breadth. It should win on
explainability, autonomy from pre-trained models, and inference-time cost.

## Falsification metrics

The MVP is validated by these five metrics, not by vibes. Any of them
going flat for a reasonable training budget is a red flag. Any two going
flat simultaneously is a falsification event and changes what we do next.

### M1: Compression ratio

Size of walker-reachable atoms divided by original corpus size. Should
**decrease** over wake / sleep iterations as the system learns to re-derive
more of the corpus from fewer atoms.

- Flat: no structural compression is happening; the system is accumulating
  noise, not learning.
- Increasing: something is catastrophically wrong (probably runaway atom
  creation with no consolidation).

### M2: Held-out reconstruction

Fraction of held-out sentences that the walker can regenerate when seeded
with their initial tokens. Should **increase** monotonically during training.

- Flat: the learned structure does not generalize beyond what it has seen.
- Perfect (100%): overfitting or the held-out is not actually held out.

### M3: Property stabilization rate

Fraction of decay-enabled properties whose delta-per-sleep-phase has
dropped below a threshold. This is the **operational definition of
"principles emerging."**

- Should grow over many cycles, then plateau near a saturation level.
- Flat at zero: no principles forming; the system is perpetually plastic
  with no long-term learning.
- Rapid 100%: over-stabilization; the system has frozen and is no longer
  learning anything new.

### M4: Generation coherence

Periodic human spot-check on 10 prompts, rated 1-5 on three axes: topic
coherence, grammaticality, factual consistency with the source corpus.

Sanity check, not a leaderboard metric. Catches cases where M1-M3 go
"well" but the output is garbage.

### M5: Integration breadth

Number of subsystem interactions working end-to-end. This is the
eve-lesson metric (see [historical.md](./historical.md)).

Concretely: can the system do **corpus bytes in -> generated text out with
full provenance** without human intervention at any seam?

- If this stalls below 3 distinct working interactions (e.g.  ingest <-> walker <-> generation), versus has rebuilt eve's failure mode and the slice has failed.

## Falsification triggers

The slice has failed if **after a reasonable training budget**:

- M1 does not decrease, OR
- M3 stays at zero, OR
- M5 stalls below 3 working subsystem interactions

That is an acceptable outcome; it just means we pivot. Likely pivots:

- **If M1/M2 flat but M5 working:** the architecture is integrating fine
  but the learning rule is wrong. Iterate on the learning rule.
- **If M5 stalls:** integration problem. Go back to `../eve`'s lesson and
  pick a single end-to-end flow, wire it, then expand.
- **If M3 stays at zero but everything else looks okay:** decay rates are
  wrong or stabilization threshold is wrong. Tune.
- **If nothing works:** this pure-symbolic path may not be tractable at
  prototype scale. Revisit the fallback (typed graph DB + retrieval
  baseline, not Hyperon).
