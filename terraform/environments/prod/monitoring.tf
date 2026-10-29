# INTERVIEW NOTE: This file covers the entire observability requirement
# from the assignment: infrastructure metrics, application metrics,
# database metrics, centralized logging, and at least two dashboards.
#
# WHY CloudWatch over Prometheus/Grafana/Datadog:
# The assignment requirement is tool-agnostic — it lists WHAT to monitor,
# not which tool to use. CloudWatch satisfies every listed item natively
# with zero additional infrastructure to provision, secure, or pay for.
# Datadog or Grafana would give richer dashboards and better alerting,
# but require deploying agents, managing an extra platform, and a separate
# billing line. For this deliverable, CloudWatch is the pragmatic, correct call.
#
# CROSS-QUESTION: "Have you used Prometheus or Grafana?"
# Be honest: if you haven't used them in production, say so and pivot to
# why CloudWatch was the correct tool for these specific requirements.
# Do not overclaim — interviewers will probe any tool you claim experience with.

# WHY SNS (Simple Notification Service) as the alarm action:
# CloudWatch alarms cannot send notifications directly to email or Slack.
# SNS is the intermediary — an alarm fires to an SNS topic, and the topic
# fans out to subscriptions (email, Lambda, Slack webhook, PagerDuty, etc.).
# This decouples "when to alert" (the alarm) from "how to notify" (the subscription),
# so you can add or change notification channels without touching the alarm.
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

# WHY there are no aws_cloudwatch_log_group resources in this file:
# ECS containers write to stdout/stderr. The awslogs log driver, configured
# automatically by the ECS module, ships that output to CloudWatch in real
# time (no log agent to install or manage). The module also CREATES the log
# group for each container, named /aws/ecs/<service>/<container>
# (/aws/ecs/frontend/frontend and /aws/ecs/backend/backend), so declaring
# our own groups here would just create empty, unused duplicates.
# The one thing we do set is the retention, in main.tf, next to each
# container definition.
#
# WHY retention is 30 days (cloudwatch_log_group_retention_in_days = 30):
# Log retention costs money ($0.03/GB/month). Retaining logs indefinitely
# is expensive and usually unnecessary. 30 days covers typical incident
# investigation windows (the module default is 14). For compliance
# requirements (PCI, SOC2), you might need 90-365 days — a one-number change.
#
# ALB access logs are NOT enabled. They can only be delivered to S3 (never
# to CloudWatch Logs), so that would need a bucket and bucket policy.

# CloudWatch Alarms
#
# HOW alarms work:
# Each alarm watches a single CloudWatch metric. When the metric crosses
# the threshold for `evaluation_periods` consecutive `period`-second windows,
# the alarm fires to its alarm_actions list (the SNS topic above).
# When it recovers, it fires to ok_actions (also the SNS topic here,
# so you get a recovery notification too, not just the alert).

# WHY CPU alarm at 80% (not 100%):
# At 100% CPU, the container is already fully saturated and responding slowly.
# Alerting at 80% gives time to investigate or scale before users are impacted.
# evaluation_periods = 2 means the metric must exceed the threshold for
# two consecutive 60-second windows before the alarm fires — this prevents
# false alarms from brief, benign CPU spikes.
resource "aws_cloudwatch_metric_alarm" "ecs_frontend_cpu" {
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  alarm_name          = "${local.name}-ecs-frontend-cpu-high"
  alarm_description   = "Frontend ECS CPU utilisation above 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ClusterName = module.ecs.cluster_name
    ServiceName = "frontend"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_backend_cpu" {
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  alarm_name          = "${local.name}-ecs-backend-cpu-high"
  alarm_description   = "Backend ECS CPU utilisation above 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ClusterName = module.ecs.cluster_name
    ServiceName = "backend"
  }
}

# WHY a 5XX alarm on the ALB (not on ECS directly):
# A 5XX error from the ALB's perspective means a request reached the
# backend and the backend returned an error — the application is broken.
# This is distinct from 4XX errors (client sent a bad request) which are
# normal and do not require on-call intervention.
# evaluation_periods = 1 (not 2): a single 60-second window of 10+ 5XX
# errors is already worth investigating. 5XX errors should normally be 0.
# treat_missing_data = "notBreaching": if the ALB receives NO requests
# (no data), we treat that as OK, not as an alarm. Without this, an idle
# application would appear broken.
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  alarm_name          = "${local.name}-alb-5xx-errors"
  alarm_description   = "ALB 5XX errors exceeded threshold — application may be down"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  alarm_name          = "${local.name}-rds-cpu-high"
  alarm_description   = "RDS CPU utilisation above 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    DBInstanceIdentifier = module.db.db_instance_identifier
  }
}

