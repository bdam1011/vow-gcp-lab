#創建monitoring_alert使用之pubsub
resource "google_pubsub_topic" "standard_log_alert_pubsub" {
  project = "cloud-sre-poc-474602"
  name    = "standard_log_alert_pubsub"
}

#建立monitoring_alert使用之channel
resource "google_monitoring_notification_channel" "pubsub_channel" {
  project      = "cloud-sre-poc-474602"
  display_name = "alert_policy_to_standard_log_alert_pubsub"
  type         = "pubsub"
  labels = {
    topic = google_pubsub_topic.standard_log_alert_pubsub.id
  }
  depends_on = [
    google_pubsub_topic.standard_log_alert_pubsub
  ]
}

#授權SA能使用所選之channel
resource "google_pubsub_topic_iam_member" "pubsub-publisher-log-metric-channel" {
  project = "cloud-sre-poc-474602"
  topic   = google_pubsub_topic.standard_log_alert_pubsub.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-42680339479@gcp-sa-monitoring-notification.iam.gserviceaccount.com"
  depends_on = [
    google_pubsub_topic.standard_log_alert_pubsub,
    google_monitoring_notification_channel.pubsub_channel
  ]
}
