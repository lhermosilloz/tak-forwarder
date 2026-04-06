#!/bin/bash
# telemTAK + videoTAK installer and config manager

set -e

INSTALL_DIR="/opt/telemtak"
CONFIG_DIR="/etc/telemtak"
CONFIG_FILE="$CONFIG_DIR/config.ini"
TELEM_SERVICE="/etc/systemd/system/telemtak.service"
VIDEO_SERVICE="/etc/systemd/system/videotak.service"

# --- Config wizard (shared between install and update) ---
run_wizard() {
    echo ""
    echo "--- MAVLink Configuration ---"
    read -p "MAVLink connection string [udp:127.0.0.1:14551]: " MAVLINK_STR
    MAVLINK_STR=${MAVLINK_STR:-"udp:127.0.0.1:14551"}

    echo ""
    echo "--- TAK Server Configuration ---"
    read -p "OpenTAKServer IP address: " TAK_HOST
    while [[ -z "$TAK_HOST" ]]; do
        echo "TAK server IP is required."
        read -p "OpenTAKServer IP address: " TAK_HOST
    done

    read -p "OpenTAKServer port [8088]: " TAK_PORT
    TAK_PORT=${TAK_PORT:-8088}

    echo ""
    echo "--- Drone Configuration ---"
    read -p "Drone UID [drone-001]: " DRONE_UID
    DRONE_UID=${DRONE_UID:-"drone-001"}

    read -p "Drone callsign [VOXL-01]: " CALLSIGN
    CALLSIGN=${CALLSIGN:-"VOXL-01"}

    echo ""
    echo "--- Video Configuration ---"
    read -p "Stream path (no slashes, e.g. starling001) [starling001]: " STREAM_PATH
    STREAM_PATH=${STREAM_PATH:-"starling001"}

    read -p "OTS username: " VIDEO_USER
    while [[ -z "$VIDEO_USER" ]]; do
        echo "OTS username is required."
        read -p "OTS username: " VIDEO_USER
    done

    read -sp "OTS password: " VIDEO_PASS
    echo ""
    while [[ -z "$VIDEO_PASS" ]]; do
        echo "OTS password is required."
        read -sp "OTS password: " VIDEO_PASS
        echo ""
    done
}

# --- Confirm summary ---
confirm_summary() {
    echo ""
    echo "============================================"
    echo "            Configuration Summary           "
    echo "============================================"
    echo "  MAVLink:      $MAVLINK_STR"
    echo "  TAK Host:     $TAK_HOST:$TAK_PORT"
    echo "  UID:          $DRONE_UID"
    echo "  Callsign:     $CALLSIGN"
    echo "  Stream Path:  $STREAM_PATH"
    echo "  OTS User:     $VIDEO_USER"
    echo "  OTS Password: ********"
    echo "============================================"
    read -p "Proceed? [y/N]: " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo "Cancelled."
        exit 0
    fi
}

# --- Write config ---
write_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
[mavlink]
connection_str = $MAVLINK_STR

[tak]
host = $TAK_HOST
port = $TAK_PORT

[drone]
uid = $DRONE_UID
callsign = $CALLSIGN

[video]
stream_path = $STREAM_PATH
username = $VIDEO_USER
password = $VIDEO_PASS
EOF
    echo "[+] Config written to $CONFIG_FILE"
}

