# Resolver: analyzes merged service_configs, emits per-subsystem enable flags.
#
# Enable rules are a mix of direct presence ("atomspace is enabled if the
# atomspace service is configured") and dependency inversion ("chat being
# enabled auto-enables atomspace, because chat needs a cogserver").
#
# For the MVP, only direct-presence rules are implemented. Dependency
# inversion for requests-from-consumers lands when those consumer modules
# come online.

locals {
  # Direct-presence rules
  atomspace_present = contains(keys(var.service_configs), "atomspace")
  walker_present    = contains(keys(var.service_configs), "walker")
  ingest_present    = contains(keys(var.service_configs), "ingest")
  chat_present      = contains(keys(var.service_configs), "chat")

  # Derived rules
  # Storage is implied whenever atomspace runs (atomspace-rocks needs a volume).
  # When chat or ingest are configured, atomspace is required; they auto-enable it.
  atomspace_enabled = local.atomspace_present || local.chat_present || local.ingest_present || local.walker_present
  walker_enabled    = local.walker_present
  ingest_enabled    = local.ingest_present
  chat_enabled      = local.chat_present
  storage_enabled   = local.atomspace_enabled
}
