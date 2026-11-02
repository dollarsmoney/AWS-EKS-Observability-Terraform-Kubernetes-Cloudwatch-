output "primary_endpoint" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

# CloudWatch Redis metrics use the *node's cluster id* (e.g. "eks-cw-lab-redis-001") as dimension.
output "cache_cluster_id" {
  value = tolist(aws_elasticache_replication_group.this.member_clusters)[0]
}

output "slow_log_group_name" {
  value = aws_cloudwatch_log_group.redis["slow-log"].name
}
