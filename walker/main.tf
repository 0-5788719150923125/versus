# Walker module.
#
# The walker is static Scheme at scripts/walker.scm. This module copies
# it into the shared generated_dir (the same .versus/ the atomspace
# module writes to), where it sits alongside atom-schema.scm,
# decay-rules.scm, and inference.scm. The atomspace module's generated
# docker-compose loads walker.scm at cogserver startup when the walker
# state fragment is active.
#
# No separate container. No long-running process. The walker is a set
# of procedures invoked by other Scheme code (specifically versus-teach,
# which auto-ticks after every fragment observation).

locals {
  source_path      = "${path.module}/scripts/walker.scm"
  destination_path = "${var.generated_dir}/walker.scm"
  content          = file(local.source_path)
}

resource "local_file" "walker_scm" {
  filename        = local.destination_path
  content         = local.content
  file_permission = "0644"
}