# --- Install mode ---
do_install() {
    echo "============================================"
    echo "     telemTAK + videoTAK Installation       "
    echo "============================================"

    echo "[*] Checking dependencies..."
    if ! python3 -c "import pymavlink" &>/dev/null; then
        echo "[*] Installing pymavlink..."
        pip3 install pymavlink
    else
        echo "[+] pymavlink found"
    fi

    if ! command -v ffmpeg &>/dev/null; then
        echo "[*] Installing ffmpeg..."
        apt update && apt install -y ffmpeg
    else
        echo "[+] ffmpeg found"
    fi

    run_wizard
    confirm_summary
    write_config

    echo "[*] Installing telemTAK..."
    mkdir -p "$INSTALL_DIR"
    cp telemTAK.py "$INSTALL_DIR/telemTAK.py"
    chmod +x "$INSTALL_DIR/telemTAK.py"
    cp telemtak.service "$TELEM_SERVICE"

    echo "[*] Installing videoTAK..."
    cp videoTAK.sh /usr/local/bin/videoTAK.sh
    chmod +x /usr/local/bin/videoTAK.sh
    cp videotak.service "$VIDEO_SERVICE"

    systemctl daemon-reload
    systemctl enable telemtak videotak
    systemctl start telemtak videotak

    echo "[+] telemtak and videotak services installed and started"

    echo ""
    echo "============================================"
    echo "           Installation Complete!           "
    echo "============================================"
    echo ""
    echo "Useful commands:"
    echo "  systemctl status telemtak       # telemetry status"
    echo "  systemctl status videotak       # video status"
    echo "  journalctl -u telemtak -f       # telemetry live logs"
    echo "  journalctl -u videotak -f       # video live logs"
    echo "  systemctl restart telemtak      # restart telemetry"
    echo "  systemctl restart videotak      # restart video"
    echo "  sudo ./install.sh --config      # update config"
}

# --- Config update mode ---
do_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: No config found at $CONFIG_FILE. Run installer first."
        exit 1
    fi

    echo "============================================"
    echo "      telemTAK + videoTAK Config Update     "
    echo "============================================"
    echo ""
    echo "Current config:"
    echo "---"
    cat "$CONFIG_FILE"
    echo "---"
    echo ""
    echo "Press Enter to keep current value, or type a new one."

    CUR_MAVLINK=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('mavlink','connection_str'))")
    CUR_HOST=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('tak','host'))")
    CUR_PORT=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('tak','port'))")
    CUR_UID=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('drone','uid'))")
    CUR_CALLSIGN=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('drone','callsign'))")
    CUR_STREAM=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('video','stream_path'))")
    CUR_USER=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('video','username'))")

    echo ""
    read -p "MAVLink connection string [$CUR_MAVLINK]: " MAVLINK_STR
    MAVLINK_STR=${MAVLINK_STR:-$CUR_MAVLINK}

    read -p "TAK host [$CUR_HOST]: " TAK_HOST
    TAK_HOST=${TAK_HOST:-$CUR_HOST}

    read -p "TAK port [$CUR_PORT]: " TAK_PORT
    TAK_PORT=${TAK_PORT:-$CUR_PORT}

    read -p "Drone UID [$CUR_UID]: " DRONE_UID
    DRONE_UID=${DRONE_UID:-$CUR_UID}

    read -p "Callsign [$CUR_CALLSIGN]: " CALLSIGN
    CALLSIGN=${CALLSIGN:-$CUR_CALLSIGN}

    read -p "Stream path [$CUR_STREAM]: " STREAM_PATH
    STREAM_PATH=${STREAM_PATH:-$CUR_STREAM}

    read -p "OTS username [$CUR_USER]: " VIDEO_USER
    VIDEO_USER=${VIDEO_USER:-$CUR_USER}

    read -sp "OTS password (leave blank to keep current): " VIDEO_PASS
    echo ""
    if [[ -z "$VIDEO_PASS" ]]; then
        VIDEO_PASS=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('video','password'))")
    fi

    confirm_summary
    write_config

    echo "[*] Restarting services..."
    systemctl restart telemtak videotak
    echo "[+] Done. Both services restarted with new config."
}

# --- Help ---
do_help() {
    echo "Usage: sudo ./install.sh [OPTION]"
    echo ""
    echo "Options:"
    echo "  (none)      Fresh install — runs wizard, installs both services"
    echo "  --config    Update config and restart both services"
    echo "  --help      Show this help message"
}

# --- Entry point ---
case "$1" in
    --config)
        do_config
        ;;
    --help)
        do_help
        ;;
    *)
        do_install
        ;;
esac