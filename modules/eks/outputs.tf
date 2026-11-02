output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

# EKS auto-creates this SG and attaches it to the control plane AND managed nodes.
# RDS/Redis allow traffic only from it.
output "cluster_security_group_id" {
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_log_group_name" {
  value = aws_cloudwatch_log_group.cluster.name
}

output "container_log_group_names" {
  value = { for k, lg in aws_cloudwatch_log_group.container_insights : k => lg.name }
}

output "node_group_name" {
  value = aws_eks_node_group.this.node_group_name
}
