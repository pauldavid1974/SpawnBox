#!/usr/bin/env bash
# ============================================================================
# SpawnBox v2.1.1 — Turn any PC into a Minecraft server with one command.
# https://github.com/pauldavid1974/spawnbox
#
# Author: Paul (pauldavid1974)
# AI Collaborator: Claude (Anthropic)
# License: MIT
# ============================================================================

set -uo pipefail
# Note: We do NOT use set -e. Errors are handled explicitly throughout.
# This avoids silent failures in subshells (especially the whiptail gauge).

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SPAWNBOX_VERSION="2.1.2"

# Crafty Docker image — change this line to pin a specific version
CRAFTY_IMAGE="registry.gitlab.com/crafty-controller/crafty-4:latest"

CRAFTY_DIR="/opt/crafty"
CRAFTY_SERVERS_DIR="${CRAFTY_DIR}/servers"
CRAFTY_CONFIG_DIR="${CRAFTY_DIR}/config"
CRAFTY_BACKUPS_DIR="${CRAFTY_DIR}/backups"
CRAFTY_LOGS_DIR="${CRAFTY_DIR}/logs"
CRAFTY_IMPORT_DIR="${CRAFTY_DIR}/import"
CRAFTY_CONTAINER="crafty"

COMPOSE_DIR="/opt/crafty-compose"

CRAFTY_PORT=8443
MC_JAVA_PORT=25565
MC_BEDROCK_PORT=19132
HARDENED_SSH_PORT=54321

LOG_FILE="/var/log/spawnbox-install.log"

# User choices (set by wizard)
WANT_SWAP="no"
WANT_SSH_HARDEN="no"
WANT_UFW="no"
WANT_FAIL2BAN="no"
WANT_TUNNEL="no"

# System state (set by preflight)
SYS_RAM_GB=0
SYS_DISK_FREE_GB=0
NEEDS_SWAP=false
HAS_SPACE=false
NEEDS_SEC=false
CURRENT_SSH_PORT=22

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
init_log() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    echo "=== SpawnBox v${SPAWNBOX_VERSION} — $(date) ===" >> "${LOG_FILE}"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_FILE}" 2>&1
}

# Run a command, logging stdout/stderr. Returns the command's exit code.
run_cmd() {
    "$@" >> "${LOG_FILE}" 2>&1
}

# ---------------------------------------------------------------------------
# Preflight Checks (silent — no UI yet)
# ---------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "SpawnBox must be run as root. Try: sudo bash spawnbox.sh"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo "Cannot detect your operating system."
        echo "SpawnBox requires Ubuntu, Debian, or Raspberry Pi OS."
        exit 1
    fi
    # shellcheck source=/dev/null
    source /etc/os-release
    log "Detected OS: ${PRETTY_NAME:-unknown} (${ID:-unknown})"

    case "${ID}" in
        ubuntu|debian|raspbian) ;;
        *)
            echo "Warning: SpawnBox is designed for Ubuntu/Debian. Detected: ${PRETTY_NAME:-unknown}"
            echo "Continuing anyway — things may not work as expected."
            sleep 3
            ;;
    esac
}

ensure_whiptail() {
    if ! command -v whiptail &>/dev/null; then
        echo "Installing UI components..."
        apt-get update -qq >> "${LOG_FILE}" 2>&1
        apt-get install -y -qq whiptail >> "${LOG_FILE}" 2>&1
        if ! command -v whiptail &>/dev/null; then
            echo "Could not install whiptail. Cannot continue."
            exit 1
        fi
    fi
}

check_internet() {
    log "Checking internet connectivity..."
    if curl -fsSL --max-time 10 -o /dev/null https://get.docker.com >> "${LOG_FILE}" 2>&1; then
        log "Internet connection confirmed"
    else
        whiptail --title "No Internet" --msgbox \
            "SpawnBox needs an internet connection to download software.\n\nPlease check your network and try again." 10 60
        exit 1
    fi
}

check_architecture() {
    local arch
    arch=$(uname -m)
    case "${arch}" in
        x86_64|amd64)  log "Architecture: amd64" ;;
        aarch64|arm64) log "Architecture: arm64" ;;
        armv7l|armhf)  log "Architecture: armv7" ;;
        *)
            whiptail --title "Unsupported Architecture" --msgbox \
                "SpawnBox supports amd64, arm64, and armv7.\n\nDetected: ${arch}" 10 60
            exit 1
            ;;
    esac
}

