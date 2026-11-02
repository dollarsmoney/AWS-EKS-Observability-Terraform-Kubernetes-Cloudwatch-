provider "aws" {
  region = var.region

  # Every resource gets these tags automatically -> easy cost tracking & cleanup.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
