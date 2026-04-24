output "script_dir" {
  description = "Directory containing the static ingest.py script. Mount into the ingest container as /opt/ingest."
  value       = abspath(local.script_dir)
}

output "resolved_config" {
  description = "Flat map of resolved ingest configuration, suitable for environment variable threading."
  value       = local.resolved
}