assess_system() {
    # RAM
    SYS_RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
    log "System RAM: ${SYS_RAM_GB} GB"
    if [[ "$SYS_RAM_GB" -lt 16 ]]; then
        NEEDS_SWAP=true
    fi

    # Disk
    SYS_DISK_FREE_GB=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    log "Free disk space: ${SYS_DISK_FREE_GB} GB"
    if [[ "$SYS_DISK_FREE_GB" -gt 10 ]]; then
        HAS_SPACE=true
    fi

    # SSH / Security posture
    if grep -q "^Port " /etc/ssh/sshd_config 2>/dev/null; then
        CURRENT_SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
    fi

    local ufw_active=false
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw_active=true
    fi

    if [[ "$CURRENT_SSH_PORT" -eq 22 ]] || [[ "$ufw_active" == false ]]; then
        NEEDS_SEC=true
    fi

    log "Current SSH port: ${CURRENT_SSH_PORT}, UFW active: ${ufw_active}, Needs security: ${NEEDS_SEC}"

    # Port conflicts — only check Crafty ports, and skip if Crafty itself is running
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CRAFTY_CONTAINER}$"; then
        log "Crafty is already running — skipping port conflict check"
    elif command -v ss &>/dev/null; then
        if ss -tuln | grep -qE ":(${CRAFTY_PORT}|${MC_JAVA_PORT})\b"; then
            whiptail --title "Port Conflict" --msgbox \
                "Another application is using port ${CRAFTY_PORT} or ${MC_JAVA_PORT}.\n\nPlease stop the conflicting application and try again." 12 60
            exit 1
        fi
    fi
}

# ---------------------------------------------------------------------------
# Wizard (whiptail)
# ---------------------------------------------------------------------------

# show_main_menu — ASCII art welcome screen with Install / Remove choice.
# ESC or Cancel exits immediately. "remove" calls do_uninstall then exits.
# "install" returns so the main flow continues.
show_main_menu() {
    local art
    art=$(cat <<'SPAWNBOX_ART'
      █████ ████   ███  █   █ █   █ ████   ███  █   █
      █     █   █ █   █ █   █ ██  █ █   █ █   █  █ █
      ████  ████  █████ █ █ █ █ █ █ ████  █   █   █
          █ █     █   █ ██ ██ █  ██ █   █ █   █  █ █
      █████ █     █   █ █   █ █   █ ████   ███  █   █
SPAWNBOX_ART
)
    local banner="

${art}
                           v${SPAWNBOX_VERSION}
               ──────────────────────────────
            Turn Any PC Into a Minecraft Server

                 What Would You Like to Do?"

    local choice rc=0
    choice=$(whiptail --title "SpawnBox" \
        --menu "${banner}" 26 66 2 \
        "Install SpawnBox"                    "" \
        "Remove SpawnBox (or its components)" "" \
        3>&1 1>&2 2>&3) || rc=$?

    # ESC (255) or Cancel (1) → clean exit
    if (( rc != 0 )); then
        clear
        echo "Goodbye."
        exit 0
    fi

    if [[ "$choice" == "Remove SpawnBox (or its components)" ]]; then
        do_uninstall
        exit 0
    fi
    # "install" — fall through; main flow continues
}

# wizard_or_exit — wrapper for whiptail calls inside run_wizard.
# ESC (exit code 255) exits the installer immediately.
# Cancel/No (exit code 1) returns 1 so the caller can skip that feature.
# OK/Yes (exit code 0) returns 0.
wizard_or_exit() {
    local rc=0
    "$@" || rc=$?
    if (( rc == 255 )); then
        clear
        echo "Installation cancelled."
        exit 0
    fi
    return $rc
}

