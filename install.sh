#!/bin/bash
# telemTAK installer and config manager

set -e

INSTALL_DIR="/opt/telemtak"
CONFIG_DIR="/etc/telemtak"
CONFIG_FILE="$CONFIG_DIR/config.ini"
SERVICE_FILE="/etc/systemd/system/telemtak.service"

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
}

# --- Confirm summary ---
confirm_summary() {
    echo ""
    echo "============================================"
    echo "            Configuration Summary           "
    echo "============================================"
    echo "  MAVLink:   $MAVLINK_STR"
    echo "  TAK Host:  $TAK_HOST:$TAK_PORT"
    echo "  UID:       $DRONE_UID"
    echo "  Callsign:  $CALLSIGN"
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
EOF
    echo "[+] Config written to $CONFIG_FILE"
}

# --- Install mode ---
do_install() {
    echo "============================================"
    echo "         telemTAK Installation Wizard       "
    echo "============================================"

    echo "[*] Checking dependencies..."
    if ! python3 -c "import pymavlink" &>/dev/null; then
        echo "[*] Installing pymavlink..."
        pip3 install pymavlink
    else
        echo "[+] pymavlink found"
    fi

    run_wizard
    confirm_summary
    write_config

    echo "[*] Installing telemTAK..."
    mkdir -p "$INSTALL_DIR"
    cp telemTAK.py "$INSTALL_DIR/telemTAK.py"
    chmod +x "$INSTALL_DIR/telemTAK.py"

    cp telemtak.service "$SERVICE_FILE"
    systemctl daemon-reload
    systemctl enable telemtak
    systemctl start telemtak
    echo "[+] telemtak service installed and started"

    echo ""
    echo "============================================"
    echo "         Installation Complete!             "
    echo "============================================"
    echo ""
    echo "Useful commands:"
    echo "  systemctl status telemtak     # check status"
    echo "  journalctl -u telemtak -f     # live logs"
    echo "  systemctl restart telemtak    # restart service"
    echo "  systemctl stop telemtak       # stop service"
    echo "  sudo ./install.sh --config    # update config"
}

# --- Config update mode ---
do_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: No config found at $CONFIG_FILE. Run installer first."
        exit 1
    fi

    echo "============================================"
    echo "         telemTAK Config Update             "
    echo "============================================"
    echo ""
    echo "Current config:"
    echo "---"
    cat "$CONFIG_FILE"
    echo "---"
    echo ""
    echo "Press Enter to keep current value, or type a new one."

    # Read current values as defaults
    CUR_MAVLINK=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('mavlink','connection_str'))")
    CUR_HOST=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('tak','host'))")
    CUR_PORT=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('tak','port'))")
    CUR_UID=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('drone','uid'))")
    CUR_CALLSIGN=$(python3 -c "import configparser; c=configparser.ConfigParser(); c.read('$CONFIG_FILE'); print(c.get('drone','callsign'))")

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

    confirm_summary
    write_config

    echo "[*] Restarting telemtak service..."
    systemctl restart telemtak
    echo "[+] Done. Service restarted with new config."
}

# --- Help ---
do_help() {
    echo "Usage: sudo ./install.sh [OPTION]"
    echo ""
    echo "Options:"
    echo "  (none)      Fresh install — runs wizard, installs service"
    echo "  --config    Update config and restart service"
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