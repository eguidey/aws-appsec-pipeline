# Runtime detections built on the application's structured JSON logs.
# Metric filters turn log events into CloudWatch metrics; alarms email the analyst.

resource "aws_sns_topic" "alerts" {
  name              = "${local.name}-security-alerts"
  kms_master_key_id = aws_kms_key.main.arn
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # AWS sends a confirmation email - click the link to start receiving alerts
}

locals {
  metric_namespace = "AppSec/${local.name}"

  detections = {
    brute_force = {
      pattern     = "{ $.event_type = \"brute_force_suspected\" }"
      threshold   = 1
      period      = 300
      severity    = "HIGH"
      description = "Repeated failed logins from a single source IP (possible credential brute force / MITRE T1110)."
    }
    auth_failure_spike = {
      pattern     = "{ $.event_type = \"auth_failure\" }"
      threshold   = 10
      period      = 300
      severity    = "MEDIUM"
      description = "10+ failed logins in 5 minutes across all sources (possible password spraying / T1110.003)."
    }
    injection_attempt = {
      pattern     = "{ $.event_type = \"suspicious_input\" }"
      threshold   = 1
      period      = 300
      severity    = "MEDIUM"
      description = "Request matched SQLi / XSS / path traversal / command injection signatures (T1190)."
    }
    rate_limited = {
      pattern     = "{ $.event_type = \"rate_limited\" }"
      threshold   = 20
      period      = 300
      severity    = "LOW"
      description = "Client exceeded the rate limit repeatedly (scraping, scanning or application-layer DoS)."
    }
    server_errors = {
      pattern     = "{ $.event_type = \"http_request\" && $.status >= 500 }"
      threshold   = 5
      period      = 300
      severity    = "MEDIUM"
      description = "5+ server errors in 5 minutes (application fault or exploitation attempt)."
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "detections" {
  for_each       = local.detections
  name           = "${local.name}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.api.name
  pattern        = each.value.pattern

  metric_transformation {
    name          = each.key
    namespace     = local.metric_namespace
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "detections" {
  for_each            = local.detections
  alarm_name          = "${local.name}-${each.key}"
  alarm_description   = "[${each.value.severity}] ${each.value.description}"
  namespace           = local.metric_namespace
  metric_name         = each.key
  statistic           = "Sum"
  period              = each.value.period
  evaluation_periods  = 1
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  depends_on = [aws_cloudwatch_log_metric_filter.detections]
}

# Saved hunting queries - open CloudWatch > Logs Insights > Saved queries.
resource "aws_cloudwatch_query_definition" "hunting" {
  for_each        = fileset("${path.module}/../detections", "*.query")
  name            = "${local.name}/${trimsuffix(each.value, ".query")}"
  log_group_names = [aws_cloudwatch_log_group.api.name]
  query_string    = file("${path.module}/../detections/${each.value}")
}
