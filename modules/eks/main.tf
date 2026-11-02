# Pre-create the control-plane log group so WE control retention (EKS would create it with "never expire").
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name}/cluster" # EKS requires exactly this name
  retention_in_days = var.log_retention_days
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.eks_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true             # nodes talk to the API inside the VPC
    endpoint_public_access  = true             # you run kubectl from your laptop...
    public_access_cidrs     = [var.my_ip_cidr] # ...but only from your IP
  }

  # Access entries (API mode) replace the old aws-auth ConfigMap.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true # whoever runs terraform becomes cluster admin
  }

  # Ship all 5 control-plane log types to CloudWatch.
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # STANDARD = auto-upgrade when standard support ends instead of moving to paid extended support (~6x price).
  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids # nodes live in private subnets only
  instance_types  = [var.node_instance_type]
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND" # try "SPOT" to save ~70% (exercise!)

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  update_config {
    max_unavailable = 1
  }

  labels = { role = "general" }

  depends_on = [aws_iam_role_policy_attachment.node]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size] # let autoscalers change it without TF drift
  }
}
