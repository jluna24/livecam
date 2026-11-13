#!/usr/bin/env bash
# Paso 1: prueba de captura + codificación H.264 sin AWS.
# Corre el mismo tipo de pipeline que usará el master de KVS y registra
# fps, CPU de gst-launch, temperatura, ventilador y throttling.
#
# Uso: ./prueba-camara.sh [minutos] [ancho] [alto] [fps] [kbps]
# Ej.: ./prueba-camara.sh 10 1280 720 15 1500
set -euo pipefail

MIN=${1:-10}
W=${2:-1280}
H=${3:-720}
FPS=${4:-15}
KBPS=${5:-1500}
DEV=${DEV:-$(ls /dev/v4l/by-id/*C922*index0 2>/dev/null | head -n1 || echo /dev/video0)}
LOG=${LOG:-prueba-${W}x${H}-${FPS}fps-$(date +%Y%m%d-%H%M%S).log}

echo "Dispositivo: $DEV | ${W}x${H} @ ${FPS} fps, ${KBPS} kbps, ${MIN} min | log: $LOG"

# La C922 no da H.264 nativo: MJPEG -> jpegdec -> x264enc (como en el ejemplo de KVS).
gst-launch-1.0 -e -v \
  v4l2src device="$DEV" do-timestamp=true \
  ! image/jpeg,width="$W",height="$H",framerate="$FPS"/1 \
  ! jpegdec ! videoconvert ! video/x-raw,format=I420 \
  ! x264enc bframes=0 speed-preset=ultrafast tune=zerolatency bitrate="$KBPS" key-int-max=$((FPS * 2)) byte-stream=true \
  ! video/x-h264,stream-format=byte-stream,alignment=au,profile=baseline \
  ! fpsdisplaysink text-overlay=false video-sink=fakesink sync=false \
  > "$LOG.gst" 2>&1 &
GST=$!
# En scripts, bash lanza los procesos en segundo plano ignorando SIGINT: usar TERM y esperar.
trap 'kill -TERM $GST 2>/dev/null || true; wait $GST 2>/dev/null || true' EXIT

printf "%-8s %6s %6s %7s %6s %s\n" seg cpu% temp fan_rpm fps throttled | tee "$LOG"
END=$(( $(date +%s) + MIN * 60 ))
T0=$(date +%s)
MAXT=0
while [ "$(date +%s)" -lt "$END" ]; do
  sleep 10
  kill -0 $GST 2>/dev/null || { echo "gst-launch terminó antes de tiempo; ver $LOG.gst" | tee -a "$LOG"; exit 1; }
  CPU=$(ps -o %cpu= -p $GST | tr -d ' ')
  TEMP=$(vcgencmd measure_temp | grep -oE '[0-9.]+')
  FAN=$(cat /sys/devices/platform/cooling_fan/hwmon/*/fan1_input 2>/dev/null || echo -)
  FPSNOW=$(grep -oE 'current: [0-9.]+' "$LOG.gst" | tail -n1 | awk '{print $2}')
  THR=$(vcgencmd get_throttled | cut -d= -f2)
  printf "%-8s %6s %6s %7s %6s %s\n" $(( $(date +%s) - T0 )) "$CPU" "$TEMP" "$FAN" "${FPSNOW:--}" "$THR" | tee -a "$LOG"
  MAXT=$(awk -v a="$MAXT" -v b="$TEMP" 'BEGIN{print (b>a)?b:a}')
done

echo "Listo. Temperatura máxima: ${MAXT} °C (objetivo < 75 °C)" | tee -a "$LOG"
