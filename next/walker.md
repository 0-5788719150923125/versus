# Walker Module (next build target)

*The walker is the first cognitive-layer subsystem to build on top of the
substrate. It is the mechanism that unifies learning, inference, and
generation (see [commitments.md](./commitments.md) § 7).*

## Scope for this build

Build **only the learning walker**. Specifically, stages A through D of
`learn` V1's pipeline adapted to versus's substrate:

- **Stage A (wake):** read corpus tokens (mock / in-memory for now),
  emit FragmentAtom and PairAtom observations, increment `count`
  properties.
- **Stages B-D (sleep):** apply log-decay to all decay-enabled
  properties, compute mutual information on PairAtoms, cluster words
  into WordClassAtoms via agglomerative clustering (simple version for
  MVP; no Gaussian Orthogonal Ensemble yet).

Explicitly out of scope for this build:

- Inference walks (not needed until chat module)
- Generation walks (not needed until chat module)
- Real corpus ingest (ingest module is a separate target)
- Link Grammar MST parsing (stages E-G of `learn` V1; later)
- Disjunct induction (stages H-J; later)
- Long-distance statistics (stages K-L; later, and V1 itself is only
  partial here)
- Tiny transformer SelectorAtoms (deferred per commitment)

## Module structure

Mirror the `atomspace/` module layout:

    walker/
    |-- main.tf
    |-- variables.tf
    |-- outputs.tf
    `-- templates/
        |-- walker.scm.tftpl       main walker loop
        |-- wake-phase.scm.tftpl   stage A implementation
        |-- sleep-phase.scm.tftpl  stages B-D implementation
        `-- walker-config.scm.tftpl runtime config derived from state fragment

### Inputs (variables.tf)

- `config` (any, default `{}`): the merged `services.walker` config slice.
- `atomspace_endpoint` (object): host + port of the running CogServer,
  passed from `module.atomspace[0].cogserver_endpoint`.
- `atomspace_generated_dir` (string): where the walker.scm file should
  land (typically the same `.versus/` the atomspace module uses).

### Outputs (outputs.tf)

- `walker_script_path`: path to the generated `walker.scm`.
- `walker_runtime_config_path`: path to the generated `walker-config.scm`.

### What it generates

At apply time, `walker/main.tf` writes:

- `.versus/walker.scm` - main loop entry point.
- `.versus/wake-phase.scm` - stage A implementation.
- `.versus/sleep-phase.scm` - stages B-D implementation.
- `.versus/walker-config.scm` - parameters (cycle durations, MI threshold,
  cluster size, etc.) derived from the state fragment.

The walker container starts running `walker.scm` which `(load ...)`s the
other three, loops wake/sleep phases forever, and exits only on signal.

## Walker loop pseudocode

```scheme
;; walker.scm
(use-modules (opencog) (opencog exec))
(load "/opt/versus/atom-schema.scm")
(load "/opt/versus/decay-rules.scm")
(load "/opt/versus/walker-config.scm")
(load "/opt/versus/wake-phase.scm")
(load "/opt/versus/sleep-phase.scm")

(define (walker-main-loop)
  (let loop ((cycle 1))
    (display "=== wake cycle ") (display cycle) (newline)
    (wake-phase versus-wake-duration-tokens)
    (display "=== sleep cycle ") (display cycle) (newline)
    (sleep-phase)
    (loop (+ cycle 1))))

(walker-main-loop)
```

## Wake phase (stage A)

```scheme
;; wake-phase.scm - pseudocode
(define (wake-phase budget)
  (let loop ((remaining budget))
    (if (> remaining 0)
      (let* ((tokens (corpus-next-tokens versus-fragment-min-size))
             (fragment (ensure-fragment-atom tokens))
             (pairs (token-pairs-within-window tokens versus-pair-window)))
        (increment-property fragment "count" 1.0)
        (for-each
          (lambda (pair) (increment-pair-count pair))
          pairs)
        (loop (- remaining 1))))))

(define (ensure-fragment-atom tokens)
  ;; look up or create a FragmentAtom for this token sequence
  ;; initialize defaults via versus-init-atom if newly created
  ...)

(define (increment-pair-count pair)
  ;; ensure PairAtom exists, increment "count" by 1.0
  ...)
```

For the initial build, `corpus-next-tokens` reads from a tiny in-memory
string list (say, 20 short sentences). Real fineweb-edu ingest comes with
the ingest module.

## Sleep phase (stages B-D)

