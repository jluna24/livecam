# livecam — documento de diseño

> Estado: **diseño aprobado, paso 0 (base del repo) en curso.**

## 1. Objetivo

Ver **en vivo desde el celular, desde cualquier red** (también con datos móviles), una webcam USB conectada a una Raspberry Pi 5 que está siempre encendida en casa.

- **Sin grabación:** solo video en vivo.
- **Sin abrir puertos** en el router: la Pi solo hace conexiones de salida.
- **Sin servidores encendidos** (nada de EC2): todo es administrado o estático.
- **Sin access keys fijas** en la Pi ni en la página.
- **Todo en OpenTofu** (`infra/`), y se borra con `tofu destroy`.

## 2. Arquitectura

```
Webcam USB (Logitech) ─► Raspberry Pi 5
                          servicio systemd "master" WebRTC (SDK de KVS en C + GStreamer)
                          │  solo conexiones de salida (HTTPS / WSS)
                          │  credenciales temporales: certificado X.509 → IoT credentials provider
                          ▼
            Amazon Kinesis Video Streams — canal de señalización WebRTC
            + servidores STUN/TURN administrados
                          ▲
                          │  WSS (señalización); video P2P o vía TURN
                          │
Celular ─► página estática (S3 privado + CloudFront, HTTPS)
           └─► login con Cognito (User Pool) → Identity Pool → credenciales temporales de "viewer"
```

### Cómo fluye una conexión

1. La Pi arranca, pide credenciales temporales a IoT Core con su certificado y se conecta al canal como **master**. Se queda esperando.
2. Abres la página en el celular e inicias sesión con Cognito. El Identity Pool te da credenciales que **solo permiten ser viewer de ese canal**.
3. El navegador se conecta al canal como **viewer**. La Pi y el celular intercambian ofertas SDP y candidatos ICE por el canal.
4. Con STUN intentan conectarse **directo**, sin costo de video. Si el NAT no lo permite, lo normal con datos móviles, el video pasa por **TURN** de KVS.

### Por qué no hace falta abrir puertos

La Pi solo abre conexiones salientes: al endpoint de señalización (WSS) y a STUN/TURN. WebRTC atraviesa NAT con ICE. Si la conexión directa falla, TURN la retransmite y tanto la Pi como el celular se conectan **hacia** el servidor TURN.

## 3. Piezas de AWS

| Pieza | Para qué | Archivo |
|---|---|---|
| Canal de señalización KVS (`SINGLE_MASTER`) | Conectar al master (Pi) con los viewers | `infra/kvs.tf` |
| IoT thing + certificado + política | Identidad de la Pi | `infra/iot.tf` |
| Rol IAM + **role alias** de IoT | Credenciales temporales de master para la Pi (`ConnectAsMaster`, `GetSignalingChannelEndpoint`, `GetIceServerConfig`) | `infra/iot.tf` |
| S3 (privado) + CloudFront con OAC | Hospedar la página con HTTPS | `infra/web.tf` |
| Cognito User Pool + Identity Pool | Login y credenciales temporales de viewer (`ConnectAsViewer`, `GetSignalingChannelEndpoint`, `GetIceServerConfig`) | `infra/auth.tf` |
| Alarma de CloudWatch + SNS | Aviso si la Pi deja de conectarse al canal | `infra/alarms.tf` |

Región: **us-east-2**. Va en la cuenta que usaba DualMind, con estado de OpenTofu separado.

## 4. Costo estimado

Precios de us-east-1/us-east-2 según la página de precios de KVS (verificado 2026-11-12):

| Concepto | Precio | Uso esperado | Costo |
|---|---|---|---|
| Canal de señalización activo | 0.03 USD / canal / mes | 1 canal | 0.03 USD/mes |
| Mensajes de señalización | 2.25 USD / millón | cientos a miles | < 0.01 USD |
| TURN | 0.12 USD / 1,000 min | ~2 h/día → ~3,600 min/mes | ~0.43 USD/mes |
| Transferencia de datos de TURN a internet | tarifa estándar de AWS (los primeros 100 GB/mes de salida son gratis) | ~1.5 Mbps × 2 h/día ≈ 40 GB/mes | 0 USD dentro de la capa gratuita |
| S3 + CloudFront (página estática) | capa gratuita | KB | ~0 USD |
| Cognito | gratis hasta 10,000 usuarios activos al mes | 1 usuario | 0 USD |
| IoT credentials provider | sin costo propio | — | 0 USD |

- **Total: menos de 1 USD al mes** con uso moderado. Una prueba de 3 días sale en centavos.
- El video **P2P directo no tiene costo**.
- KVS **no tiene capa gratuita**.

## 5. Webcam y codificación

- **La Pi 5 no tiene codificador H.264 por hardware**, a diferencia de la Pi 4.
- **Si la webcam entrega H.264 nativo** (algunas Logitech C920 de primeras versiones): se reenvía sin recodificar y casi no gasta CPU.
- **Si entrega MJPEG o YUYV:** se codifica por software con `x264enc` (`tune=zerolatency`, `speed-preset=ultrafast`). Es suficiente para 720p a 15–30 fps en la Pi 5, pero ocupa 1–2 núcleos y la calienta, así que requiere el disipador activo.
- **Arranque conservador:** 1280×720 a 15 fps y ~1.5 Mbps. Se sube si el CPU y la temperatura lo permiten.

## 6. Pasos

| Paso | Qué | Listo cuando |
|---|---|---|
| **0** | Repo, `.gitignore` y base de OpenTofu | `tofu init` y `tofu validate` OK; primer commit en GitHub |
| **1** | Webcam en la Pi sin AWS: formatos (`v4l2-ctl --list-formats-ext`), prueba de captura y codificación con GStreamer, CPU y temperatura | Pipeline estable de 10 min a 720p con temperatura < 75 °C |
| **2** | Canal KVS (OpenTofu); compilar el SDK de WebRTC de KVS en C en la Pi; correr el ejemplo master con GStreamer y la webcam | Video visible en el visor WebRTC de la consola de KVS. En esta prueba se usan credenciales temporales de la sesión, sin access key en la Pi |
| **3** | IoT thing + certificado + role alias (OpenTofu); el master usa el IoT credentials provider; servicio systemd con reinicio automático | Sobrevive un reinicio de la Pi y un corte de internet sin intervención |
| **4** | S3 + CloudFront + Cognito (OpenTofu); página viewer con el SDK de JavaScript de KVS | Video en el celular **con datos móviles**, fuera del WiFi |
| **5** | Alarma de desconexión; revisión de costo tras 24 h; README de operación y borrado | Costo real confirmado; `tofu destroy` documentado |

## 7. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| La Pi 5 se calienta al codificar por software | Disipador activo; 720p a 15 fps; medir en el paso 1 |
| La compilación del SDK de C en Debian 13 (trixie) da problemas | Fijar una versión del SDK; dependencias de GStreamer desde apt; documentar los pasos en `pi/README.md` |
| Cortes de luz o internet | systemd `Restart=always`; el SDK se reconecta al canal; alarma en el paso 5 |
| Alguien más ve la cámara | Página detrás de Cognito; el rol del Identity Pool solo da permiso de viewer de ese canal; sin registro abierto en el User Pool (el usuario se crea con OpenTofu o el CLI) |
| Filtrar datos de la cuenta en el repo público | `.gitignore` para estado, `tfvars`, certificados y `config.js` generado; `git grep` del ID de cuenta y de `AKIA` antes de cada commit |
| `SINGLE_MASTER` admite pocos viewers simultáneos (hasta 10) | Suficiente para uso personal |