run_wizard() {
    # Swap — only ask if needed and possible
    if [[ "$NEEDS_SWAP" == true ]] && [[ "$HAS_SPACE" == true ]]; then
        if wizard_or_exit whiptail --title "Memory" --yesno \
            "Your system has ${SYS_RAM_GB} GB of RAM (less than 16 GB).\n\nWould you like to add an 8 GB swap file to help prevent crashes?" 11 60; then
            WANT_SWAP="yes"
        fi
    fi

    # Security hardening — only ask if system looks unhardened.
    # Shows a checklist so the user can pick exactly what to apply (all ON by default).
    # Note: whiptail --checklist output requires fd-swap (3>&1 1>&2 2>&3), so ESC is
    # checked inline rather than via wizard_or_exit.
    if [[ "$NEEDS_SEC" == true ]]; then
        local sec_choices rc=0
        sec_choices=$(whiptail --title "Security Hardening" \
            --checklist "Your system is using default security settings.\n\nSelect the protections to apply (all recommended):" \
            17 64 3 \
            "ssh"      "Move SSH to port ${HARDENED_SSH_PORT}"  ON \
            "ufw"      "Enable UFW firewall with game ports"    ON \
            "fail2ban" "Fail2ban brute-force protection"        ON \
            3>&1 1>&2 2>&3) || rc=$?
        # ESC → exit installer; Cancel (1) with no selection → skip security entirely
        (( rc == 255 )) && { clear; echo "Installation cancelled."; exit 0; }
        [[ "$sec_choices" == *'"ssh"'*      ]] && WANT_SSH_HARDEN="yes"
        [[ "$sec_choices" == *'"ufw"'*      ]] && WANT_UFW="yes"
        [[ "$sec_choices" == *'"fail2ban"'* ]] && WANT_FAIL2BAN="yes"
    fi

    # Playit.gg
    if wizard_or_exit whiptail --title "External Access" --yesno \
        "Do you want friends outside your home network to be able to join?\n\nThis installs Playit.gg — a free tunnel service that avoids port forwarding." 11 60; then
        WANT_TUNNEL="yes"
    fi

    # Final confirmation
    local summary="SpawnBox will now install:\n\n"
    summary+="  • Docker\n"
    summary+="  • Crafty Controller (Minecraft server manager)"
    [[ "$WANT_SWAP" == "yes" ]] && summary+="\n  • 8 GB swap file"

    local any_sec="no"
    if [[ "$WANT_SSH_HARDEN" == "yes" ]] || [[ "$WANT_UFW" == "yes" ]] || \
        [[ "$WANT_FAIL2BAN" == "yes" ]]; then
        any_sec="yes"
    fi
    if [[ "$any_sec" == "yes" ]]; then
        summary+="\n  • Security hardening:"
        [[ "$WANT_SSH_HARDEN" == "yes" ]] && summary+="\n      - SSH moved to port ${HARDENED_SSH_PORT}"
        [[ "$WANT_UFW"        == "yes" ]] && summary+="\n      - UFW firewall enabled"
        [[ "$WANT_FAIL2BAN"   == "yes" ]] && summary+="\n      - Fail2ban brute-force protection"
    fi
    [[ "$WANT_TUNNEL" == "yes" ]] && summary+="\n  • Playit.gg tunnel"
    summary+="\n\nProceed?"

    if ! wizard_or_exit whiptail --title "Ready to Install" --yesno "${summary}" 20 64; then
        clear
        echo "Installation cancelled."
        exit 0
    fi

    # Log choices
    log "User choices: swap=${WANT_SWAP}, ssh_harden=${WANT_SSH_HARDEN}, ufw=${WANT_UFW}, fail2ban=${WANT_FAIL2BAN}, tunnel=${WANT_TUNNEL}"
}

# ---------------------------------------------------------------------------
# Install Functions
# ---------------------------------------------------------------------------

install_dependencies() {
    log "Installing system dependencies..."
    run_cmd apt-get update -qq || { log "apt-get update failed"; return 1; }

    local deps=(curl wget jq ca-certificates)
    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            run_cmd apt-get install -y -qq "${dep}" || { log "Failed to install ${dep}"; return 1; }
        fi
    done
    log "Dependencies ready"
}

do_swap() {
    log "Setting up swap file..."

    # Check for existing /swapfile specifically (not just any swap)
    if [[ -f /swapfile ]]; then
        log "Swap file /swapfile already exists — skipping"
        return 0
    fi

    fallocate -l 8G /swapfile >> "${LOG_FILE}" 2>&1 || { log "fallocate failed"; return 1; }
    chmod 600 /swapfile
    run_cmd mkswap /swapfile || { log "mkswap failed"; return 1; }
    run_cmd swapon /swapfile || { log "swapon failed"; return 1; }

    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    log "8 GB swap file created and enabled"
}

do_docker() {
    log "Installing Docker..."

    if command -v docker &>/dev/null; then
        log "Docker is already installed"
        return 0
    fi

    curl -fsSL https://get.docker.com | bash >> "${LOG_FILE}" 2>&1 || { log "Docker install failed"; return 1; }
    run_cmd systemctl enable --now docker || { log "Failed to start Docker"; return 1; }
    log "Docker installed and running"
}

do_crafty() {
    log "Deploying Crafty Controller..."

    # If Crafty is already running, skip
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CRAFTY_CONTAINER}$"; then
        log "Crafty is already running — skipping"
        return 0
    fi

    # Remove stale stopped container if present
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CRAFTY_CONTAINER}$"; then
        log "Removing stale Crafty container..."
        docker rm -f "${CRAFTY_CONTAINER}" >> "${LOG_FILE}" 2>&1 || true
    fi

    # Create directories
    mkdir -p "${CRAFTY_SERVERS_DIR}" "${CRAFTY_CONFIG_DIR}" \
             "${CRAFTY_BACKUPS_DIR}" "${CRAFTY_LOGS_DIR}" "${CRAFTY_IMPORT_DIR}"
    chmod -R 775 "${CRAFTY_DIR}"
    chgrp -R root "${CRAFTY_DIR}"

    # Write docker-compose.yml
    mkdir -p "${COMPOSE_DIR}"
    local tz
    tz=$(cat /etc/timezone 2>/dev/null || echo 'Etc/UTC')

    cat > "${COMPOSE_DIR}/docker-compose.yml" <<COMPOSEFILE
name: crafty

