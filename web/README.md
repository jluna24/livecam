# web/ — página viewer

Página estática (sin build) que se sirve desde S3 + CloudFront (`infra/web.tf`).

| Archivo | Qué hace |
|---|---|
| `index.html`, `style.css` | Video, estado y botones |
| `app.js` | Login con Cognito (PKCE) → credenciales del Identity Pool → endpoint y servidores ICE de KVS → WebRTC de solo recepción |
| `vendor/` | [SDK de KVS para JavaScript](https://github.com/awslabs/amazon-kinesis-video-streams-webrtc-sdk-js) 2.9.0 (Apache-2.0) y [aws4fetch](https://github.com/mhart/aws4fetch) 1.0.20 (MIT) |
| `config.js` | **No está en el repo:** OpenTofu lo genera directo en S3 con los IDs reales |

Al cambiar cualquier archivo: `tofu apply` lo sube (CloudFront no cachea, así que los cambios se ven de inmediato).

Crear un usuario (no hay registro abierto):

```powershell
aws cognito-idp admin-create-user --region us-east-2 --user-pool-id (tofu output -raw user_pool_id) `
  --username correo@ejemplo.com --user-attributes Name=email,Value=correo@ejemplo.com Name=email_verified,Value=true `
  --desired-delivery-mediums EMAIL
```
