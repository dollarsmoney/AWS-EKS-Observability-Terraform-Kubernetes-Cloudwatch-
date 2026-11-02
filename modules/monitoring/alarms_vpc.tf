# NAT ran out of source ports -> outbound connections from private subnets fail.
resource "aws_cloudwatch_metric_alarm" "nat_port_allocation" {
  alarm_name          = "${var.name}-nat-port-allocation-errors"
  alarm_description   = "NAT gateway could not allocate a source port"
  namespace           = "AWS/NATGateway"
  metric_name         = "ErrorPortAllocation"
  dimensions          = { NatGatewayId = var.nat_gateway_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# Alarm on a metric WE created from logs (see logs.tf metric filter).
resource "aws_cloudwatch_metric_alarm" "vpc_rejects" {
  alarm_name          = "${var.name}-vpc-rejected-flows-high"
  alarm_description   = "Lots of rejected connections - port scan or broken SG?"
  namespace           = var.custom_metric_namespace
  metric_name         = aws_cloudwatch_log_metric_filter.vpc_rejects.metric_transformation[0].name
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 500
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "eks_api_errors" {
  alarm_name          = "${var.name}-eks-api-errors"
  alarm_description   = "Kubernetes API returning 403/5xx"
  namespace           = var.custom_metric_namespace
  metric_name         = aws_cloudwatch_log_metric_filter.eks_api_errors.metric_transformation[0].name
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 20
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# Composite alarm: one page for "the app tier is in trouble" instead of 3 separate emails.
# Child alarms still change state; best practice is to remove their actions and only notify here.
resource "aws_cloudwatch_composite_alarm" "app_tier" {
  alarm_name        = "${var.name}-app-tier-unhealthy"
  alarm_description = "EKS nodes, RDS or Redis CPU is in ALARM"
  alarm_actions     = local.actions
  ok_actions        = local.actions

  alarm_rule = join(" OR ", [
    "ALARM(\"${aws_cloudwatch_metric_alarm.eks_node_cpu.alarm_name}\")",
    "ALARM(\"${aws_cloudwatch_metric_alarm.rds["cpu"].alarm_name}\")",
    "ALARM(\"${aws_cloudwatch_metric_alarm.redis_cpu.alarm_name}\")",
  ])
}
