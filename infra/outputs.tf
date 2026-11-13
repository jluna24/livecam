output "channel_name" {
  description = "Nombre del canal de señalización de KVS"
  value       = awscc_kinesisvideo_signaling_channel.cam.name
}

output "channel_arn" {
  description = "ARN del canal de señalización de KVS"
  value       = awscc_kinesisvideo_signaling_channel.cam.arn
}

output "iot_thing_name" {
  description = "Nombre del IoT thing (igual al canal)"
  value       = aws_iot_thing.pi.name
}

output "iot_role_alias" {
  description = "Role alias para el IoT credentials provider"
  value       = aws_iot_role_alias.pi.alias
}

output "iot_credentials_endpoint" {
  description = "Endpoint del IoT credentials provider (AWS_IOT_CORE_CREDENTIAL_ENDPOINT)"
  value       = data.aws_iot_endpoint.credentials.endpoint_address
}

output "pi_certificate_pem" {
  description = "Certificado de la Pi (público; se copia a la Pi como pi.crt)"
  value       = aws_iot_certificate.pi.certificate_pem
  sensitive   = true # el provider lo marca así; se lee con tofu output -raw
}
