resource "google_kms_key_ring" "key_ring_01" {
  project  = "cloud-sre-poc-474602"
  name     = "${local.env}kr${local.apid}g01"
  location = local.region
}

resource "google_kms_crypto_key" "crypto_key_01" {
  name            = "${local.env}kk${local.apid}g01"
  key_ring        = google_kms_key_ring.key_ring_01.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "31536000s"
  version_template {                                 //Optional，如無設定則防護等級為軟體
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION" //Required，演算法
    protection_level = "HSM"                         //調整回 HSM 防護等級
  }
  depends_on = [google_kms_key_ring.key_ring_01]
}