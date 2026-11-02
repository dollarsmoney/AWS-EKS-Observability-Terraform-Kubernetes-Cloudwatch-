variable "name" {
  description = "Name prefix for alarms, dashboard, topic"
  type        = string
}

variable "alert_email" {
  description = "Email subscribed to the alarm SNS topic"
  type        = string
}

variable "eks_cluster_name" {
  type = string
}

variable "eks_cluster_log_group_name" {
  type = string
}

variable "eks_application_log_group_name" {
  description = "Container Insights application log group (pod stdout/stderr)"
  type        = string
}

variable "rds_instance_id" {
  type = string
}

variable "rds_postgres_log_group_name" {
  type = string
}

variable "redis_cache_cluster_id" {
  type = string
}

variable "redis_slow_log_group_name" {
  type = string
}

variable "flow_log_group_name" {
  type = string
}

variable "nat_gateway_id" {
  type = string
}

variable "custom_metric_namespace" {
  description = "Namespace for metrics we create from logs via metric filters"
  type        = string
  default     = "Lab/Custom"
}
