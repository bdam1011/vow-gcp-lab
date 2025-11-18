# 監控專案已存在，移除重複定義避免衝突
# resource "google_monitoring_monitored_project" "monitoring" {
#   metrics_scope = "locations/global/metricsScopes/${local.env_monitor_project_id}"
#   name          = "locations/global/metricsScopes/${local.env_monitor_project_id}/projects/cloud-sre-poc-474602"
# }

resource "google_monitoring_notification_channel" "notification_channel_mail" {
  for_each = {
    cloud03_sec = {
      mail = "shenghui.wang@cathaybk.com.tw"
    }
  }
  project      = "cloud-sre-poc-474602"
  display_name = each.key
  type         = "email"
  labels = {
    email_address = each.value.mail
  }
  force_delete = false
}

resource "google_monitoring_alert_policy" "alert_policy" {
  project = "cloud-sre-poc-474602"
  for_each = {
    IAC-Firewall_monitored = {
      resource-type = "global"
    }
    IAC-Network_monitored = {
      resource-type = "global"
    }
    IAC-Custom_role_monitored = {
      resource-type = "global"
    }
    IAC-Owner_monitored = {
      resource-type = "global"
    }
    IAC-Audit_config_monitored = {
      resource-type = "global"
    }
    IAC-Route_monitored = {
      resource-type = "global"
    }
    IAC-Bucket_IAM_monitored = {
      resource-type = "gcs_bucket"
    }
    IAC-SQL_instance_monitored = {
      resource-type = "global"
    }
  }
  display_name = each.key
  combiner     = "OR"
  alert_strategy {
    auto_close = "259200s"
  }
  documentation {
    content   = "$${resource.project}"
    mime_type = "text/markdown"
  }
  conditions {
    display_name = each.key
    condition_threshold {
      filter     = "metric.type=\"logging.googleapis.com/user/${each.key}\" AND resource.type=\"${each.value.resource-type}\""
      duration   = "60s"
      comparison = "COMPARISON_GT"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  notification_channels = [google_monitoring_notification_channel.notification_channel_mail["cloud03_sec"].name]
  depends_on = [
    google_logging_metric.logging_metric
  ]
}
