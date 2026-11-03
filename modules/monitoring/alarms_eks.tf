# Container Insights metrics live in the "ContainerInsights" namespace, dimension ClusterName.

# "M out of N": alarm when 3 of the last 5 one-minute points are > 80% (ignores short spikes).
resource "aws_cloudwatch_metric_alarm" "eks_node_cpu" {
  alarm_name          = "${var.name}-eks-node-cpu-high"
  alarm_description   = "Average node CPU across the cluster > 80%"
  namespace           = "ContainerInsights"
  metric_name         = "node_cpu_utilization"
  dimensions          = { ClusterName = var.eks_cluster_name }
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

resource "aws_cloudwatch_metric_alarm" "eks_node_memory" {
  alarm_name          = "${var.name}-eks-node-memory-high"
  alarm_description   = "Average node memory across the cluster > 80%"
  namespace           = "ContainerInsights"
  metric_name         = "node_memory_utilization"
  dimensions          = { ClusterName = var.eks_cluster_name }
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

resource "aws_cloudwatch_metric_alarm" "eks_failed_nodes" {
  alarm_name          = "${var.name}-eks-failed-nodes"
  alarm_description   = "At least one node is NotReady"
  namespace           = "ContainerInsights"
  metric_name         = "cluster_failed_node_count"
  dimensions          = { ClusterName = var.eks_cluster_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# Metrics Insights (SQL-like) query inside an alarm: sum restarts across ALL pods in the cluster,
# even though the raw metric is per-pod. One alarm instead of one per pod.
resource "aws_cloudwatch_metric_alarm" "eks_pod_restarts" {
  alarm_name          = "${var.name}-eks-pod-restarts"
  alarm_description   = "Containers are restarting (CrashLoopBackOff?)"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 3
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  metric_query {
    id          = "restarts"
    label       = "Total container restarts"
    return_data = true
    period      = 60
    expression  = "SELECT SUM(pod_number_of_container_restarts) FROM SCHEMA(ContainerInsights, ClusterName, Namespace, PodName) WHERE ClusterName = '${var.eks_cluster_name}'"
  }
}

# Node filesystem utilisation: Container Insights reports how full each node's root volume is.
# > 85% means the node is getting close to an eviction or OOMKill scenario from disk pressure.
# Uses M-of-N (2 of 3) to avoid false positives from short log bursts.
resource "aws_cloudwatch_metric_alarm" "eks_node_filesystem" {
  alarm_name          = "${var.name}-eks-node-filesystem-high"
  alarm_description   = "Node filesystem utilisation > 85% — risk of disk-pressure eviction"
  namespace           = "ContainerInsights"
  metric_name         = "node_filesystem_utilization"
  dimensions          = { ClusterName = var.eks_cluster_name }
  statistic           = "Maximum" # worst node in the group, not the average
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# Network throughput: alarms when a node exceeds 80% of a t3.small's 5 Gbps baseline.
# Sustained saturation here signals that the workload needs a larger instance type or
# horizontal scaling before it starts dropping packets.
resource "aws_cloudwatch_metric_alarm" "eks_node_network_tx" {
  alarm_name          = "${var.name}-eks-node-network-tx-high"
  alarm_description   = "Node network transmit bytes/s is high — potential bandwidth saturation"
  namespace           = "ContainerInsights"
  metric_name         = "node_network_total_bytes"
  dimensions          = { ClusterName = var.eks_cluster_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = 400000000 # ~400 MB/s ≈ 80% of t3.small 5 Gbps baseline
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}
