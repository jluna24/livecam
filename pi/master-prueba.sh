#!/usr/bin/env bash
# Paso 2: corre el ejemplo master de KVS WebRTC (con el parche de pi/patches/)
# usando la webcam. Las credenciales temporales llegan por variables de entorno
# (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN); no se guardan en disco.
#
# Uso: CANAL=livecam-pi5-cam-01 ./master-prueba.sh
set -euo pipefail

: "${CANAL:?Falta CANAL (nombre del canal de señalización)}"
: "${AWS_ACCESS_KEY_ID:?Faltan credenciales temporales}"
: "${AWS_SESSION_TOKEN:?Faltan credenciales temporales (session token)}"
SDK=${SDK:-$HOME/kvs-webrtc}
W=${W:-1280}; H=${H:-720}; FPS=${FPS:-15}; KBPS=${KBPS:-1500}
DEV=${DEV:-$(ls /dev/v4l/by-id/*C922*index0 2>/dev/null | head -n1 || echo /dev/video0)}

export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-2}
export AWS_KVS_CACERT_PATH=$SDK/certs/cert.pem
export AWS_KVS_LOG_LEVEL=${AWS_KVS_LOG_LEVEL:-3}   # 3 = info

# Mismo pipeline que pi/prueba-camara.sh, terminando en el appsink que espera el SDK.
export LIVECAM_GST_VIDEO="v4l2src device=$DEV do-timestamp=true \
! image/jpeg,width=$W,height=$H,framerate=$FPS/1 ! jpegdec ! videoconvert ! video/x-raw,format=I420 \
! x264enc name=sampleVideoEncoder bframes=0 speed-preset=ultrafast tune=zerolatency bitrate=$KBPS key-int-max=$((FPS * 2)) byte-stream=true \
! video/x-h264,stream-format=byte-stream,alignment=au,profile=baseline \
! appsink sync=TRUE emit-signals=TRUE name=appsink-video"

cd "$SDK/build/samples"
exec ./kvsWebrtcClientMasterGstSample "$CANAL" video-only devicesrc
