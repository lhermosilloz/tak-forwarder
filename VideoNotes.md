In order to test streaming to the OpenTAKServer, here is a manual way to have the OpenTAKServer pull from the drone's camera stream.

SSH onto the device running your OpenTAKServer. In our case, its a Raspberry Pi 5.

nano ~/ots/mediamtx/mediamtx.yml

Go to the very bottom where you'll find:
paths:
  startup:
    runOnInit: curl -s http://localhost:8081/api/mediamtx/webhook?path=$MTX_PATH&rtsp_port=$RTSP_PORT&event=init&token=uGijHpvoDkK7yXBUsXmey3fNd1x5hw > /dev/null
  # example:
  # my_camera:
  #   source: rtsp://my_camera

  # ADD HERE
  drone1:
    source: rtsp://192.168.1.132:8900/live
    sourceOnDemand: no
  # This sourceOnDemand line will prompt for OTS username and password

  # Settings under path "all_others" are applied to all paths that
  # do not match another entry.
  all_others:

sudo systemctl restart mediamtx.service

All goes well, your ATAK connection should allow you to:
1. Click Videos
2. Click download
3. Select and search from OpenTAKServer
4. Click on drone entry
5. Enter username and password
6. Select the video feed

--

For something more scalable, the drones should automatically stream.

Clear the previous changes and instead add this:

paths:
  startup:
    runOnInit: curl -s ...

  "~.*":
    source: publisher

  all_others:

After that, make an executable script to test streaming from the drone to the OTS server manually

#!/bin/bash
OTS_IP="192.168.1.195"
STREAM="rtsp://192.168.1.132:8900/live" 

sleep 5

exec ffmpeg -rtsp_transport tcp -i rtsp://localhost:8900/live -c copy -f rtsp rtsp://user0:12345678@${OTS_IP}:8554/${STREAM}