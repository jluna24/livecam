# pi/ — master WebRTC en la Raspberry Pi 5

Equipo: Raspberry Pi 5 (8 GB), Debian 13 (trixie) aarch64, webcam Logitech C922 Pro Stream, disipador activo.

## Paso 1: webcam y codificación (sin AWS)

Dependencias:

```bash
sudo apt install -y v4l-utils gstreamer1.0-tools gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly
```

Formatos de la cámara:

```bash
v4l2-ctl -d /dev/video0 --list-formats-ext
```

La C922 no entrega H.264, así que se usa MJPEG y se codifica con `x264enc` (la Pi 5 no tiene codificador por hardware).

Prueba de captura y codificación, con registro de fps, CPU, temperatura, ventilador y throttling cada 10 s:

```bash
mkdir -p logs
LOG=logs/720p15.log ./prueba-camara.sh 10 1280 720 15 1500   # minutos ancho alto fps kbps
```

Resultado de referencia a 720p y 15 fps: ~28 % de un núcleo y una máxima de 53.8 °C en 10 min.

## Paso 2: SDK de WebRTC de KVS en C y master de prueba

```bash
sudo apt install -y cmake libssl-dev libcurl4-openssl-dev liblog4cplus-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
git clone --depth 1 --branch v1.20.0 \
  https://github.com/awslabs/amazon-kinesis-video-streams-webrtc-sdk-c.git ~/kvs-webrtc
cd ~/kvs-webrtc && git apply /ruta/a/livecam/pi/patches/0001-livecam-pipeline-env.patch
mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Release && make -j4   # cmake ~9 min
```

El parche permite pasar el pipeline de GStreamer por `LIVECAM_GST_VIDEO`. Hace falta porque el `autovideosrc` del ejemplo pide video crudo a 720p y 25 fps, y la C922 no lo da.

Para la prueba, la Pi recibe credenciales temporales (`sts get-federation-token`) con una política que solo permite master sobre el canal. Se pasan por variables de entorno, sin escribirlas en disco, y **sin `\r`** si se generan en Windows:

```bash
CANAL=livecam-pi5-cam-01 ./master-prueba.sh
```

El video se ve en la consola: Kinesis Video Streams → **Signaling channels** → el canal → **Media playback viewer**.

## Paso 3: identidad con IoT y servicio systemd

1. En la Pi, generar la llave y el CSR (la llave nunca sale de la Pi):
   ```bash
   mkdir -p -m 700 ~/livecam/certs && cd ~/livecam/certs
   (umask 077; openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out pi.key)
   openssl req -new -key pi.key -subj "/CN=livecam-pi5-cam-01" -out pi.csr
   ```
2. Copiar `pi.csr` a `infra/pi.csr` (fuera de git), aplicar con `tofu apply` y copiar el certificado a la Pi:
   ```bash
   tofu output -raw pi_certificate_pem > pi.crt   # → ~/livecam/certs/pi.crt
   ```
3. Compilar el ejemplo con IoT: `cmake .. -DCMAKE_BUILD_TYPE=Release -DIOT_CORE_ENABLE_CREDENTIALS=ON && make -j4`.
4. Crear `~/livecam/livecam.env` (modo 600) a partir de `livecam.env.example`, con el endpoint que da `tofu output iot_credentials_endpoint`. Copiar `master.sh` a `~/livecam/`.
5. Instalar el servicio:
   ```bash
   sudo cp ~/livecam/livecam-master.service /etc/systemd/system/
   sudo systemctl enable systemd-time-wait-sync
   sudo systemctl daemon-reload && sudo systemctl enable --now livecam-master
   journalctl -u livecam-master -f
   ```

Probar el certificado sin el SDK:

```bash
curl --cert pi.crt --key pi.key -H 'x-amzn-iot-thingname: livecam-pi5-cam-01' \
  https://<endpoint>/role-aliases/livecam-pi-master/credentials
```
