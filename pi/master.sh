#!/usr/bin/env bash
# Paso 3: master WebRTC de KVS para systemd. Saca credenciales temporales del
# IoT credentials provider con el certificado de la Pi (sin access keys).
# Configuración en livecam.env (ver livecam.env.example).
set -euo pipefail

: "${CANAL:?Falta CANAL}"
: "${AWS_IOT_CORE_CREDENTIAL_ENDPOINT:?Falta AWS_IOT_CORE_CREDENTIAL_ENDPOINT}"
: "${AWS_IOT_CORE_ROLE_ALIAS:?Falta AWS_IOT_CORE_ROLE_ALIAS}"
: "${AWS_IOT_CORE_CERT:?Falta AWS_IOT_CORE_CERT}"
: "${AWS_IOT_CORE_PRIVATE_KEY:?Falta AWS_IOT_CORE_PRIVATE_KEY}"
export AWS_IOT_CORE_THING_NAME=${AWS_IOT_CORE_THING_NAME:-$CANAL}

SDK=${SDK:-$HOME/kvs-webrtc}
W=${W:-1280}; H=${H:-720}; FPS=${FPS:-15}; KBPS=${KBPS:-1500}
DEV=${DEV:-$(ls /dev/v4l/by-id/*C922*index0 2>/dev/null | head -n1 || echo /dev/video0)}
[ -e "$DEV" ] || { echo "No está la webcam ($DEV)"; exit 1; }

export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-2}
export AWS_KVS_CACERT_PATH=${AWS_KVS_CACERT_PATH:-$SDK/certs/cert.pem}
export AWS_KVS_LOG_LEVEL=${AWS_KVS_LOG_LEVEL:-3}

export LIVECAM_GST_VIDEO="v4l2src device=$DEV do-timestamp=true \
! image/jpeg,width=$W,height=$H,framerate=$FPS/1 ! jpegdec ! videoconvert ! video/x-raw,format=I420 \
! x264enc name=sampleVideoEncoder bframes=0 speed-preset=ultrafast tune=zerolatency bitrate=$KBPS key-int-max=$((FPS * 2)) byte-stream=true \
! video/x-h264,stream-format=byte-stream,alignment=au,profile=baseline \
! appsink sync=TRUE emit-signals=TRUE name=appsink-video"

# El SDK escribe su caché de señalización en el directorio actual.
cd "$SDK/build/samples"
# stdbuf: sin esto, printf del SDK queda en buffer y no llega al journal.
exec stdbuf -oL -eL ./kvsWebrtcClientMasterGstSample "$CANAL" video-only devicesrc
