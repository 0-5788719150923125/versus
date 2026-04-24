variable "config" {
  description = <<-EOT
    Atomspace service configuration as merged from state fragments.

    Expected shape (all keys optional, sensible defaults applied):

      core:
        image:         docker image tag (default: opencog/learn:latest)
        cogserver:
          port:        int (default: 18080)
        storage:
          driver:      atomspace-rocks (default)
          path:        in-container mount path (default: /data/atoms)

      schema:
        <type_name>:
          properties:
            <prop_name>:
              default:    float
              decay_rate: float
  EOT
  type        = any
  default     = {}
}

variable "walker_enabled" {
  description = "If true, walker.scm is loaded by the cogserver at startup. Must be paired with the walker module writing walker.scm into generated_dir."
  type        = bool
  default     = false
}

variable "walker_script_hash" {
  description = "SHA-256 of walker.scm, passed through so the cogserver null_resource recreates when walker.scm changes."
  type        = string
  default     = ""
}

variable "ingest_enabled" {
  description = "If true, the generated docker-compose includes the ingest service alongside cog."
  type        = bool
  default     = false
}

variable "ingest_script_dir" {
  description = "Absolute path to the directory holding ingest.py. Mounted into the ingest container as /opt/ingest."
  type        = string
  default     = ""
}

variable "ingest_config" {
  description = "Resolved ingest configuration (flat map) from module.ingest.resolved_config. Threaded into the compose file as env vars."
  type        = any
  default     = {}
}
