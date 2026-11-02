terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # pin major version so upgrades are deliberate
    }
  }

  # Remote, locked state (bucket created by ./bootstrap). The bucket name is passed at init time
  # so the account ID stays out of the code:
  #   terraform init -backend-config="bucket=<state_bucket output>"
  backend "s3" {
    key          = "eks-cloudwatch-lab/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true # S3-native locking (no DynamoDB needed)
    encrypt      = true
  }
}