services:
  crafty:
    image: ${CRAFTY_IMAGE}
    container_name: ${CRAFTY_CONTAINER}
    restart: unless-stopped
    environment:
      TZ: "${tz}"
    ports:
      - "${CRAFTY_PORT}:8443"       # Crafty web UI (HTTPS)
      - "8123:8123"                  # Crafty websocket
      - "${MC_JAVA_PORT}:25565"      # Minecraft Java
      - "25566:25566"                # Extra server slots
      - "25567:25567"
      - "25568:25568"
      - "25569:25569"
      - "25570:25570"
      - "${MC_BEDROCK_PORT}:19132/udp"  # Minecraft Bedrock
    volumes:
      - ${CRAFTY_BACKUPS_DIR}:/crafty/backups
      - ${CRAFTY_LOGS_DIR}:/crafty/logs
      - ${CRAFTY_SERVERS_DIR}:/crafty/servers
      - ${CRAFTY_CONFIG_DIR}:/crafty/app/config
      - ${CRAFTY_IMPORT_DIR}:/crafty/import
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "5"
COMPOSEFILE

    log "docker-compose.yml written to ${COMPOSE_DIR}"

    # Pull and start
    docker compose -f "${COMPOSE_DIR}/docker-compose.yml" up -d >> "${LOG_FILE}" 2>&1 \
        || { log "docker compose up failed"; return 1; }

    # Wait for Crafty to respond (retry loop, not blind sleep)
    log "Waiting for Crafty to initialize..."
    local retries=40
    while [[ ${retries} -gt 0 ]]; do
        if curl -fsSk --max-time 5 "https://localhost:${CRAFTY_PORT}" &>/dev/null; then
            log "Crafty Controller is responding"
            return 0
        fi
        sleep 3
        retries=$((retries - 1))
    done

    # Not fatal — it may still be starting on slow hardware
    log "Crafty not yet responding after 2 minutes (may still be initializing)"
    return 0
}

do_ssh_harden() {
    log "Hardening SSH port..."
    if grep -q "^Port ${HARDENED_SSH_PORT}" /etc/ssh/sshd_config 2>/dev/null; then
        log "SSH already on port ${HARDENED_SSH_PORT} — skipping SSH config"
        return 0
    fi

    # Backup SSH config before touching it
    run_cmd cp /etc/ssh/sshd_config \
        "/etc/ssh/sshd_config.spawnbox.bak.$(date +%Y%m%d-%H%M%S)"

    sed -i '/^Port /d' /etc/ssh/sshd_config
    sed -i '/^#Port /d' /etc/ssh/sshd_config
    echo "Port ${HARDENED_SSH_PORT}" >> /etc/ssh/sshd_config

    # Handle Ubuntu 22.10+ ssh.socket issue
    if systemctl list-unit-files 2>/dev/null | grep -q "ssh.socket"; then
        run_cmd systemctl disable --now ssh.socket 2>/dev/null || true
        run_cmd rm -rf /etc/systemd/system/ssh.socket.d 2>/dev/null || true
        run_cmd systemctl daemon-reload
    fi
    run_cmd systemctl unmask ssh.service
    run_cmd systemctl enable --now ssh.service
    run_cmd systemctl restart ssh
    log "SSH port set to ${HARDENED_SSH_PORT}"
}

do_fail2ban() {
    log "Installing Fail2ban..."

    # Protect whichever SSH port is actually active after this install
    local active_ssh_port
    if [[ "$WANT_SSH_HARDEN" == "yes" ]]; then
        active_ssh_port="${HARDENED_SSH_PORT}"
    else
        active_ssh_port="${CURRENT_SSH_PORT}"
    fi

    if command -v fail2ban-server &>/dev/null \
        && grep -q "port = ${active_ssh_port}" /etc/fail2ban/jail.local 2>/dev/null; then
        log "Fail2ban already installed and configured — skipping"
        return 0
    fi

    run_cmd apt-get update -qq
    run_cmd apt-get install -y -qq fail2ban \
        || { log "Failed to install fail2ban"; return 1; }

    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1d
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ${active_ssh_port}
EOF

    run_cmd systemctl enable --now fail2ban
    run_cmd systemctl restart fail2ban
    log "Fail2ban installed and configured (protecting SSH on port ${active_ssh_port})"
}

do_ufw() {
    log "Configuring UFW firewall..."

    # Use the port SSH is actually listening on to avoid locking the user out
    local active_ssh_port
    if [[ "$WANT_SSH_HARDEN" == "yes" ]]; then
        active_ssh_port="${HARDENED_SSH_PORT}"
    else
        active_ssh_port="${CURRENT_SSH_PORT}"
    fi

    if ! command -v ufw &>/dev/null; then
        run_cmd apt-get update -qq
        run_cmd apt-get install -y -qq ufw \
            || { log "Failed to install ufw"; return 1; }
    fi

    run_cmd ufw default deny incoming
    run_cmd ufw default allow outgoing

    local -A ufw_rules=(
        ["${active_ssh_port}/tcp"]="SSH"
        ["${CRAFTY_PORT}/tcp"]="Crafty web UI"
        ["8123/tcp"]="Crafty websocket"
        ["${MC_JAVA_PORT}/tcp"]="Minecraft Java"
        ["25566:25570/tcp"]="Extra server slots"
        ["${MC_BEDROCK_PORT}/udp"]="Minecraft Bedrock"
    )
    for rule in "${!ufw_rules[@]}"; do
        if ufw status 2>/dev/null | grep -qF "${rule%/*}"; then
            log "UFW rule already exists for ${ufw_rules[$rule]} (${rule}) — skipping"
        else
            run_cmd ufw allow ${rule}
            log "UFW rule added: ${rule} (${ufw_rules[$rule]})"
        fi
    done

    run_cmd ufw --force enable
    log "UFW enabled (SSH allowed on port ${active_ssh_port})"
}

