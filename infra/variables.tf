variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-2"
}

variable "device_id" {
  description = "Identificador de la cámara (se usa en el thing de IoT y el canal de KVS)"
  type        = string
  default     = "pi5-cam-01"
}
