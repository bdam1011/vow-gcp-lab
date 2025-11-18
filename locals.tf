locals {
  region = "asia-east1"

  # Lab 環境設定
  environments   = "lab"
  apid_full_name = "ovs-cp-vow-01"

  # 專案標籤
  labels = {
    "dept"    = "技術中台部"
    "section" = "數據中台發展科"
    "apid"    = local.apid_full_name
  }

  # Lab 環境專案 IDs
  project_id     = "cloud-sre-poc-474602"
  project_number = "42680339479"

  # 服務專案 IDs
  env_network_project_id = "cloud-sre-poc-474602"
  env_monitor_project_id = "cloud-sre-poc-474602"
  env_acm_project_id     = "cloud-sre-poc-474602"
  env_gkehub_project_num = "42680339479"

  # 環境前置詞
  env = "l" # lab 環境前置詞

  # 簡化變數
  apid     = replace(local.apid_full_name, "-", "")
  ap_group = "${local.apid_full_name}@cathaybk.com.tw"

  # 網域名稱
  redis_domain    = "gcublabredis"
  cloudsql_domain = "gcublabsql"

  # 認證檔案
  credentials = file("terraform-lab-creator-key.json")
}
