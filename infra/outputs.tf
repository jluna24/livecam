output "channel_name" {
  description = "Nombre del canal de señalización de KVS"
  value       = awscc_kinesisvideo_signaling_channel.cam.name
}

output "channel_arn" {
  description = "ARN del canal de señalización de KVS"
  value       = awscc_kinesisvideo_signaling_channel.cam.arn
}
