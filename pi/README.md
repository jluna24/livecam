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
