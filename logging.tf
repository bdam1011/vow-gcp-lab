resource "google_logging_metric" "logging_metric" {
  project = "cloud-sre-poc-474602"
  for_each = {
    IAC-Firewall_monitored = {
      filter = "resource.type=\"gce_firewall_rule\" AND (protoPayload.methodName:\"compute.firewalls.insert\" OR protoPayload.methodName:\"compute.firewalls.patch\" OR protoPayload.methodName:\"compute.firewalls.delete\")"
    }
    IAC-Network_monitored = {
      filter = "resource.type=\"gce_network\" AND (protoPayload.methodName:\"compute.networks.insert\" OR protoPayload.methodName:\"compute.networks.patch\" OR protoPayload.methodName:\"compute.networks.delete\" OR protoPayload.methodName:\"compute.networks.removePeering\" OR protoPayload.methodName:\"compute.networks.addPeering\")"
    }
    IAC-Custom_role_monitored = {
      filter = "resource.type=\"iam_role\" AND (protoPayload.methodName=\"google.iam.admin.v1.CreateRole\" OR protoPayload.methodName=\"google.iam.admin.v1.DeleteRole\" OR protoPayload.methodName=\"google.iam.admin.v1.UpdateRole\")"
    }
    IAC-Owner_monitored = {
      filter = "(protoPayload.serviceName=\"cloudresourcemanager.googleapis.com\") AND (ProjectOwnership OR projectOwnerInvitee) OR (protoPayload.serviceData.policyDelta.bindingDeltas.action=\"REMOVE\" AND protoPayload.serviceData.policyDelta.bindingDeltas.role=\"roles/owner\") OR (protoPayload.serviceData.policyDelta.bindingDeltas.action=\"ADD\" AND protoPayload.serviceData.policyDelta.bindingDeltas.role=\"roles/owner\")"
    }
    IAC-Audit_config_monitored = {
      filter = "protoPayload.methodName=\"SetIamPolicy\" AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*"
    }
    IAC-Route_monitored = {
      filter = "resource.type=\"gce_route\" AND (protoPayload.methodName:\"compute.routes.delete\" OR protoPayload.methodName:\"compute.routes.insert\")"
    }
    IAC-Bucket_IAM_monitored = {
      filter = "resource.type=gcs_bucket AND protoPayload.methodName=\"storage.setIamPermissions\""
    }
    IAC-SQL_instance_monitored = {
      filter = "protoPayload.methodName=\"cloudsql.instances.update\" OR protoPayload.methodName=\"cloudsql.instances.create\" OR protoPayload.methodName=\"cloudsql.instances.delete\""
    }
  }
  name   = each.key
  filter = each.value.filter
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_logging_project_bucket_config" "logging_bucket" {
  project        = "cloud-sre-poc-474602"
  location       = "global"   # 日誌儲存位置，也可以是特定區域
  bucket_id      = "_Default" # 默認的日誌桶，或者您可以指定其他桶名
  retention_days = 30         # 設定日誌保留期限為 30 天
}