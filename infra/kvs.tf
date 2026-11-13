# Canal de señalización WebRTC de Kinesis Video Streams (paso 2).
# La Pi se conecta como master; los celulares, como viewers. Sin grabación.
resource "awscc_kinesisvideo_signaling_channel" "cam" {
  name                = local.channel_name
  type                = "SINGLE_MASTER"
  message_ttl_seconds = 60

  tags = [
    { key = "project", value = "livecam" },
    { key = "managed_by", value = "opentofu" },
  ]
}
