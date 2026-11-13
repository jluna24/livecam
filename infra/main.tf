data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  name         = "livecam"
  channel_name = "${local.name}-${var.device_id}"
}

# Los recursos se agregan por pasos (ver docs/diseno.md):
#   paso 2 → kvs.tf      (canal de señalización)
#   paso 3 → iot.tf      (thing, certificado, role alias para la Pi)
#   paso 4 → web.tf      (S3 + CloudFront) y auth.tf (Cognito)
#   paso 5 → alarms.tf   (aviso si la cámara se desconecta)
