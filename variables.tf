variable "states" {
  description = <<-EOT
    List of state fragments to load and merge from the states/ directory.
    State fragments are YAML files that define cognitive subsystem configs.

    States are deep-merged in order (left-to-right). Later fragments override
    earlier ones at overlapping keys; non-overlapping keys accumulate.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.states : can(regex("^[a-z0-9-]+$", s))])
    error_message = "State names must contain only lowercase letters, numbers, and hyphens."
  }
}