```scheme
;; sleep-phase.scm - pseudocode
(define (sleep-phase)
  (display "  applying decay...") (newline)
  (versus-apply-decay-all-types 1)

  (display "  computing MI on pairs...") (newline)
  (for-each
    (lambda (pair-atom)
      (let* ((p-ij (pair-joint-probability pair-atom))
             (p-i (left-marginal pair-atom))
             (p-j (right-marginal pair-atom))
             (mi (- (log p-ij) (log (* p-i p-j)))))
        (cog-set-value! pair-atom (Predicate "mi") (FloatValue mi))))
    (cog-get-atoms 'PairAtom))

  (display "  agglomerative clustering...") (newline)
  (cluster-word-classes versus-cluster-mi-threshold))
```

Clustering is the fuzziest part of the MVP. The simplest first pass:
single-link agglomerative using MI as the similarity measure, stopping
when the threshold drops below a configured value. This is crude compared
to V1's Gaussian Orthogonal Ensemble approach, but "crude and working"
beats "sophisticated and not yet implemented."

## State fragment

A new `states/walker.yaml` enables the walker service and parameterizes
cycle behavior:

```yaml
services:
  walker:
    core:
      image: opencog/learn:latest        # same image as cogserver
      cycles:
        wake:
          duration_tokens: 10000
        sleep:
          mi_threshold: 2.0
          cluster_size_min: 3
      corpus:
        source: in_memory_demo           # real corpus comes with ingest
```

Adding `"walker"` to `states` in tfvars enables everything.

## Resolver wiring

`walker_enabled` is already implemented in the resolver as presence of
the `walker` key in service_configs. No resolver changes needed.

`module.walker` block in root main.tf (uncomment and wire):

```hcl
module "walker" {
  count  = module.resolver.walker_enabled ? 1 : 0
  source = "./walker"

  config                   = lookup(module.config.service_configs, "walker", {})
  atomspace_endpoint       = module.atomspace[0].cogserver_endpoint
  atomspace_generated_dir  = module.atomspace[0].generated_dir
}
```

Depends on `module.atomspace[0]`; must be gated on `atomspace_enabled`
being true (which the resolver already ensures when walker is enabled).

## Docker-compose changes

Update the `atomspace/templates/docker-compose.yml.tftpl` to stop hard-
coding `walker_enabled = false` and wire it to the resolver flag.

Current:
```hcl
walker_enabled = false # TODO: wire when walker module lands
walker_image   = local.image
```

New (in `atomspace/main.tf`):
```hcl
# Accept walker_enabled as a variable passed from root main.tf
walker_enabled = var.walker_enabled
walker_image   = var.walker_image    # default to opencog/learn:latest
```

Then root main.tf:
```hcl
module "atomspace" {
  # ... existing ...
  walker_enabled = module.resolver.walker_enabled
  walker_image   = "opencog/learn:latest"
}
```

When walker is enabled, the compose file includes the walker container
block with the same image, running `guile -L /opt/versus /opt/versus/walker.scm`.

## Success criteria for this build

The walker module is "done" when, starting from a clean `terraform destroy`:

1. `terraform apply -var='states=["core","walker"]'` succeeds with no
   errors.
2. Two containers are up: `versus-cog-1` and `versus-walker-1` (or
   similar; whatever Docker names them).
3. Walker logs show alternating wake/sleep cycles with visible output
   per phase.
4. After N sleep cycles (say, N=5 on a 20-sentence toy corpus), querying
   the CogServer reveals:
   - WordClassAtoms exist (clustering produced something)
   - PairAtoms have non-zero MI values
   - At least one atom property has stabilized (delta < threshold)
5. `terraform destroy` cleanly tears down both containers.

M3 (property stabilization rate; see [evaluation.md](./evaluation.md))
should be measurably above zero after this build. If it stays at zero,
the stabilization threshold is wrong, the decay rates are wrong, or the
walker is not actually running the sleep phase.

## Open questions to settle during the build

- **Where does the walker run?** In-process inside the cogserver
  container (simpler, shares memory), or as a separate container
  connecting via CogServer's WebSocket (more isolated, matches Platformer's
  multi-container pattern). Recommend: separate container for the eve-lesson
  reasons (subsystem boundaries visible), but revisit if WebSocket latency
  hurts.
- **How is corpus provided during MVP?** In-memory hardcoded list
  (simplest), a static text file mounted via a volume (slightly more
  realistic), or a tiny HuggingFace sample checked into states/
  (preview of real ingest). Recommend: static text file mounted via a
  volume.
- **Clustering algorithm.** Single-link agglomerative is the crudest
  thing that could work. If it produces degenerate clusters (everything
  merges or nothing does), upgrade to complete-link or average-link, or
  defer to V1's GOE approach. Recommend: start with single-link, raise
  the threshold aggressively, and re-evaluate.
