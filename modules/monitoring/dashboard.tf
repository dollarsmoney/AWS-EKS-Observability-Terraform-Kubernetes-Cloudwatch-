locals {
  # Every alarm in one place - used by the dashboard's alarm-status widget and the outputs.
  all_alarms = merge(
    {
      eks_node_cpu        = aws_cloudwatch_metric_alarm.eks_node_cpu
      eks_node_memory     = aws_cloudwatch_metric_alarm.eks_node_memory
      eks_failed_nodes    = aws_cloudwatch_metric_alarm.eks_failed_nodes
      eks_pod_restarts    = aws_cloudwatch_metric_alarm.eks_pod_restarts
      eks_api_errors      = aws_cloudwatch_metric_alarm.eks_api_errors
      rds_free_storage    = aws_cloudwatch_metric_alarm.rds_free_storage
      redis_cpu           = aws_cloudwatch_metric_alarm.redis_cpu
      redis_memory        = aws_cloudwatch_metric_alarm.redis_memory
      redis_evictions     = aws_cloudwatch_metric_alarm.redis_evictions
      redis_conn_anomaly  = aws_cloudwatch_metric_alarm.redis_connections_anomaly
      nat_port_allocation = aws_cloudwatch_metric_alarm.nat_port_allocation
      vpc_rejects         = aws_cloudwatch_metric_alarm.vpc_rejects
    },
    { for k, a in aws_cloudwatch_metric_alarm.rds : "rds_${k}" => a },
  )
  alarm_names = concat([for a in values(local.all_alarms) : a.alarm_name], [aws_cloudwatch_composite_alarm.app_tier.alarm_name])
  alarm_arns  = concat([for a in values(local.all_alarms) : a.arn], [aws_cloudwatch_composite_alarm.app_tier.arn])

  rds   = ["DBInstanceIdentifier", var.rds_instance_id]
  redis = ["CacheClusterId", var.redis_cache_cluster_id]

  # Small helper so each widget below is just: title, position, metrics.
  # metrics format: [Namespace, MetricName, DimName, DimValue, {options}]
  widget = {
    type   = "metric"
    width  = 8
    height = 6
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name}-overview"

  # Dashboard body is JSON. jsonencode() lets us write it as HCL and interpolate IDs.
  # Tip: build a widget in the console, then "Actions > View/edit source" to copy its JSON.
  dashboard_body = jsonencode({
    widgets = [
      # ---------- Row 0: header + alarm status ----------
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# ${var.name} overview\nEKS `${var.eks_cluster_name}` · RDS `${var.rds_instance_id}` · Redis `${var.redis_cache_cluster_id}`"
        }
      },
      {
        type       = "alarm", x = 0, y = 2, width = 24, height = 4
        properties = { title = "Alarm status", alarms = local.alarm_arns }
      },

      # ---------- Row 1: EKS (Container Insights) ----------
      merge(local.widget, {
        x = 0, y = 6
        properties = {
          title = "EKS node CPU / memory %", region = local.region, stat = "Average", period = 60, view = "timeSeries"
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", var.eks_cluster_name],
            ["ContainerInsights", "node_memory_utilization", "ClusterName", var.eks_cluster_name],
          ]
          annotations = { horizontal = [{ value = 80, label = "alarm threshold" }] }
        }
      }),
      merge(local.widget, {
        x = 8, y = 6
        properties = {
          title = "EKS nodes & pods", region = local.region, stat = "Average", period = 60, view = "timeSeries"
          metrics = [
            ["ContainerInsights", "cluster_node_count", "ClusterName", var.eks_cluster_name],
            ["ContainerInsights", "cluster_failed_node_count", "ClusterName", var.eks_cluster_name],
            ["ContainerInsights", "node_number_of_running_pods", "ClusterName", var.eks_cluster_name],
          ]
        }
      }),
      merge(local.widget, {
        x = 16, y = 6
        properties = {
          title = "Container restarts by namespace (Metrics Insights)", region = local.region, period = 60, view = "timeSeries"
          metrics = [[{
            id         = "q1"
            expression = "SELECT SUM(pod_number_of_container_restarts) FROM SCHEMA(ContainerInsights, ClusterName, Namespace, PodName) WHERE ClusterName = '${var.eks_cluster_name}' GROUP BY Namespace"
            label      = "restarts"
          }]]
        }
      }),

      # ---------- Row 2: RDS ----------
      merge(local.widget, {
        x = 0, y = 12
        properties = {
          title = "RDS CPU % & connections", region = local.region, stat = "Average", period = 60, view = "timeSeries"
          metrics = [
            concat(["AWS/RDS", "CPUUtilization"], local.rds),
            concat(["AWS/RDS", "DatabaseConnections"], local.rds, [{ yAxis = "right" }]),
          ]
        }
      }),
      merge(local.widget, {
        x = 8, y = 12
        properties = {
          title = "RDS read/write latency (ms)", region = local.region, stat = "Average", period = 60, view = "timeSeries"
          # Metric math in a widget: hide raw seconds (visible=false), show ms.
          metrics = [
            concat(["AWS/RDS", "ReadLatency"], local.rds, [{ id = "r", visible = false }]),
            concat(["AWS/RDS", "WriteLatency"], local.rds, [{ id = "w", visible = false }]),
            [{ expression = "r*1000", label = "Read ms", id = "rms" }],
            [{ expression = "w*1000", label = "Write ms", id = "wms" }],
          ]
        }
      }),
      merge(local.widget, {
        x = 16, y = 12
        properties = {
          title = "RDS free storage & memory", region = local.region, stat = "Minimum", period = 300, view = "timeSeries"
          metrics = [
            concat(["AWS/RDS", "FreeStorageSpace"], local.rds),
            concat(["AWS/RDS", "FreeableMemory"], local.rds, [{ yAxis = "right" }]),
          ]
        }
      }),

      # ---------- Row 3: Redis ----------
      merge(local.widget, {
        x = 0, y = 18
        properties = {
          title = "Redis engine CPU & memory %", region = local.region, stat = "Average", period = 60, view = "timeSeries"
          yAxis = { left = { min = 0, max = 100 } }
          metrics = [
            concat(["AWS/ElastiCache", "EngineCPUUtilization"], local.redis),
            concat(["AWS/ElastiCache", "DatabaseMemoryUsagePercentage"], local.redis),
          ]
        }
      }),
      merge(local.widget, {
        x = 8, y = 18
        properties = {
          title = "Redis connections & cache hit rate", region = local.region, stat = "Average", period = 60, view = "timeSeries"
          metrics = [
            concat(["AWS/ElastiCache", "CurrConnections"], local.redis),
            concat(["AWS/ElastiCache", "CacheHitRate"], local.redis, [{ yAxis = "right" }]),
          ]
        }
      }),
      merge(local.widget, {
        x = 16, y = 18
        properties = {
          title = "Redis ops & evictions", region = local.region, stat = "Sum", period = 60, view = "timeSeries"
          metrics = [
            concat(["AWS/ElastiCache", "GetTypeCmds"], local.redis),
            concat(["AWS/ElastiCache", "SetTypeCmds"], local.redis),
            concat(["AWS/ElastiCache", "Evictions"], local.redis, [{ yAxis = "right" }]),
          ]
        }
      }),

      # ---------- Row 4: Network + custom metrics from logs ----------
      merge(local.widget, {
        x = 0, y = 24
        properties = {
          title = "NAT gateway traffic (bytes)", region = local.region, stat = "Sum", period = 300, view = "timeSeries"
          metrics = [
            ["AWS/NATGateway", "BytesOutToDestination", "NatGatewayId", var.nat_gateway_id],
            ["AWS/NATGateway", "BytesInFromDestination", "NatGatewayId", var.nat_gateway_id],
            ["AWS/NATGateway", "ErrorPortAllocation", "NatGatewayId", var.nat_gateway_id, { yAxis = "right" }],
          ]
        }
      }),
      merge(local.widget, {
        x = 8, y = 24
        properties = {
          title = "Custom metrics (from log metric filters)", region = local.region, stat = "Sum", period = 300, view = "timeSeries"
          metrics = [
            [var.custom_metric_namespace, "VpcRejectedFlows"],
            [var.custom_metric_namespace, "EksApiErrors", { yAxis = "right" }],
          ]
        }
      }),
      {
        type = "log", x = 16, y = 24, width = 8, height = 6
        properties = {
          title  = "Top rejected sources (Flow Logs)"
          region = local.region
          view   = "table"
          query  = "SOURCE '${var.flow_log_group_name}' | filter action = 'REJECT' | stats count(*) as rejects by srcAddr, dstPort | sort rejects desc | limit 10"
        }
      },

      # ---------- Row 5: container error logs ----------
      {
        type = "log", x = 0, y = 30, width = 24, height = 6
        properties = {
          title  = "Recent container errors"
          region = local.region
          view   = "table"
          query  = "SOURCE '${var.eks_application_log_group_name}' | fields @timestamp, kubernetes.pod_name, log | filter log like /(?i)(error|exception|fatal)/ | sort @timestamp desc | limit 20"
        }
      },
    ]
  })
}