do_security() {
    log "Applying security hardening..."
    [[ "$WANT_SSH_HARDEN" == "yes" ]] && { do_ssh_harden  || return 1; }
    [[ "$WANT_FAIL2BAN"   == "yes" ]] && { do_fail2ban    || return 1; }
    [[ "$WANT_UFW"        == "yes" ]] && { do_ufw         || return 1; }
    log "Security hardening complete"
}

do_tunnel() {
    log "Installing Playit.gg..."

    if command -v playit &>/dev/null; then
        log "Playit.gg is already installed"
        return 0
    fi

    run_cmd apt-get install -y -qq gnupg \
        || { log "Failed to install gnupg"; return 1; }

    curl -SsL https://playit-cloud.github.io/ppa/key.gpg \
        | gpg --dearmor \
        | tee /etc/apt/trusted.gpg.d/playit.gpg >/dev/null 2>> "${LOG_FILE}"

    echo "deb [signed-by=/etc/apt/trusted.gpg.d/playit.gpg] https://playit-cloud.github.io/ppa/data ./" \
        | tee /etc/apt/sources.list.d/playit-cloud.list >/dev/null

    run_cmd apt-get update -qq
    run_cmd apt-get install -y -qq playit \
        || { log "Failed to install playit"; return 1; }

    # Don't auto-start — user needs to run 'playit setup' interactively
    run_cmd systemctl disable --now playit 2>/dev/null || true
    log "Playit.gg installed (user must run 'playit setup' to configure)"
}

# ---------------------------------------------------------------------------
# Health Check
# ---------------------------------------------------------------------------
health_check() {
    local all_ok=true

    # Docker
    if docker info &>/dev/null 2>&1; then
        log "Health check: Docker OK"
    else
        log "Health check: Docker FAILED"
        all_ok=false
    fi

    # Crafty
    if curl -fsSk --max-time 5 "https://localhost:${CRAFTY_PORT}" &>/dev/null; then
        log "Health check: Crafty OK"
    else
        log "Health check: Crafty not responding (may still be starting)"
        all_ok=false
    fi

    if [[ "$all_ok" == false ]]; then
        log "Health check: some components not ready"
    fi
}

