output "atomspace_enabled" {
  description = "Whether the atomspace substrate module should be instantiated"
  value       = local.atomspace_enabled
}

output "walker_enabled" {
  description = "Whether the walker process module should be instantiated"
  value       = local.walker_enabled
}

output "ingest_enabled" {
  description = "Whether the corpus-ingest worker module should be instantiated"
  value       = local.ingest_enabled
}

output "chat_enabled" {
  description = "Whether the chat endpoint module should be instantiated"
  value       = local.chat_enabled
}

output "storage_enabled" {
  description = "Whether the storage (atomspace-rocks volume) module should be instantiated"
  value       = local.storage_enabled
}
