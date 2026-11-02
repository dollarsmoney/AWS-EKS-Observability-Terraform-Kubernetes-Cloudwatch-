variable "name" {
  description = "Name prefix"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the cache subnet group"
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "SG allowed to connect on 6379 (EKS cluster SG)"
  type        = string
}

variable "node_type" {
  description = "Cache node type"
  type        = string
}

variable "log_retention_days" {
  description = "Retention for Redis log groups"
  type        = number
}