# ---------------------------------------------------------------------------
# Completion Screen
# ---------------------------------------------------------------------------
show_completion() {
    local ip_address
    ip_address=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "${ip_address}" ]]; then
        ip_address="<your-server-ip>"
    fi

    # Try to read Crafty default credentials
    local crafty_creds_file="${CRAFTY_CONFIG_DIR}/default-creds.txt"
    local crafty_user="(check ${crafty_creds_file})"
    local crafty_pass="(check ${crafty_creds_file})"
    if [[ -f "${crafty_creds_file}" ]]; then
        local u p
        u=$(jq -r '.username // empty' "${crafty_creds_file}" 2>/dev/null)
        p=$(jq -r '.password // empty' "${crafty_creds_file}" 2>/dev/null)
        [[ -n "$u" ]] && crafty_user="$u"
        [[ -n "$p" ]] && crafty_pass="$p"
    fi

    clear
    echo ""
    echo "========================================================"
    echo "  SpawnBox setup complete!"
    echo "========================================================"
    echo ""
    echo "  Crafty Controller:  https://${ip_address}:${CRAFTY_PORT}"
    echo ""
    echo "  Login credentials:"
    echo "    Username: ${crafty_user}"
    echo "    Password: ${crafty_pass}"
    echo ""
    echo "  Change your password after the first login!"
    echo ""

    if [[ "$WANT_SSH_HARDEN" == "yes" ]]; then
        echo "  --------------------------------------------------------"
        echo "  SSH port changed to ${HARDENED_SSH_PORT}"
        echo "  Next time connect with: ssh -p ${HARDENED_SSH_PORT} user@${ip_address}"
        echo "  --------------------------------------------------------"
        echo ""
    fi

    if [[ "$WANT_UFW" == "yes" ]]; then
        echo "  UFW firewall is active. Game ports are open."
        echo ""
    fi

    if [[ "$WANT_FAIL2BAN" == "yes" ]]; then
        echo "  Fail2ban is running (SSH brute-force protection active)."
        echo ""
    fi

    if [[ "$WANT_TUNNEL" == "yes" ]]; then
        echo "  --------------------------------------------------------"
        echo "  Playit.gg is installed but needs setup."
        echo "  Run:  playit setup"
        echo "  --------------------------------------------------------"
        echo ""
    fi

    echo "  Install log: ${LOG_FILE}"
    echo ""
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
do_uninstall() {
    check_root
    init_log
    ensure_whiptail

    whiptail --title "SpawnBox Uninstaller" --msgbox \
        "This will remove Crafty Controller and its Docker container.\n\nDocker itself will NOT be removed." 10 60 || true

    # Ask about data
    local keep_data="yes"
    if whiptail --title "Keep Your Data?" --yesno \
        "Do you want to KEEP your Minecraft worlds and backups?\n\n• Yes = remove Crafty but keep your server files\n• No  = remove everything including all world data" 12 60; then
        keep_data="yes"
    else
        keep_data="no"
    fi

    # Final confirmation for destructive action
    if [[ "$keep_data" == "no" ]]; then
        if ! whiptail --title "Are You Sure?" --yesno \
            "This will permanently delete ALL your Minecraft worlds, backups, and server files.\n\nThis cannot be undone. Proceed?" 11 60; then
            echo "Uninstall cancelled."
            exit 0
        fi
    fi

    log "=== SpawnBox Uninstall Started (keep_data=${keep_data}) ==="

    # Stop and remove Crafty
    echo "Stopping Crafty Controller..."
    if [[ -f "${COMPOSE_DIR}/docker-compose.yml" ]]; then
        docker compose -f "${COMPOSE_DIR}/docker-compose.yml" down >> "${LOG_FILE}" 2>&1 || true
    else
        docker stop "${CRAFTY_CONTAINER}" >> "${LOG_FILE}" 2>&1 || true
        docker rm "${CRAFTY_CONTAINER}" >> "${LOG_FILE}" 2>&1 || true
    fi
    echo "  Crafty Controller removed."

    if [[ "$keep_data" == "no" ]]; then
        echo "Removing all server data..."
        rm -rf "${CRAFTY_DIR}"
        rm -rf "${COMPOSE_DIR}"
        echo "  All data removed."
    else
        echo "  Your worlds and backups have been kept at:"
        echo "    ${CRAFTY_SERVERS_DIR}"
        echo "    ${CRAFTY_BACKUPS_DIR}"
    fi

    # Remove compose dir (but not data dir if keeping)
    [[ "$keep_data" == "yes" ]] && rm -rf "${COMPOSE_DIR}" 2>/dev/null || true

    # Playit.gg
    if command -v playit &>/dev/null; then
        echo "Removing Playit.gg..."
        systemctl stop playit 2>/dev/null || true
        apt-get remove -y playit >> "${LOG_FILE}" 2>&1 || true
        rm -f /etc/apt/sources.list.d/playit-cloud.list \
              /etc/apt/trusted.gpg.d/playit.gpg 2>/dev/null || true
        echo "  Playit.gg removed."
    fi

    # Revert security hardening
    local backup
    backup=$(ls /etc/ssh/sshd_config.spawnbox.bak.* 2>/dev/null | head -n1)
    if [[ -n "$backup" ]]; then
        if whiptail --title "Revert Security?" --yesno \
            "A backup of your original SSH config was found.\n\nRestore it and revert firewall rules?" 10 60; then
            cp "$backup" /etc/ssh/sshd_config
            # Read original port from restored config (default 22 if not set)
            local original_ssh_port
            original_ssh_port=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
            original_ssh_port="${original_ssh_port:-22}"
            # CRITICAL: allow original port BEFORE removing hardened port — avoids lockout
            ufw allow "${original_ssh_port}/tcp" 2>/dev/null || true
            ufw --force reload 2>/dev/null || true
            # Now safe to remove the hardened port rule
            ufw delete allow "${HARDENED_SSH_PORT}/tcp" 2>/dev/null || true
            systemctl restart ssh 2>/dev/null || true
            ufw --force reload 2>/dev/null || true
            echo "  SSH config restored from backup (SSH now on port ${original_ssh_port})."
        fi
    fi

    # Clean up fail2ban config
    rm -f /etc/fail2ban/jail.local 2>/dev/null || true
    systemctl restart fail2ban 2>/dev/null || true

    # Remove remaining UFW rules added by SpawnBox
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        for rule in "${CRAFTY_PORT}/tcp" "8123/tcp" "${MC_JAVA_PORT}/tcp" \
                    "25566:25570/tcp" "${MC_BEDROCK_PORT}/udp"; do
            ufw delete allow ${rule} >> "${LOG_FILE}" 2>&1 || true
        done
        ufw --force reload >> "${LOG_FILE}" 2>&1 || true
        log "Removed SpawnBox UFW rules"
        echo "  Firewall rules removed."
    fi

    # Remove swap file if SpawnBox created it
    if [[ -f /swapfile ]]; then
        if whiptail --title "Remove Swap File?" --yesno \
            "An 8 GB swap file exists at /swapfile.\n\nRemove it and free the disk space?" 10 60; then
            swapoff /swapfile 2>/dev/null || true
            rm -f /swapfile
            sed -i '/\/swapfile/d' /etc/fstab
            log "Swap file removed"
            echo "  Swap file removed."
        fi
    fi

    # Remove Docker
    if command -v docker &>/dev/null; then
        if whiptail --title "Remove Docker?" --yesno \
            "Docker is still installed.\n\nRemove Docker and all its components?" 10 60; then
            run_cmd apt-get remove -y docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
            run_cmd apt-get autoremove -y
            rm -rf /var/lib/docker /etc/docker >> "${LOG_FILE}" 2>&1 || true
            log "Docker removed"
            echo "  Docker removed."
        fi
    fi

    # Remove install log
    if [[ -f "${LOG_FILE}" ]]; then
        if whiptail --title "Remove Log File?" --yesno \
            "Remove the SpawnBox install log at ${LOG_FILE}?" 9 60; then
            rm -f "${LOG_FILE}"
        fi
    fi

    echo ""
    echo "SpawnBox has been uninstalled."
    echo ""

    log "=== SpawnBox Uninstall Complete ==="
}

