resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.private_subnet_ids
}

# Only pods/nodes in the EKS cluster SG can reach Postgres. Everything else = REJECT (visible in Flow Logs!).
resource "aws_security_group" "db" {
  name        = "${var.name}-rds"
  description = "Postgres access from EKS only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-rds" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_eks" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = var.allowed_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Postgres from EKS"
}

# Custom parameter group so Postgres writes useful logs for CloudWatch.
resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-pg17"
  family = "postgres17"

  parameter {
    name  = "log_min_duration_statement" # log any query slower than 500ms
    value = "500"
  }

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

# Pre-create log groups RDS exports to, so retention is set (RDS creates them as "never expire").
resource "aws_cloudwatch_log_group" "rds" {
  for_each = toset(["postgresql", "upgrade"])

  name              = "/aws/rds/instance/${var.name}-postgres/${each.value}"
  retention_in_days = var.log_retention_days
}

# Enhanced Monitoring = OS-level metrics (per-process CPU, memory) every 60s, stored in CloudWatch Logs "RDSOSMetrics".
data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name               = "${var.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = "17" # major only -> AWS picks the latest 17.x
  instance_class = var.instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "appdb"
  username = "dbadmin"
  # Password is generated & stored in Secrets Manager -> never lands in Terraform state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = false # cost: true in prod

  # ---- Observability ----
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_retention_period = 7 # 7 days is free

  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  apply_immediately          = true

  # Lab settings - in prod: deletion_protection = true, skip_final_snapshot = false.
  deletion_protection = false
  skip_final_snapshot = true

  depends_on = [aws_cloudwatch_log_group.rds]
}
