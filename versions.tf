terraform {
  required_version = ">= 1.5.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # OPTIONAL: use a remote backend so state (which is NOT secret-free) is not
  # committed to git and can be shared by CI. Uncomment and configure one.
  #
  # backend "s3" {
  #   bucket = "my-tfstate-bucket"
  #   key    = "dynatrace-oneagent/terraform.tfstate"
  #   region = "us-east-1"
  # }
}