# ---------------------------------------------------------------------------
# Main Install Flow (called from gauge)
# ---------------------------------------------------------------------------
do_install() {
    # This runs inside the gauge subshell.
    # We use a status file to signal success/failure to the parent.
    local status_file="/tmp/spawnbox-install-status"
    echo "running" > "$status_file"

    echo "5"
    echo "XXX"; echo "Installing system dependencies..."; echo "XXX"
    if ! install_dependencies; then
        echo "FAILED: dependencies" > "$status_file"
        return 1
    fi

    if [[ "$WANT_SWAP" == "yes" ]]; then
        echo "15"
        echo "XXX"; echo "Creating 8 GB swap file..."; echo "XXX"
        if ! do_swap; then
            echo "FAILED: swap" > "$status_file"
            return 1
        fi
    fi

    echo "25"
    echo "XXX"; echo "Installing Docker..."; echo "XXX"
    if ! do_docker; then
        echo "FAILED: docker" > "$status_file"
        return 1
    fi

    echo "55"
    echo "XXX"; echo "Deploying Crafty Controller..."; echo "XXX"
    if ! do_crafty; then
        echo "FAILED: crafty" > "$status_file"
        return 1
    fi

    if [[ "$WANT_SSH_HARDEN" == "yes" ]] || [[ "$WANT_UFW" == "yes" ]] || [[ "$WANT_FAIL2BAN" == "yes" ]]; then
        echo "75"
        echo "XXX"; echo "Applying security hardening..."; echo "XXX"
        if ! do_security; then
            echo "FAILED: security" > "$status_file"
            return 1
        fi
    fi

    if [[ "$WANT_TUNNEL" == "yes" ]]; then
        echo "90"
        echo "XXX"; echo "Installing Playit.gg..."; echo "XXX"
        if ! do_tunnel; then
            echo "FAILED: tunnel" > "$status_file"
            return 1
        fi
    fi

    echo "95"
    echo "XXX"; echo "Running health check..."; echo "XXX"
    health_check

    echo "100"
    echo "XXX"; echo "Done!"; echo "XXX"
    sleep 1

    echo "ok" > "$status_file"
}

# ---------------------------------------------------------------------------
# Minecraft Theme
# ---------------------------------------------------------------------------
setup_minecraft_theme() {
    export NEWT_COLORS="root=green,black
border=yellow,black
window=green,black
shadow=black,black
title=yellow,black
button=black,yellow
actbutton=black,white
compactbutton=green,black
textbox=green,black
acttextbox=green,black
entry=black,yellow
disentry=green,black
checkbox=green,black
actcheckbox=black,yellow
error=white,red
label=green,black
listbox=green,black
actlistbox=black,yellow
sellistbox=black,yellow
actsellistbox=black,yellow
gauge=black,yellow
emptygauge=green,black
"
}

