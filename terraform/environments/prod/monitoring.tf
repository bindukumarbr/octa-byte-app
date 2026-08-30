
# Alerting (SNS)
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

# CloudWatch Log Groups (Centralized Logging)

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${local.name}/frontend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name}/backend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "alb_access" {
  name              = "/aws/alb/${local.name}"
  retention_in_days = 30
}

# CloudWatch Alarms

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
resource "aws_cloudwatch_dashboard" "application" {
  dashboard_name = "${local.name}-application"

  dashboard_body = jsonencode({
    widgets = [
      {
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
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
            region = "us-east-1"
          title  = "Backend Application Logs"
          query  = "SOURCE '/ecs/${local.name}/backend' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          region = var.aws_region
          view   = "table"
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

