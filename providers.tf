terraform {
  required_version = "~> 1.8"

  required_providers {
    deepmerge = {
      source  = "isometry/deepmerge"
      version = "~> 1.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "deepmerge" {}