draw_progress_screen() {
    local pct="${1:-0}"
    local action="${2:-Initializing...}"

    local cols rows
    cols=$(tput cols 2>/dev/null || echo 72)
    rows=$(tput lines 2>/dev/null || echo 24)

    # Box inner width (content between the two ║ chars)
    local inner=58
    (( cols < inner + 4 )) && inner=$(( cols - 4 ))
    (( inner < 20 )) && inner=20

    # Bar width: "║ [bar] NNN% ║" uses inner = 1+1+bar_w+1+1+3+1+1 = bar_w+9
    local bar_w=$(( inner - 9 ))
    (( bar_w < 5 )) && bar_w=5

    local filled=$(( pct * bar_w / 100 ))
    local empty=$(( bar_w - filled ))

    # ANSI color codes
    local RST='\e[0m'
    local BG='\e[40m'       # black background
    local FG='\e[32m'       # green foreground
    local YEL='\e[1;33m'   # bold yellow
    local WHT='\e[1;97m'   # bright white

    # Build progress bar strings
    local bar_f="" bar_e="" i
    for (( i=0; i<filled; i++ )); do bar_f+="█"; done
    for (( i=0; i<empty; i++ ));  do bar_e+="░"; done

    # Horizontal border line (═ × inner)
    local hborder=""
    for (( i=0; i<inner; i++ )); do hborder+="═"; done

    # Horizontal centering (box is inner+2 wide including ║ chars)
    local lpad=$(( (cols - inner - 2) / 2 ))
    (( lpad < 0 )) && lpad=0
    local L=""; for (( i=0; i<lpad; i++ )); do L+=" "; done

    # Vertical centering: box is 9 rows tall, place at ~1/3 from top
    local vpad=$(( (rows - 9) / 3 ))
    (( vpad < 0 )) && vpad=0

    # Truncate strings that would overflow the box
    local title="  SpawnBox v${SPAWNBOX_VERSION}  -  Minecraft Server Setup"
    (( ${#title} > inner )) && title="${title:0:$inner}"

    local max_a=$(( inner - 3 ))   # " > " is 3 chars prefix, leaving inner-3 for action + padding
    (( ${#action} > max_a )) && action="${action:0:$max_a}"

    # Paint screen: set black bg, clear, home cursor
    printf '\e[40m\e[2J\e[H'
    tput civis 2>/dev/null
    tput cup "$vpad" 0

    #  ╔══════════════════════════╗
    printf "${BG}${YEL}${L}╔${hborder}╗\n"
    #  ║  SpawnBox v2.1.0  - ...  ║
    printf "${BG}${YEL}${L}║${WHT}%-*s${YEL}║\n" "$inner" "$title"
    #  ╠══════════════════════════╣
    printf "${BG}${YEL}${L}╠${hborder}╣\n"
    #  ║                          ║
    printf "${BG}${YEL}${L}║%*s║\n" "$inner" ""
    #  ║ [████████░░░░░░] NNN%  ║
    printf "${BG}${YEL}${L}║ [${YEL}%s${FG}%s${YEL}] %3d%% ║\n" "$bar_f" "$bar_e" "$pct"
    #  ║                          ║
    printf "${BG}${YEL}${L}║%*s║\n" "$inner" ""
    #  ║ > Installing Docker...   ║
    printf "${BG}${YEL}${L}║ ${WHT}> %-*s${YEL}║\n" $(( inner - 3 )) "$action"
    #  ╚══════════════════════════╝
    printf "${BG}${YEL}${L}╚${hborder}╝\n"
    printf "${RST}"
}

run_install_with_gauge() {
    local status_file="/tmp/spawnbox-install-status"
    rm -f "$status_file"

    # Restore terminal on interrupt or normal exit
    trap 'tput cnorm 2>/dev/null; printf "\e[0m"; clear' EXIT
    trap 'tput cnorm 2>/dev/null; printf "\e[0m"; clear; exit 130' INT TERM

    draw_progress_screen 0 "Starting..."

    # Parse the gauge-protocol stream from do_install and render live
    local cur_pct=0 cur_action="Starting..." in_msg=0
    while IFS= read -r line; do
        if [[ "$line" == "XXX" ]]; then
            (( in_msg = 1 - in_msg )) || true
        elif [[ "$line" =~ ^[0-9]+$ ]] && (( in_msg == 0 )); then
            cur_pct="$line"
        elif (( in_msg == 1 )) && [[ -n "$line" ]]; then
            cur_action="$line"
            draw_progress_screen "$cur_pct" "$cur_action"
        fi
    done < <(do_install)

    trap - EXIT INT TERM
    tput cnorm 2>/dev/null
    printf '\e[0m'
    clear

    local result
    result=$(cat "$status_file" 2>/dev/null || echo "unknown")
    rm -f "$status_file"

    if [[ "$result" == "ok" ]]; then
        return 0
    elif [[ "$result" == "running" ]]; then
        echo "Installation failed unexpectedly. Check the log: ${LOG_FILE}"
        exit 1
    else
        echo "Installation failed: ${result}. Check the log: ${LOG_FILE}"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------
case "${1:-}" in
    --uninstall)
        do_uninstall
        ;;
    --version|-v)
        echo "SpawnBox v${SPAWNBOX_VERSION}"
        ;;
    --help|-h)
        echo "SpawnBox v${SPAWNBOX_VERSION}"
        echo ""
        echo "Usage:"
        echo "  sudo bash spawnbox.sh             Install SpawnBox"
        echo "  sudo bash spawnbox.sh --uninstall  Remove SpawnBox"
        echo "  bash spawnbox.sh --version         Show version"
        echo "  bash spawnbox.sh --help            Show this help"
        echo ""
        echo "More info: https://github.com/pauldavid1974/spawnbox"
        ;;
    *)
        check_root
        init_log
        check_os
        ensure_whiptail
        setup_minecraft_theme
        show_main_menu
        check_architecture
        check_internet
        assess_system
        run_wizard
        run_install_with_gauge
        show_completion
        log "=== SpawnBox installation completed at $(date) ==="
        ;;
esac
