# Ingest module.
#
# The ingest worker is a static Python script (scripts/ingest.py) that
# runs inside a separate container alongside cog. This Terraform module
# does not generate or write the script; it only exposes paths and a
# resolved-config structure so the atomspace module's docker-compose
# template can mount the script and set the right environment variables.

locals {
  # Static script lives at ingest/scripts/ingest.py in the repo.
  script_dir  = "${path.module}/scripts"
  script_path = "${local.script_dir}/ingest.py"

  # Resolve each configurable, falling back to sensible defaults when
  # the state fragment omits a key. try() is used throughout because
  # lookup() is type-strict on homogeneous any-typed maps.
  core = try(var.config.core, {})

  dataset_source = try(local.core.dataset.source, "HuggingFaceFW/fineweb-edu")
  dataset_config = try(local.core.dataset.config, "sample-10BT")
  dataset_split  = try(local.core.dataset.split, "train")

  fragment_min_words = try(local.core.fragments.min_words, 3)
  fragment_max_words = try(local.core.fragments.max_words, 8)

  rate_fragments_per_second = try(local.core.rate.fragments_per_second, 5)
  rate_max_fragments        = try(local.core.rate.max_fragments, 1000)

  role_tag = try(local.core.role_tag, "")

  # Resolved config, collapsed to a flat map for easy threading through
  # the compose template as environment variables.
  resolved = {
    dataset_source            = local.dataset_source
    dataset_config            = local.dataset_config
    dataset_split             = local.dataset_split
    fragment_min_words        = local.fragment_min_words
    fragment_max_words        = local.fragment_max_words
    rate_fragments_per_second = local.rate_fragments_per_second
    rate_max_fragments        = local.rate_max_fragments
    role_tag                  = local.role_tag
  }
}
