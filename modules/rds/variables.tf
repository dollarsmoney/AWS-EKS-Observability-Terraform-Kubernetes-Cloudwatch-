variable "name" {
  description = "Name prefix"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the DB subnet group"
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "SG allowed to connect on 5432 (EKS cluster SG)"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "log_retention_days" {
  description = "Retention for exported Postgres logs"
  type        = number
}
