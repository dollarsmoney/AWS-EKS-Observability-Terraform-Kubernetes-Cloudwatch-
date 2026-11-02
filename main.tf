locals {
  name = "${var.project}-${var.environment}" # e.g. eks-cw-lab-dev
}

# 1) Network: VPC, 2 public + 2 private subnets, NAT, Flow Logs
module "vpc" {
  source = "./modules/vpc"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  log_retention_days = var.log_retention_days
}

# 2) EKS in the private subnets (+ Container Insights add-on)
module "eks" {
  source = "./modules/eks"

  name               = local.name
  eks_version        = var.eks_version
  private_subnet_ids = module.vpc.private_subnet_ids
  my_ip_cidr         = var.my_ip_cidr
  node_instance_type = var.node_instance_type
  log_retention_days = var.log_retention_days
}

# 3) Postgres - only reachable from the EKS cluster security group
module "rds" {
  source = "./modules/rds"

  name                      = local.name
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  allowed_security_group_id = module.eks.cluster_security_group_id
  instance_class            = var.db_instance_class
  log_retention_days        = var.log_retention_days
}

# 4) Redis - same idea
module "elasticache" {
  source = "./modules/elasticache"

  name                      = local.name
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  allowed_security_group_id = module.eks.cluster_security_group_id
  node_type                 = var.redis_node_type
  log_retention_days        = var.log_retention_days
}

# 5) CloudWatch: SNS, alarms, metric filters, saved queries, dashboard
#    Notice it only consumes *outputs* of the other modules - monitoring is fully decoupled.
module "monitoring" {
  source = "./modules/monitoring"

  name        = local.name
  alert_email = var.alert_email

  eks_cluster_name               = module.eks.cluster_name
  eks_cluster_log_group_name     = module.eks.cluster_log_group_name
  eks_application_log_group_name = module.eks.container_log_group_names["application"]

  rds_instance_id             = module.rds.instance_id
  rds_postgres_log_group_name = module.rds.postgres_log_group_name

  redis_cache_cluster_id    = module.elasticache.cache_cluster_id
  redis_slow_log_group_name = module.elasticache.slow_log_group_name

  flow_log_group_name = module.vpc.flow_log_group_name
  nat_gateway_id      = module.vpc.nat_gateway_id
}
