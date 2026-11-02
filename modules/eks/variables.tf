variable "name" {
  description = "Cluster name / name prefix"
  type        = string
}

variable "eks_version" {
  description = "Kubernetes version"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for control-plane ENIs and nodes"
  type        = list(string)
}

variable "my_ip_cidr" {
  description = "CIDR allowed to reach the public API endpoint"
  type        = string
}

variable "node_instance_type" {
  description = "Worker node instance type"
  type        = string
}

variable "log_retention_days" {
  description = "Retention for EKS & Container Insights log groups"
  type        = number
}
