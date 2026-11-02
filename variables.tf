variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short name used as a prefix for every resource"
  type        = string
  default     = "eks-cw-lab"
}

variable "environment" {
  description = "Environment tag (dev/stage/prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "alert_email" {
  description = "Email that receives CloudWatch alarm notifications (you must confirm the SNS email)"
  type        = string
  sensitive   = true # keeps it out of plan output / public CI logs
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form (e.g. 1.2.3.4/32) - only this IP can reach the EKS API"
  type        = string
  sensitive   = true

  validation {
    condition     = can(cidrhost(var.my_ip_cidr, 0))
    error_message = "my_ip_cidr must be a valid CIDR, e.g. 203.0.113.10/32."
  }

  # Catch the copy-pasted example: 192.0.2.x / 198.51.100.x / 203.0.113.x are documentation-only ranges, EKS rejects them.
  validation {
    condition     = !can(regex("^(192\\.0\\.2|198\\.51\\.100|203\\.0\\.113)\\.", var.my_ip_cidr))
    error_message = "my_ip_cidr is still the example placeholder. Use your real IP: echo \"$(curl -s https://checkip.amazonaws.com)/32\""
  }
}

variable "eks_version" {
  description = "Kubernetes version. Check `aws eks describe-cluster-versions` - stay in STANDARD support to avoid extra cost"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "EC2 type for EKS worker nodes"
  type        = string
  default     = "t3.small"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "log_retention_days" {
  description = "How long CloudWatch keeps logs. Never leave it at 'never expire' - logs cost money"
  type        = number
  default     = 7
}
