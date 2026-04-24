variable "config" {
  description = <<-EOT
    Ingest service configuration as merged from state fragments.

    Expected shape (all keys optional; defaults applied if absent):

      core:
        dataset:
          source:   HuggingFace dataset identifier
          config:   dataset config / subset name (optional)
          split:    dataset split (default: train)
        fragments:
          min_words: int
          max_words: int
        rate:
          fragments_per_second: number
          max_fragments:        int (0 = unbounded)
        role_tag:   optional; tags every ingested FragmentAtom with a
                    role ConceptAtom (e.g. "assistant"). Not used by the
                    trivial inference; useful later for generation.
  EOT
  type        = any
  default     = {}
}
