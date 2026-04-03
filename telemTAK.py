import socket
import time
from datetime import datetime, timezone, timedelta
import math
import uuid
from pymavlink import mavutil

class TelemTAK:
    def __init__(self, connection_str, tak_host, tak_port, uid, callsign):
        self.running = False
        self.master = None
        self.latest_gps = None
        self.latest_attitude = None
        self.connection_str = connection_str
        self.tak_host = tak_host
        self.tak_port = tak_port
        self.tak_socket = None
        self.uid = uid
        self.callsign = callsign

    def start(self):
        self.master = mavutil.mavlink_connection(self.connection_str)
        print("Waiting for heartbeat...")
        self.master.wait_heartbeat()
        print(f"Heartbeat received from system {self.master.target_system}")
        self.tak_socket = self._connect_tak()
        self.running = True
        self._run()
                                                                                                                                                                                                def _connect_tak(self):
        while True:
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(5)
                s.connect((self.tak_host, self.tak_port))
                print("Connected to TAK")
                return s
            except Exception as e:
                print(f"TAK unavailable: {e}, retrying in 5s...")
                time.sleep(5)

    def _run(self):
        last_sent = 0
        while self.running:
            msg = self.master.recv_match(type=['GLOBAL_POSITION_INT', 'ATTITUDE'], blocking=True, timeout=1)

            if msg is None:
                continue
            if msg.get_type() == 'GLOBAL_POSITION_INT':
                self.latest_gps = msg

            now = time.time()
            if self.latest_gps and (now - last_sent) >= 1.0:
                send = self.latest_gps
                cot = self.build_cot(send.lat / 1e7, send.lon / 1e7, send.alt / 1000.0, send.hdg / 100.0, self.uid, self.callsign)
                self.send_cot(cot, self.tak_host, self.tak_port)
                last_sent = now
                print("Sent over to TAK")

    def stop(self):
        self.running = False

    def build_cot(self, lat, lon, alt, heading, uid="drone-1", callsign="PX4-Drone"):
        now = datetime.now(timezone.utc)
        stale = now + timedelta(seconds=30)
        fmt = "%Y-%m-%dT%H:%M:%S.%fZ"

        cot = f"""<?xml version="1.0" encoding="UTF-8"?> <event version="2.0" uid="{uid}" type="a-f-A-M-H-Q" time="{now.strftime(fmt)}" start="{now.strftime(fmt)}" stale="{stale.strftime(fmt)}" how="m-g"> <point lat="{lat}" lon="{lon}" hae="{alt}" ce="10" le="10"/> <detail> <contact callsign="{callsign}"/> <track speed="0" course="{heading}"/> <remarks>PX4 MAVLink telemetry</remarks> </detail> </event>"""

        return cot.encode('utf-8')

    def send_cot(self, cot_bytes, host, port):
        try:
            self.tak_socket.sendall(cot_bytes)
        except Exception as e:
            print(f"Error: {e}")
            self.tak_socket = self._connect_tak()

if __name__ == '__main__':
    telem = TelemTAK(
            connection_str='udp:127.0.0.1:14551',
            tak_host='192.168.1.195',
            tak_port=8088,
            uid='drone-001',
            callsign='VOXL-01'
    )
    telem.start()