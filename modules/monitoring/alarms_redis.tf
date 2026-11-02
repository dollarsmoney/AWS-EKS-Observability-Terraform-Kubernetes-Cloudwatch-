# EngineCPUUtilization = the Redis thread itself (Redis is single-threaded, so watch this, not host CPU).
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "${var.name}-redis-engine-cpu-high"
  alarm_description   = "Redis engine CPU > 80%"
  namespace           = "AWS/ElastiCache"
  metric_name         = "EngineCPUUtilization"
  dimensions          = { CacheClusterId = var.redis_cache_cluster_id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name          = "${var.name}-redis-memory-high"
  alarm_description   = "Redis memory usage > 80% of maxmemory"
  namespace           = "AWS/ElastiCache"
  metric_name         = "DatabaseMemoryUsagePercentage"
  dimensions          = { CacheClusterId = var.redis_cache_cluster_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# Evictions > 0 = Redis is throwing away keys because it's full.
resource "aws_cloudwatch_metric_alarm" "redis_evictions" {
  alarm_name          = "${var.name}-redis-evictions"
  alarm_description   = "Redis is evicting keys (out of memory)"
  namespace           = "AWS/ElastiCache"
  metric_name         = "Evictions"
  dimensions          = { CacheClusterId = var.redis_cache_cluster_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# Anomaly detection: CloudWatch learns the normal pattern (needs ~1 day of data) and alarms
# when connections go above the expected band. No fixed threshold to guess.
resource "aws_cloudwatch_metric_alarm" "redis_connections_anomaly" {
  alarm_name          = "${var.name}-redis-connections-anomaly"
  alarm_description   = "Redis connections above the learned normal band"
  evaluation_periods  = 3
  comparison_operator = "GreaterThanUpperThreshold"
  threshold_metric_id = "band"
  treat_missing_data  = "missing"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  metric_query {
    id          = "band"
    expression  = "ANOMALY_DETECTION_BAND(conn, 2)" # 2 = band width in standard deviations
    label       = "Expected range"
    return_data = true
  }

  metric_query {
    id          = "conn"
    return_data = true
    metric {
      namespace   = "AWS/ElastiCache"
      metric_name = "CurrConnections"
      dimensions  = { CacheClusterId = var.redis_cache_cluster_id }
      stat        = "Average"
      period      = 300
    }
  }
}
