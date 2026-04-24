# Platformer Coupling

*How versus depends on Platformer and why, plus the two compatibility
patches that landed during scaffolding.*

## The import

Versus imports Platformer's `config/` module as a child module via
filesystem path:

```hcl
module "config" {
  source = "../platformer/config"
  states = var.states
  states_dirs = [abspath("${path.root}/states")]
}
```

This is deliberately tight coupling for now. A clone of `platformer` must
exist at `../platformer` relative to versus. If it does not, `terraform
init` fails on module resolution.

## Why reuse instead of copy

Three reasons.

1. **The config module is battle-tested.** It loads YAML fragments,
   deep-merges them with `provider::deepmerge::mergo()` using union mode,
   handles directory fallbacks, and validates state names. Re-writing
   this for versus would duplicate working code and guarantee drift.
2. **The state-fragment pattern is the whole point.** Versus's design
   premise is that Platformer's GitOps-style composable state fragments
   are the right authoring surface for systems beyond cloud
   infrastructure. Importing the module is a direct demonstration.
3. **Eventual Platformer integration.** Versus is likely to become a
   service fragment inside Platformer's broader composition later. Using
   the same config module makes that integration a file-move rather than
   a refactor.

## The three import "shapes"

Recorded here for when this decision gets revisited:

- **Shape A: filesystem-level import** (current). `source =
  "../platformer/config"`. Tight coupling; both repos must be cloned side
  by side. Fastest to set up.
- **Shape B: extracted framework package.** Pull `config/` out of
  Platformer into a separate `platformer-framework` repo or git submodule
  that both projects depend on. Clean separation; requires coordinated
  refactor on Platformer's side.
- **Shape C: copy-and-drift.** Inline a copy of `config/` into versus.
  Zero coupling, guaranteed drift. Rejected.

Current plan: stay on Shape A until versus needs to be distributed
independently (PyPI, public demo, handoff to a collaborator without
Platformer). At that point, refactor to Shape B. Not a day-one concern.

## The two compatibility patches

Both landed in Platformer during scaffolding, both backward-compatible
with Platformer's own usage.

### Patch 1: default `aws_region` in `config/variables.tf`

```hcl
variable "aws_region" {
  description = "Current AWS region for deployment (used in validation error messages)"
  type        = string
  default     = "us-east-2"          # <-- added
}
```

Without this, versus would have to pass a meaningless placeholder value
(the variable is only used in AWS-specific validation error messages that
never fire for versus's use). Adding the default lets versus import without
thinking about AWS at all.

### Patch 2: absolute-path support in `config/main.tf`

```hcl
locals {
  # Resolve each states_dirs entry: absolute paths are used verbatim,
  # relative paths are prefixed with path.module for backward compatibility
  # with Platformer's own usage (which passes e.g. "../states" to mean
  # "up one level from the config module").
  resolved_dirs = [
    for dir in var.states_dirs :
    startswith(dir, "/") ? dir : "${path.module}/${dir}"
  ]

  state_paths = {
    for state in var.states :
    state => coalesce([
      for dir in local.resolved_dirs :
      "${dir}/${state}.yaml" if fileexists("${dir}/${state}.yaml")
    ]...)
  }
  # ...
}
```

Without this, any `states_dirs` entry gets `path.module` prefixed, which
for an imported child module means "inside the platformer clone's config/
subdirectory." Versus's `states/` is somewhere else entirely.

The fix: if the directory starts with `/` (absolute), use it verbatim.
Relative paths still get prefixed for Platformer's own usage. Versus
passes `abspath("${path.root}/states")` which always evaluates to an
absolute path.

## Invariants to preserve

Any future change to Platformer's `config/` module should keep these true,
or we have to update versus:

- `states` input: list of strings, each matching `^[a-z0-9-]+$`.
- `states_dirs` input: list of strings, absolute paths used verbatim,
  relative paths prefixed with `path.module`.
- `service_configs` output: map, each key is a service name, each value
  is the deep-merged config for that service.
- `matrix_configs` output: map; versus currently does not use it but we
  leave the hook open.
- Deep-merge semantics: union mode (map-merge recursive, list-dedup).
