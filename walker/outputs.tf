output "script_path" {
  description = "Path to the walker Scheme file that was copied into the shared generated_dir."
  value       = local_file.walker_scm.filename
}

output "script_hash" {
  description = "SHA-256 of walker.scm content. The atomspace module includes this in the cogserver null_resource triggers so changes to walker.scm cause a container restart."
  value       = local_file.walker_scm.content_sha256
}
