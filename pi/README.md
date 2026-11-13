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
