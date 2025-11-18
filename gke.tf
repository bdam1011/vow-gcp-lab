locals {
  # 機器類型，可以從計算機看要幾Core幾GB的規格
  machine_type = "e2-standard-2"

  # GKE Control Plane的/28網段，可以從OneNote的GCP網路網段資訊查找
  # ex. 10.171.224.112/28
  master_ipv4_cidr_block = "10.171.226.176/28"

  # GKE的Pod Name，與Control Plane的資訊互相對應，可以從OneNote的GCP網路網段資訊查找
  # ex. gke-pod08
  cluster_secondary_range_name = "gke-pod44"

  # 控制層授權網路，連到GKE Master Node的授權IP，請與以下環境做對應
  # LAB:  (無開放，因為使用私有端點)
  # UT:   10.171.12.5/32
  # UAT:  10.171.44.5/32
  # PROD: 10.171.76.5/32
  cidr_block = local.environments == "lab" ? "10.171.0.0/16" : local.environments == "ut" ? "10.171.12.5/32" : local.environments == "uat" ? "10.171.44.5/32" : "10.171.76.5/32"

  # GKE的Tags，依需求填寫
  # 有需要出外網則加入Proxy的Tag ${environments}-proxy-client
  # 
  tags = ["lb-health-check"] //tag

  subnetwork_gke_tier = google_compute_subnetwork.gke-subnet.id
}

# GKE SA
resource "google_service_account" "gke_sa" {
  project      = "cloud-sre-poc-474602"
  display_name = "${local.apid}-gke-sa"
  account_id   = "${local.apid}-gke-sa"
}

# 建立 GKE Hub 服務帳戶身份
resource "google_project_service_identity" "gcp_sa_gkehub" {
  provider = google-beta
  project  = "cloud-sre-poc-474602"
  service  = "gkehub.googleapis.com"
}

# Topic gke-update-notification
resource "google_pubsub_topic" "gke-update-notification" {
  project = "cloud-sre-poc-474602"
  name    = "gke-update-notification"
}

resource "google_project_iam_member" "iam_member_gke" {
  for_each = {
    logging_logWriter_gke = {
      project = "cloud-sre-poc-474602"
      role    = "roles/logging.logWriter"
      member  = "serviceAccount:${google_service_account.gke_sa.email}"
    }
    monitoring_metric_writer_gke = {
      project = "cloud-sre-poc-474602"
      role    = "roles/monitoring.metricWriter"
      member  = "serviceAccount:${google_service_account.gke_sa.email}"
    }
    gkehub_serviceAgent = {
      project = "cloud-sre-poc-474602"
      role    = "roles/gkehub.serviceAgent"
      member  = "serviceAccount:service-${local.project_number}@gcp-sa-gkehub.iam.gserviceaccount.com"
    }
  }
  project = each.value.project
  role    = each.value.role
  member  = each.value.member
  depends_on = [
    google_service_account.gke_sa,
    google_project_service_identity.gcp_sa_gkehub
  ]
}

resource "google_container_cluster" "gke_primary01" {
  project                   = "cloud-sre-poc-474602"
  name                      = "${local.env}gk${local.apid}g01"
  location                  = local.region
  remove_default_node_pool  = true
  initial_node_count        = 1
  default_max_pods_per_node = 32
  network                   = google_compute_network.lab-vpc.id
  subnetwork                = local.subnetwork_gke_tier
  maintenance_policy {
    recurring_window {
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
      start_time = "2023-08-24T16:00:00Z"
      end_time   = "2023-08-24T22:00:00Z"
    }
    # Lab 環境不設定維護排除期間
    # maintenance_exclusion {
    #   exclusion_name = "20250107-20250930"
    #   start_time     = "2025-01-07T16:00:00Z"
    #   end_time       = "2025-09-30T16:00:00Z"
    #   exclusion_options {
    #     scope = "NO_MINOR_OR_NODE_UPGRADES"
    #   }
    # }
  }
  notification_config {
    pubsub {
      enabled = true
      topic   = google_pubsub_topic.gke-update-notification.id
    }
  }
  addons_config {
    network_policy_config {
      disabled = false
    }
  }
  network_policy {
    enabled  = true
    provider = "CALICO"
  }
  workload_identity_config {
    workload_pool = "cloud-sre-poc-474602.svc.id.goog"
  }
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = local.master_ipv4_cidr_block //control plane
  }
  ip_allocation_policy {
    cluster_secondary_range_name  = local.cluster_secondary_range_name //pods
    services_secondary_range_name = "gke-svc44"                        //services
  }
  monitoring_config {
    managed_prometheus {
      enabled = true //啟用GMP
    }
    enable_components = [
      "SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER",
      "CONTROLLER_MANAGER", "STORAGE", "POD", "DEPLOYMENT", "STATEFULSET", "DAEMONSET",
      "HPA", "CADVISOR", "KUBELET"
    ]
  }
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = local.cidr_block //連master入口
      display_name = ""
    }
  }
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  release_channel {
    channel = "STABLE"
  }
  enterprise_config {
    desired_tier = "ENTERPRISE"
  }
  lifecycle {
    ignore_changes = [
      maintenance_policy
    ]
  }
  depends_on = [
    google_project_iam_member.iam_member_gke,
    google_pubsub_topic.gke-update-notification
  ]
}

resource "google_container_node_pool" "gke_node_pool01" {
  project        = "cloud-sre-poc-474602"
  name           = "${local.env}np${local.apid}g01"
  location       = local.region
  cluster        = google_container_cluster.gke_primary01.name
  node_count     = 1
  node_locations = ["${local.region}-a", "${local.region}-b", "${local.region}-c"]
  node_config {
    tags            = local.tags
    machine_type    = local.machine_type
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.gke_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring"
    ]
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_secure_boot = true
    }
    # labels = {
    #   mesh_id = "proj-${google_project.project.number}"
    # }
  }
  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }
  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }
  lifecycle {
    ignore_changes = [
      node_count
    ]
  }
  depends_on = [
    google_container_cluster.gke_primary01,
    google_project_iam_member.iam_member_gke
  ]
}

# 註冊到Anthos shared-services project
resource "google_gke_hub_membership" "gke_primary01_acm" {
  project       = local.env_acm_project_id
  membership_id = "${local.env}gk${local.apid}g01"
  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${google_container_cluster.gke_primary01.id}"
    }
  }
  authority {
    issuer = "https://container.googleapis.com/v1/${google_container_cluster.gke_primary01.id}"
  }
  depends_on = [
    google_container_cluster.gke_primary01,
    google_project_iam_member.iam_member_gke
  ]
}
