variable "generated_dir" {
  description = "Directory where engine artifacts are written (shared with atomspace module). The walker script lands here as walker.scm and is loaded by the cogserver at startup."
  type        = string
}
