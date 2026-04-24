output "generated_dir" {
  description = "Directory holding all generated engine artifacts"
  value       = local.generated_dir
}

output "cogserver_endpoint" {
  description = "Host and port where the running CogServer is reachable"
  value = {
    host = "localhost"
    port = local.cogserver_port
  }
}

output "schema_path" {
  description = "Path to the generated atom schema Scheme file"
  value       = local_file.atom_schema.filename
}

output "decay_rules_path" {
  description = "Path to the generated decay rules Scheme file"
  value       = local_file.decay_rules.filename
}

output "compose_path" {
  description = "Path to the generated docker-compose.yml"
  value       = local.compose_path
}

output "atom_types" {
  description = "Flattened list of atom types emitted into the schema"
  value       = local.atom_types
}
