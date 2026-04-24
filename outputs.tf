output "loaded_states" {
  description = "State fragment files that were loaded and merged"
  value       = module.config.loaded_states
}

output "merged_services" {
  description = "Final merged service configurations (for debugging and tooling)"
  value       = module.config.service_configs
}

output "enable_flags" {
  description = "Resolver-computed enable flags per subsystem"
  value = {
    atomspace = module.resolver.atomspace_enabled
    walker    = module.resolver.walker_enabled
    ingest    = module.resolver.ingest_enabled
    chat      = module.resolver.chat_enabled
    storage   = module.resolver.storage_enabled
  }
}

output "generated_dir" {
  description = "Directory holding generated engine artifacts"
  value       = try(module.atomspace[0].generated_dir, null)
}

output "cogserver_endpoint" {
  description = "Running CogServer endpoint (host + port)"
  value       = try(module.atomspace[0].cogserver_endpoint, null)
}
