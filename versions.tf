terraform {
  required_version = ">= 1.5.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # A state backend is REQUIRED for team use — without one, state is local and
  # lost or duplicated across runners. Pick ONE of the examples below and
  # uncomment it. The `local` backend works for a single dev; everything else
  # needs a real bucket / container.

  # ----- Local backend (single dev only, NOT shared) -------------------
  # backend "local" {
  #   path = "terraform.tfstate"
  # }

  # ----- AWS S3 ---------------------------------------------------------
  # backend "s3" {
  #   bucket         = "my-tfstate-bucket"
  #   key            = "dynatrace-oneagent/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"   # for state locking
  #   encrypt        = true
  # }

  # ----- Azure Storage --------------------------------------------------
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "mytfstate"
  #   container_name       = "tfstate"
  #   key                  = "dynatrace-oneagent.terraform.tfstate"
  # }

  # ----- GCP GCS --------------------------------------------------------
  # backend "gcs" {
  #   bucket = "my-tfstate-bucket"
  #   prefix = "dynatrace-oneagent"
  # }

  # ----- Terraform Cloud / HCP -----------------------------------------
  # backend "remote" {
  #   organization = "my-org"
  #   workspaces {
  #     name = "dynatrace-oneagent"
  #   }
  # }
}