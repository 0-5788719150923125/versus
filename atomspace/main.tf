# Atomspace module
#
# Responsibilities:
#   1. Flatten the schema state-fragment config into a form templates can consume.
#   2. Render three generated artifacts via templatefile(): Scheme atom schema,
#      Scheme decay rules, and a docker-compose.yml.
#   3. Write those artifacts to .versus/ at the repo root.
#   4. Spawn the CogServer container via local-exec (portal/docker.tf pattern).
#
# The operator never sees the generated files; they exist purely as the
# bridge between YAML and the running engine.

locals {
  # Where generated artifacts land. Gitignored via the root .gitignore.
  # Must be absolute: docker-compose resolves relative volume sources
  # relative to the compose file's own directory, which would produce
  # .versus/.versus/ if a relative path were embedded into the template.
  generated_dir = abspath("${path.root}/.versus")

  # --- Schema extraction -------------------------------------------------
  schema_config = lookup(var.config, "schema", {})

  atom_types = [
    for type_name, type_config in local.schema_config : {
      name = type_name
      properties = [
        for prop_name, prop_config in lookup(type_config, "properties", {}) : {
          name       = prop_name
          default    = prop_config.default
          decay_rate = prop_config.decay_rate
        }
      ]
    }
  ]

  # --- Core runtime config ----------------------------------------------
  core_config     = lookup(var.config, "core", {})
  image           = lookup(local.core_config, "image", "opencog/learn:latest")
  cogserver_block = lookup(local.core_config, "cogserver", {})
  cogserver_port  = lookup(local.cogserver_block, "port", 18080)
  storage_block   = lookup(local.core_config, "storage", {})
  storage_path    = lookup(local.storage_block, "path", "/data/atoms")

  # --- Template rendering -----------------------------------------------
  atom_schema_scm = templatefile("${path.module}/templates/atom-schema.scm.tftpl", {
    atom_types   = local.atom_types
    generated_on = timestamp()
  })

  decay_rules_scm = templatefile("${path.module}/templates/decay-rules.scm.tftpl", {
    atom_types   = local.atom_types
    generated_on = timestamp()
  })

  docker_compose_yml = templatefile("${path.module}/templates/docker-compose.yml.tftpl", {
    image          = local.image
    cogserver_port = local.cogserver_port
    storage_path   = local.storage_path
    path_generated = local.generated_dir
    walker_enabled = false # TODO: wire when walker module lands
    walker_image   = local.image
    generated_on   = timestamp()
  })

  compose_path = "${local.generated_dir}/docker-compose.yml"
}

# ---------------------------------------------------------------------
# Write generated artifacts. local_file creates parent dirs automatically.
# ---------------------------------------------------------------------

resource "local_file" "atom_schema" {
  filename        = "${local.generated_dir}/atom-schema.scm"
  content         = local.atom_schema_scm
  file_permission = "0644"
}

resource "local_file" "decay_rules" {
  filename        = "${local.generated_dir}/decay-rules.scm"
  content         = local.decay_rules_scm
  file_permission = "0644"
}

resource "local_file" "docker_compose" {
  filename        = local.compose_path
  content         = local.docker_compose_yml
  file_permission = "0644"
}

# ---------------------------------------------------------------------
# Spawn / tear down the CogServer container.
# Pattern: null_resource + local-exec create/destroy provisioners,
# keyed on content hashes so changes to the generated files trigger
# container recreation. Borrowed from ../platformer/portal/docker.tf.
# ---------------------------------------------------------------------

resource "null_resource" "cogserver" {
  depends_on = [
    local_file.docker_compose,
    local_file.atom_schema,
    local_file.decay_rules,
  ]

  triggers = {
    compose_hash = local_file.docker_compose.content_sha256
    schema_hash  = local_file.atom_schema.content_sha256
    decay_hash   = local_file.decay_rules.content_sha256
    compose_path = local.compose_path
  }

  provisioner "local-exec" {
    when    = create
    command = "docker compose -f ${self.triggers.compose_path} up -d"
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "docker compose -f ${self.triggers.compose_path} down"
    on_failure = continue
  }
}
