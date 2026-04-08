import socket
import time
import signal
import logging
import configparser
from datetime import datetime, timezone, timedelta
from pymavlink import mavutil

logging.basicConfig(
    level=logging.INFO, 
    format='%(asctime)s %(levelname)s %(message)s'
)
log = logging.getLogger('telemTAK')

class TelemTAK:
    def __init__(self, connection_str, tak_host, tak_port, uid, callsign, stream_path=None, video_user=None, video_pass=None):
        """Initialize TelemTAK with MAVLink and TAK server connection parameters."""
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
        self.stream_path = stream_path  # None disables __video tag
        self.video_user = video_user
        self.video_pass = video_pass

    def start(self):
        """Establish MAVLink and TAK connections, then begin the main loop."""
        self._connect_mavlink()
        self.tak_socket = self._connect_tak()
        self.running = True
        self._run()

    def _connect_mavlink(self):
        """Connect to PX4 via MAVLink, retrying indefinitely until successful."""
        while True:
            try:
                log.info(f"Connecting to MAVLink at {self.connection_str}...")
                self.master = mavutil.mavlink_connection(self.connection_str)
                self.master.wait_heartbeat(timeout=10)
                log.info(f"Heartbeat received from system {self.master.target_system}")
                return
            except Exception as e:
                log.warning(f"MAVLink connection failed: {e}, retrying in 5s...")
                time.sleep(5)

    def _connect_tak(self):
        """Connect to OpenTAKServer via TCP, retrying indefinitely until successful."""
        while True:
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(5)
                s.connect((self.tak_host, self.tak_port))
                log.info(f"Connected to TAK at {self.tak_host}:{self.tak_port}")
                return s
            except Exception as e:
                log.warning(f"TAK unavailable: {e}, retrying in 5s...")
                time.sleep(5)

    def _run(self):
        """Main loop. Reads MAVLink messages, builds CoT, and forwards to OTS at 1Hz."""
        last_sent = 0
        last_msg_time = time.time()
        while self.running:
            # Watchdog: reconnect if no MAVLink messages received in 10 seconds
            if (time.time() - last_msg_time) > 10:
                log.warning("MAVLink stalled, reconnecting...")
                self._connect_mavlink()
                last_msg_time = time.time()

            try:
                msg = self.master.recv_match(type=['GLOBAL_POSITION_INT', 'ATTITUDE'], blocking=True, timeout=1)
            except Exception as e:
                log.error(f"MAVLink read error: {e}, reconnecting...")
                self._connect_mavlink()
                continue
                
            if msg is None:
                continue

            last_msg_time = time.time()

            if msg.get_type() == 'GLOBAL_POSITION_INT':
                # Dont want zeroed out GPS
                if msg.lat == 0 and msg.lon == 0:
                    continue
                self.latest_gps = msg

            now = time.time()
            # Rate limit CoT to 1Hz to avoid flooding OTS
            if self.latest_gps and (now - last_sent) >= 1.0:
                send = self.latest_gps
                cot = self.build_cot(
                    send.lat / 1e7,
                    send.lon / 1e7,
                    send.alt / 1000.0,
                    send.hdg / 100.0,
                    self.uid,
                    self.callsign
                )
                self.send_cot(cot)
                last_sent = now
                log.info(f"CoT sent | lat={send.lat/1e7:.6f} lon={send.lon/1e7:.6f} alt={send.alt/1000.0:.1f}m")

    def stop(self):
        """Gracefully shut down MAVLink and TAK connections."""
        log.info("Shutting down...")
        self.running = False
        if self.tak_socket:
            try:
                self.tak_socket.close()
            except Exception:
                pass
        if self.master:
            try:
                self.master.close()
            except Exception:
                pass

    def build_cot(self, lat, lon, alt, heading, uid, callsign):
        """Build a CoT XML event string from PX4 GPS data."""
        now = datetime.now(timezone.utc)
        stale = now + timedelta(seconds=30)
        fmt = "%Y-%m-%dT%H:%M:%S.%fZ"

        # Build optional __video block if stream_path is configured
        if self.stream_path:
            video_block = f"""<__video uid="{uid}-video" url="rtsp://{self.tak_host}:8554/{self.stream_path}"><ConnectionEntry uid="{uid}-video" alias="{callsign} Camera" address="{self.tak_host}" port="8554" path="{self.stream_path}" protocol="rtsp" type="raw" roverPort="-1" ignoreEmbeddedKLV="false" bufferTime="-1" networkTimeout="10000" rtspReliable="1" user="{self.video_user}" password="{self.video_pass}"/></__video>"""
            # video_block = f"""<__video><ConnectionEntry uid="{uid}" alias="{callsign} Camera" address="{self.tak_host}" port="8554" path="/{self.stream_path}" protocol="rtsp" type="raw" roverPort="-1" ignoreEmbeddedKLV="false" bufferTime="-1" networkTimeout="10000" rtspReliable="1"/></__video>"""
        else:
            video_block = ""

        cot = f"""<?xml version="1.0" encoding="UTF-8"?> <event version="2.0" uid="{uid}" type="a-f-A-M-H-Q" time="{now.strftime(fmt)}" start="{now.strftime(fmt)}" stale="{stale.strftime(fmt)}" how="m-g"> <point lat="{lat}" lon="{lon}" hae="{alt}" ce="10" le="10"/> <detail> <contact callsign="{callsign}"/> <track speed="0" course="{heading}"/> <remarks>PX4 MAVLink telemetry</remarks>{video_block} </detail> </event>"""

        return cot.encode('utf-8')

    def send_cot(self, cot_bytes):
        """Send CoT bytes over persistent TCP socket, reconnecting on failure."""
        try:
            self.tak_socket.sendall(cot_bytes)
        except Exception as e:
            log.error(f"TAK send failed: {e}, reconnecting...")
            self.tak_socket = self._connect_tak()
            try:
                self.tak_socket.sendall(cot_bytes)  # retry once after reconnect
            except Exception as e:
                log.error(f"TAK retry failed, packet dropped: {e}")

def load_config(path='/etc/telemtak/config.ini'):
    """Load configuration from ini file. Falls back to defaults if file not found."""
    cfg = configparser.ConfigParser()
    cfg.read(path)
    return cfg

if __name__ == '__main__':
    cfg = load_config()

    telem = TelemTAK(
        connection_str=cfg.get('mavlink', 'connection_str', fallback='udp:127.0.0.1:14551'),
        tak_host=cfg.get('tak', 'host', fallback='192.168.1.195'),
        tak_port=cfg.getint('tak', 'port', fallback=8088),
        uid=cfg.get('drone', 'uid', fallback='drone-001'),
        callsign=cfg.get('drone', 'callsign', fallback='VOXL-01'),
        stream_path=cfg.get('video', 'stream_path', fallback=None),
        video_user=cfg.get('video', 'username', fallback=None),
        video_pass=cfg.get('video', 'password', fallback=None)
    )

    def _handle_signal(sig, frame):
        telem.stop()

    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    telem.start()