# Pattern: define similar alarms as data, create them with for_each. Add a line = add an alarm.
locals {
  rds_alarms = {
    cpu = {
      metric      = "CPUUtilization"
      threshold   = 80
      operator    = "GreaterThanThreshold"
      description = "RDS CPU > 80%"
    }
    connections = {
      metric      = "DatabaseConnections"
      threshold   = 60 # db.t4g.micro max_connections is ~80
      operator    = "GreaterThanThreshold"
      description = "RDS connections close to the limit"
    }
    memory = {
      metric      = "FreeableMemory"
      threshold   = 100 * 1024 * 1024 # bytes -> 100 MiB
      operator    = "LessThanThreshold"
      description = "RDS freeable memory < 100MiB"
    }
    read_latency = {
      metric      = "ReadLatency"
      threshold   = 0.02 # seconds -> 20ms
      operator    = "GreaterThanThreshold"
      description = "RDS read latency > 20ms"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "rds" {
  for_each = local.rds_alarms

  alarm_name          = "${var.name}-rds-${replace(each.key, "_", "-")}"
  alarm_description   = each.value.description
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBInstanceIdentifier = var.rds_instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = each.value.threshold
  comparison_operator = each.value.operator
  treat_missing_data  = "missing"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# Metric math: convert bytes -> GiB so the threshold is human-readable.
resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${var.name}-rds-free-storage-low"
  alarm_description   = "RDS free storage < 2 GiB"
  evaluation_periods  = 1
  threshold           = 2
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  metric_query {
    id          = "free_gib"
    expression  = "bytes / 1073741824"
    label       = "Free storage (GiB)"
    return_data = true
  }

  metric_query {
    id = "bytes"
    metric {
      namespace   = "AWS/RDS"
      metric_name = "FreeStorageSpace"
      dimensions  = { DBInstanceIdentifier = var.rds_instance_id }
      stat        = "Minimum"
      period      = 300
    }
  }
}
