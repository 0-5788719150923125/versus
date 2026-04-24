# Root orchestration for versus.
#
# Pattern borrowed from ../platformer: state-fragment YAML under states/
# is deep-merged by the imported config module into service_configs,
# which the resolver analyzes to produce enable flags, which gate
# conditional instantiation of versus-specific service modules.

# ---------------------------------------------------------------------
# Config: imported from ../platformer (Shape A, filesystem-level import)
# ---------------------------------------------------------------------

module "config" {
  source = "../platformer/config"

  states = var.states

  # Pass an absolute path so the imported config module's path.module
  # prefix (which is correct for Platformer's own relative ../states
  # usage) does not misresolve versus's state fragments.
  states_dirs = [abspath("${path.root}/states")]

  # aws_region is unused by versus but the platformer config module
  # declares the variable. We accept its default.
}

# ---------------------------------------------------------------------
# Resolver: versus-specific enable-flag logic
# ---------------------------------------------------------------------

module "resolver" {
  source = "./resolver"

  service_configs = module.config.service_configs
}

# ---------------------------------------------------------------------
# Atomspace: the substrate. Generates Scheme and docker-compose,
# spawns CogServer via local-exec (portal/docker.tf pattern).
# ---------------------------------------------------------------------

# ---------------------------------------------------------------------
# Ingest: corpus-streaming worker. Data module that has to exist BEFORE
# atomspace in the dependency graph because atomspace's generated
# docker-compose embeds the ingest service's env vars and script-dir.
# The ingest module itself creates no resources; it is a pure
# configuration transformer.
# ---------------------------------------------------------------------

module "ingest" {
  count  = module.resolver.ingest_enabled ? 1 : 0
  source = "./ingest"

  config = lookup(module.config.service_configs, "ingest", {})
}

# ---------------------------------------------------------------------
# Atomspace: the substrate. Generates Scheme and docker-compose,
# spawns CogServer via local-exec. When ingest is enabled, the
# generated compose also includes the ingest container.
# ---------------------------------------------------------------------

module "atomspace" {
  count  = module.resolver.atomspace_enabled ? 1 : 0
  source = "./atomspace"

  config = lookup(module.config.service_configs, "atomspace", {})

  ingest_enabled    = module.resolver.ingest_enabled
  ingest_script_dir = try(module.ingest[0].script_dir, "")
  ingest_config     = try(module.ingest[0].resolved_config, {})
}

# ---------------------------------------------------------------------
# The chat CLI client is a static Python script at repo root (chat.py)
# that reads cogserver connection details from environment variables.
# It is intentionally not a Terraform module: its output is neither
# generated code nor a managed resource, just a convenience wrapper
# for the human operator.
#
# Other service modules land here as they come online:
#
# module "walker"  { count = module.resolver.walker_enabled  ? 1 : 0; source = "./walker";  ... }
# module "storage" { count = module.resolver.storage_enabled ? 1 : 0; source = "./storage"; ... }
# ---------------------------------------------------------------------
