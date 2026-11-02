output "configure_kubectl" {
  description = "Run this to point kubectl at the cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "rds_address" {
  value = module.rds.address
}

output "rds_username" {
  value = module.rds.username
}

output "rds_db_name" {
  value = module.rds.db_name
}

output "rds_master_secret_arn" {
  description = "Secrets Manager secret holding the generated DB password"
  value       = module.rds.master_secret_arn
}

output "redis_endpoint" {
  value = module.elasticache.primary_endpoint
}

output "sns_topic_arn" {
  value = module.monitoring.sns_topic_arn
}

output "dashboard_url" {
  value = module.monitoring.dashboard_url
}

output "alarm_names" {
  value = module.monitoring.alarm_names
}
