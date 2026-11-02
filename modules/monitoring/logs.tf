# ---------- Metric filters: turn log lines into numbers you can graph & alarm on ----------

# Default flow-log format is space-separated; name the fields and match action = REJECT.
resource "aws_cloudwatch_log_metric_filter" "vpc_rejects" {
  name           = "${var.name}-vpc-rejects"
  log_group_name = var.flow_log_group_name
  pattern        = "[version, account, eni, srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes, start, end, action=\"REJECT\", status]"

  metric_transformation {
    name          = "VpcRejectedFlows"
    namespace     = var.custom_metric_namespace
    value         = "1" # count each matching record; try "$packets" to sum packets instead
    default_value = "0"
  }
}

# EKS audit logs are JSON -> use JSON filter syntax { $.field ... }.
resource "aws_cloudwatch_log_metric_filter" "eks_api_errors" {
  name           = "${var.name}-eks-api-errors"
  log_group_name = var.eks_cluster_log_group_name
  pattern        = "{ ($.responseStatus.code = 403) || ($.responseStatus.code >= 500) }"

  metric_transformation {
    name          = "EksApiErrors"
    namespace     = var.custom_metric_namespace
    value         = "1"
    default_value = "0"
  }
}

# ---------- Saved Logs Insights queries (CloudWatch > Logs Insights > Saved queries) ----------

resource "aws_cloudwatch_query_definition" "top_rejected" {
  name            = "${var.name}/vpc/top-rejected-sources"
  log_group_names = [var.flow_log_group_name]
  query_string    = <<-EOT
    fields @timestamp, srcAddr, dstAddr, dstPort, action
    | filter action = "REJECT"
    | stats count(*) as rejects by srcAddr, dstPort
    | sort rejects desc
    | limit 20
  EOT
}

resource "aws_cloudwatch_query_definition" "slow_queries" {
  name            = "${var.name}/rds/slow-queries"
  log_group_names = [var.rds_postgres_log_group_name]
  query_string    = <<-EOT
    fields @timestamp, @message
    | filter @message like /duration:/
    | parse @message "duration: * ms  statement: *" as duration_ms, statement
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "eks_audit_by_user" {
  name            = "${var.name}/eks/audit-by-user"
  log_group_names = [var.eks_cluster_log_group_name]
  query_string    = <<-EOT
    fields @timestamp, user.username, verb, objectRef.resource
    | filter @logStream like /kube-apiserver-audit/
    | stats count(*) as calls by user.username, verb
    | sort calls desc
    | limit 25
  EOT
}

resource "aws_cloudwatch_query_definition" "container_errors" {
  name            = "${var.name}/eks/container-errors"
  log_group_names = [var.eks_application_log_group_name]
  query_string    = <<-EOT
    fields @timestamp, kubernetes.namespace_name, kubernetes.pod_name, log
    | filter log like /(?i)(error|exception|fatal)/
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "redis_slow" {
  name            = "${var.name}/redis/slow-commands"
  log_group_names = [var.redis_slow_log_group_name]
  query_string    = <<-EOT
    fields @timestamp, Command, `Duration (us)` as duration_us, ClientAddress
    | sort duration_us desc
    | limit 20
  EOT
}
