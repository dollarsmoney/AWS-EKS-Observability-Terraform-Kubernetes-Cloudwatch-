# Core add-ons managed by EKS (no addon_version = EKS picks the default for our k8s version).
resource "aws_eks_addon" "core" {
  for_each = toset(["vpc-cni", "kube-proxy", "coredns", "eks-pod-identity-agent"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this] # coredns needs nodes to become ACTIVE
}

# Pre-create Container Insights log groups so they get retention (Fluent Bit would create them as "never expire").
resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = toset(["application", "dataplane", "host", "performance"])

  name              = "/aws/containerinsights/${var.name}/${each.value}"
  retention_in_days = var.log_retention_days
}

# Gives the add-on's "cloudwatch-agent" service account the IAM role from iam.tf.
resource "aws_eks_pod_identity_association" "cloudwatch_agent" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "amazon-cloudwatch"
  service_account = "cloudwatch-agent"
  role_arn        = aws_iam_role.cloudwatch_agent.arn
}

# Container Insights (metrics) + Fluent Bit (container logs) in one add-on.
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_addon.core, # needs the pod-identity agent running first
    aws_eks_pod_identity_association.cloudwatch_agent,
    aws_cloudwatch_log_group.container_insights,
  ]
}
