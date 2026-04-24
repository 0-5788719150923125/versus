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
