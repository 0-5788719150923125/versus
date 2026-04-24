# versus

An autonomous probabilistic-symbolic AI, prototyped as a Terraform module.
Backed by classic OpenCog Atomspace. Chat via grounded fragment composition.
Built with Platformer's "good bones": state-fragment YAML, deep-merge
composition, declarative artifact generation.

**Status:** scaffolding complete. `terraform apply` generates Atomese and
docker-compose from YAML and brings up a CogServer on `localhost:18080`.
Walker, ingest, and chat subsystems are not yet built. See
[next/roadmap.md](./next/roadmap.md) for what comes next and
[next/walker.md](./next/walker.md) for the immediate next build target.

## Quickstart

Prerequisites:
- Terraform >= 1.8
- Docker with the `docker compose` subcommand
- A clone of `platformer` at `../platformer` with the compatibility patches
  applied (see [next/coupling.md](./next/coupling.md))

```
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

This produces `.versus/atom-schema.scm`, `.versus/decay-rules.scm`,
`.versus/docker-compose.yml`, and brings up `versus-cog-1`. To tear down:
`terraform destroy`.

Interact with the running CogServer:

```
curl http://localhost:18080/            # returns 404; confirms it is alive
docker exec -it versus-cog-1 guile      # drops into Guile inside the container
```

Inside Guile:

```
(use-modules (opencog))
(load "/opt/versus/atom-schema.scm")
(load "/opt/versus/decay-rules.scm")
(versus-init-atom (Concept "hello") "fragments")
(versus-known-types)                    ; => (concepts disjuncts fragments)
```

## Repository layout

```
versus/
  README.md                  this file; orientation layer
  LICENSE
  main.tf                    root orchestration
  providers.tf               provider declarations
  variables.tf               tfvars contract
  outputs.tf                 surfaced state for debugging
  terraform.tfvars.example   reference tfvars
  .gitignore

  resolver/                  versus-specific enable-flag logic
  atomspace/                 substrate module: schema and docker generation
  states/                    operator-authored YAML; edit only here

  next/                      working documents; see "For deeper context"
```

## For deeper context

The `next/` directory holds focused documents on specific aspects of the
design. Read in any order; each is self-contained.

- [next/roadmap.md](./next/roadmap.md) - build order and priorities
- [next/walker.md](./next/walker.md) - **immediate next build target**
- [next/commitments.md](./next/commitments.md) - the seven design commitments that should not drift
- [next/evaluation.md](./next/evaluation.md) - falsifiability metrics and realistic success bar
- [next/historical.md](./next/historical.md) - URE post-mortem and the Eve lesson (the design's backward-looking rationale)
- [next/coupling.md](./next/coupling.md) - Platformer import story, the two patches, and the escape path
- [next/vocabulary.md](./next/vocabulary.md) - versus-specific terminology (FragmentAtom, ConceptAtom, walker, principle, etc.)
- [next/gotchas.md](./next/gotchas.md) - scaffolding iteration log; check before re-debugging

## Philosophy

Operators never touch three things:
1. Scheme / Atomese (generated from state fragments)
2. docker-compose (generated from state fragments)
3. Walker / ingest / chat configs (generated, consumed by Guile processes)

Operators always touch one thing: YAML under `states/`.

If editing Scheme by hand feels tempting, the HCL layer is failing to
earn its weight and should be fixed, not worked around. See
[next/commitments.md](./next/commitments.md) § 6 for why.

## Living-document conventions

This README and the `next/` docs are living. Update as work progresses.

README itself gets edited only for: **Status** (top), new next/ doc
listings, and layout changes. Everything deeper belongs in `next/`.

Stable next/ docs ([commitments.md](./next/commitments.md),
[historical.md](./next/historical.md), [evaluation.md](./next/evaluation.md))
are not edited in routine iteration. Revising them is a design event and
should be deliberate.

Volatile next/ docs ([roadmap.md](./next/roadmap.md),
[walker.md](./next/walker.md), [gotchas.md](./next/gotchas.md)) evolve
as the project does.
