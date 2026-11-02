variable "name" {
  description = "Name prefix"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "log_retention_days" {
  description = "Retention for the flow log group"
  type        = number
}