# WHY a DatabaseConnections alarm:
# PostgreSQL has a hard connection limit based on instance class.
# db.t3.micro supports ~85 max connections. The connection POOL in Node.js
# defaults to 10 connections. If many tasks scale up simultaneously,
# each with its own pool, you can exhaust the limit and new connections fail.
# Alerting at 80 connections gives early warning before the hard limit is hit.
# The correct fix at scale is PgBouncer (a connection pooler) sitting between
# ECS tasks and RDS to multiplex many application connections into fewer DB connections.
resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  alarm_name          = "${local.name}-rds-connections-high"
  alarm_description   = "RDS database connections above threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    DBInstanceIdentifier = module.db.db_instance_identifier
  }
}

# Dashboard 1: Application Dashboard
# WHY two separate dashboards (not one):
# The assignment explicitly asked for "at least two dashboards".
# Beyond fulfilling the requirement, separating application-level metrics
# (request rates, error rates, latency, logs) from infrastructure metrics
# (CPU, memory, DB connections) maps to different audiences:
# - Dashboard 1 is for developers debugging application behaviour.
# - Dashboard 2 is for infrastructure/ops engineers monitoring resource health.

resource "aws_cloudwatch_dashboard" "application" {
  dashboard_name = "${local.name}-application"

  # WHY jsonencode() instead of a raw JSON string:
  # jsonencode() lets you reference Terraform variables and resource
  # attributes (like module.alb.arn_suffix) directly inside the dashboard
  # definition. A raw heredoc string cannot interpolate Terraform values.
  dashboard_body = jsonencode({
    widgets = [
      {
        # ALB Request Count: total requests per minute hitting the load balancer.
        # Useful for traffic pattern analysis and capacity planning.
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          region = "us-east-1"
          title  = "ALB — Request Count"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", module.alb.arn_suffix]
          ]
        }
      },
      {
        # ALB 5XX Error Count: application errors visible at the load balancer.
        # Spike here = something is broken in the backend ECS tasks.
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          region = "us-east-1"
          title  = "ALB — 5XX Error Count"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", module.alb.arn_suffix]
          ]
        }
      },
      {
        # ALB Response Latency: end-to-end request latency from the ALB's perspective.
        # Spike here could indicate DB query slowness or ECS task CPU saturation.
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          region = "us-east-1"
          title  = "ALB — Response Latency"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.alb.arn_suffix]
          ]
        }
      },
      {
        # Live backend application logs — the same logs visible in CloudWatch
        # Logs Insights. This gives developers a live log tail without leaving
        # the dashboard.
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          region = "us-east-1"
          title  = "Backend Application Logs"
          # Reads the log group the ECS module created for the backend container,
          # by reference, so the name can never drift from what is really written.
          query = "SOURCE '${module.ecs.services["backend"].container_definitions["backend"].cloudwatch_log_group_name}' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          view  = "table"
        }
      }
    ]
  })
}

# Dashboard 2: Infrastructure Dashboard
resource "aws_cloudwatch_dashboard" "infrastructure" {
  dashboard_name = "${local.name}-infrastructure"

  dashboard_body = jsonencode({
    widgets = [
      {
        # ECS CPU for both services on one graph — easy to compare
        # frontend vs backend CPU during the same traffic event.
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          region = "us-east-1"
          title  = "ECS — CPU Utilisation"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", module.ecs.cluster_name, "ServiceName", "frontend"],
            ["AWS/ECS", "CPUUtilization", "ClusterName", module.ecs.cluster_name, "ServiceName", "backend"]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          region = "us-east-1"
          title  = "ECS — Memory Utilisation"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ClusterName", module.ecs.cluster_name, "ServiceName", "frontend"],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", module.ecs.cluster_name, "ServiceName", "backend"]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          region = "us-east-1"
          title  = "RDS — CPU Utilisation"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", module.db.db_instance_identifier]
          ]
        }
      },
      {
        # RDS DatabaseConnections is one of the most important DB metrics.
        # See the rds_connections alarm comment above for why.
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          region = "us-east-1"
          title  = "RDS — Database Connections"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", module.db.db_instance_identifier]
          ]
        }
      }
    ]
  })
}
