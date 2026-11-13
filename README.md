# livecam

Video **en vivo** de una webcam USB conectada a una Raspberry Pi 5, visible desde el celular en cualquier red, con **Amazon Kinesis Video Streams (WebRTC)**.

- Sin abrir puertos en el router: la Pi solo hace conexiones de salida.
- Sin servidores: la señalización y TURN los pone KVS, la página es estática (S3 + CloudFront) y el login es con Cognito.
- Sin access keys fijas: la Pi usa su certificado X.509 con el IoT credentials provider, y el celular usa credenciales temporales de Cognito.
- Costo estimado: **menos de 1 USD al mes** con uso personal.
- Toda la infraestructura está en **OpenTofu** (`infra/`).

Diseño, costos y pasos: [`docs/diseno.md`](docs/diseno.md).

## Estructura

| Carpeta | Contenido |
|---|---|
| `infra/` | OpenTofu: canal KVS, IoT, Cognito, S3/CloudFront, alarmas |
| `pi/` | Servicio master WebRTC en la Raspberry Pi (SDK de KVS en C + GStreamer) |
| `web/` | Página viewer para el celular (SDK de KVS para JavaScript) |
| `docs/` | Documentos de diseño |

## Uso de la infraestructura

```powershell
cd infra
copy terraform.tfvars.example terraform.tfvars   # ajustar valores
tofu init
tofu plan -out='plan.tfplan'
tofu apply plan.tfplan
```

Para borrar todo:

```powershell
tofu destroy
```
