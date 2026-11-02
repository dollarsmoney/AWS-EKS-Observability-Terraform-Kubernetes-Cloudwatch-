resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-redis"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "redis" {
  name        = "${var.name}-redis"
  description = "Redis access from EKS only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-redis" }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_eks" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = var.allowed_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Redis from EKS"
}

# Lower the slow-log threshold (default 10ms) so the lab actually produces slow-log entries.
resource "aws_elasticache_parameter_group" "this" {
  name   = "${var.name}-redis7"
  family = "redis7"

  parameter {
    name  = "slowlog-log-slower-than" # microseconds
    value = "1000"
  }
}

resource "aws_cloudwatch_log_group" "redis" {
  for_each = toset(["slow-log", "engine-log"])

  name              = "/aws/elasticache/${var.name}/${each.value}"
  retention_in_days = var.log_retention_days
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name}-redis"
  description          = "Redis for ${var.name}"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.node_type
  num_cache_clusters   = 1 # cost: 2+ with automatic_failover_enabled in prod
  port                 = 6379

  parameter_group_name = aws_elasticache_parameter_group.this.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true # clients must use TLS (redis-cli --tls)
  automatic_failover_enabled = false
  apply_immediately          = true
  snapshot_retention_limit   = 0

  # Ship Redis logs to CloudWatch Logs (JSON so Logs Insights can parse fields).
  dynamic "log_delivery_configuration" {
    for_each = aws_cloudwatch_log_group.redis
    content {
      destination      = log_delivery_configuration.value.name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = log_delivery_configuration.key
    }
  }
}
