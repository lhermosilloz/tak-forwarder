#!/bin/bash
# videoTAK - Forwards voxl-streamer RTSP stream to OpenTAKServer MediaMTX
OTS_IP=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('/etc/telemtak/config.ini'); print(c['tak']['host'])")
STREAM=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('/etc/telemtak/config.ini'); print(c['video']['stream_path'])")
USERNAME=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('/etc/telemtak/config.ini'); print(c['video']['username'])")
PASSWORD=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('/etc/telemtak/config.ini'); print(c['video']['password'])")

sleep 5

exec ffmpeg \
  -rtsp_transport tcp \
  -i rtsp://localhost:8900/live \
  -c copy \
  -f rtsp \
  rtsp://${USERNAME}:${PASSWORD}@${OTS_IP}:8554/${STREAM}