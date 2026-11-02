data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Every alarm sends ALARM + OK notifications here.
resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

# You'll get a "Subscription Confirmation" email - click it or you get no alerts!
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Explicitly allow CloudWatch (only from this account) to publish.
data "aws_iam_policy_document" "alerts" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}

locals {
  actions = [aws_sns_topic.alerts.arn]
  region  = data.aws_region.current.region
}
