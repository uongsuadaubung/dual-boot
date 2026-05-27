#!/bin/bash
# ============================================================
#  Debian 13 Trixie — Setup for Intel 12500H
#  Run with: sudo bash setup-debian.sh
# ============================================================

set -e  # stop on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
section() { echo -e "\n${GREEN}========== $1 ==========${NC}"; }

ask_choice() {
  local prompt="$1"
  local choice
  read -p "$prompt (y/n): " choice
  if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
    return 0
  else
    return 1
  fi
}

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
  error "Please run with sudo: sudo bash $0"
  exit 1
fi

# ============================================================
# STEP 1: Add non-free repository (needed for firmware)
# ============================================================
section "STEP 1: Add non-free repository"

if ask_choice "Do you want to add the non-free repository (needed for firmware)?"; then
  info "Updating sources.list to include contrib and non-free..."
  cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-backports main contrib non-free non-free-firmware
EOF

  apt update
  info "Done."
else
  info "Skipped STEP 1."
fi

# ============================================================
# STEP 2: Install required firmware
# ============================================================
section "STEP 2: Install required firmware"

if ask_choice "Do you want to install the required firmware for Intel + other devices?"; then
  info "Installing firmware for Intel + other devices..."
  apt install -y \
    firmware-linux \
    firmware-linux-nonfree \
    firmware-misc-nonfree \
    firmware-sof-signed \
    intel-microcode

  info "Done."
else
  info "Skipped STEP 2."
fi

# ============================================================
# STEP 3: Install tuned + tuned-ppd (Power profile management)
# ============================================================
section "STEP 3: Install tuned"

if ask_choice "Do you want to install and configure tuned (power profile management)?"; then
  # Remove power-profiles-daemon if present (to avoid conflict)
  if dpkg -l | grep -q "^ii.*power-profiles-daemon"; then
    info "power-profiles-daemon detected, removing it..."
    apt remove -y power-profiles-daemon
  fi

  info "Installing tuned and tuned-ppd..."
  apt install -y tuned tuned-ppd

  info "Enabling and starting tuned service..."
  systemctl enable --now tuned

  info "Setting default profile: balanced..."
  tuned-adm profile balanced

  info "Done. Active profile: $(tuned-adm active)"
else
  info "Skipped STEP 3."
fi

# ============================================================
# STEP 4: Install Distrobox + Podman
# ============================================================
section "STEP 4: Install Distrobox"

if ask_choice "Do you want to install Distrobox + Podman?"; then
  info "Installing podman (backend for distrobox)..."
  apt install -y podman

  info "Installing distrobox..."
  apt install -y distrobox

  info "Done."
else
  info "Skipped STEP 4."
fi

# ============================================================
# STEP 5: Install ibus-unikey (Vietnamese Keyboard)
# ============================================================
section "STEP 5: Install ibus-unikey"

if ask_choice "Do you want to install ibus-unikey?"; then
  info "Installing ibus and ibus-unikey..."
  apt install -y ibus ibus-unikey

  info "Done."
else
  info "Skipped STEP 5."
fi
warn "After reboot: run 'im-config' and select IBus as default input method."
warn "Then run 'ibus-setup', go to Input Method -> Add -> Vietnamese -> Unikey."

# ============================================================
# STEP 6: Install zram-tools (Compressed Swap in RAM)
# ============================================================
section "STEP 6: Install zram-tools"

if ask_choice "Do you want to install and configure zram-tools?"; then
  info "Installing zram-tools to optimize RAM..."
  apt install -y zram-tools

  info "Configuring zram-tools (zstd algorithm, 60% of RAM)..."
  cat > /etc/default/zram-tools << 'EOF'
# Optimized zram configuration
CORES=default
ALGO=zstd
PERCENT=60
PRIORITY=100
EOF

  info "Enable and start zram-tools service..."
  systemctl enable zram-tools.service || true
  systemctl restart zram-tools.service || true

  info "Done. Compressed zram swap (60% of RAM) will take full effect after reboot."
else
  info "Skipped STEP 6."
fi

# ============================================================
# STEP 7: Install Flatpak + Flathub (for GNOME Software)
# ============================================================
section "STEP 7: Install Flatpak"

if ask_choice "Do you want to install Flatpak + GNOME Software?"; then
  info "Installing Flatpak, GNOME Software, and Flatpak plugin..."
  apt install -y flatpak gnome-software gnome-software-plugin-flatpak

  info "Adding Flathub repository..."
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  info "Done. A reboot is required for GNOME Software to show Flatpak apps."
else
  info "Skipped STEP 7."
fi

# ============================================================
# [OPTIONAL] Bluetooth — uncomment if needed
# ============================================================
# section "Install Bluetooth"
# apt install -y bluetooth bluez bluez-firmware blueman libspa-0.2-bluetooth
# systemctl enable bluetooth
# info "Done."

# ============================================================
# STEP 8: Configure Dual Boot (Time Synchronization with Windows)
# ============================================================
section "STEP 8: Configure Dual Boot (Time Synchronization)"

if ask_choice "Is your system running alongside Windows (Dual Boot)?"; then
  info "Configuring real-time clock (RTC) to local time..."
  timedatectl set-local-rtc 1 --adjust-system-clock || true
  info "Time synchronization configured successfully."
else
  info "Skipped Dual Boot configuration."
fi

# ============================================================
# STEP 9: Remove unnecessary packages (System Cleanup)
# ============================================================
section "STEP 9: Remove unnecessary packages"

if ask_choice "Do you want to run unnecessary packages cleanup (STEP 9)?"; then
  # 9.1 Accessibility tools
  if ask_choice "Do you want to remove accessibility tools (orca, brltty, speech-dispatcher)?"; then
    info "Removing unnecessary accessibility tools..."
    apt-get purge -y orca brltty speech-dispatcher speech-dispatcher-audio-plugins || true
  else
    info "Skipped removing accessibility tools."
  fi

  # 9.2 Printer and scanner services
  if ask_choice "Do you want to remove printer and scanner services (cups, sane, hplip)?"; then
    info "Removing printer and scanner services..."
    apt-get purge -y cups cups-bsd cups-client cups-common sane-utils sane-airscan hplip hplip-data printer-driver-* || true
  else
    info "Skipped removing printer and scanner services."
  fi

  # 9.3 Legacy network or mobile network packages
  if ask_choice "Do you want to remove old network tools (telnet, modemmanager)?"; then
    info "Removing telnet and modemmanager..."
    apt-get purge -y telnet inetutils-telnet modemmanager || true
  else
    info "Skipped removing telnet and modemmanager."
  fi

  # 9.4 Automatically clean up unused dependencies (autoremove)
  if ask_choice "Do you want to automatically clean up unused dependencies (autoremove)?"; then
    info "Automatically cleaning up unused dependencies (autoremove)..."
    apt-get autoremove --purge -y || true
  else
    info "Skipped autoremove."
  fi

  # 9.5 Clear APT download cache
  if ask_choice "Do you want to clear the APT download cache (apt clean)?"; then
    info "Clearing APT download cache..."
    apt-get clean || true
  else
    info "Skipped clearing APT download cache."
  fi

  info "Done. System cleaned up according to your choices."
else
  info "Skipped STEP 9."
fi

# ============================================================
# STEP 10: Configure APT installation block on Host
# ============================================================
section "STEP 10: Configure APT installation block on Host"

if ask_choice "Do you want to enable the 'apt/apt-get install' block on this Host?"; then
  info "Setting up wrappers to block 'apt/apt-get install'..."
  
  # 10.1 Create centralized apt-lock manager
  cat > /usr/local/bin/apt-lock << 'EOF'
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

STATE_FILE="/var/lib/apt-lock-state"
SERVICE_FILE="/etc/systemd/system/apt-lock-on-boot.service"

is_locked() {
    [ -f "$STATE_FILE" ]
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Please run with sudo.${NC}" >&2
        exit 1
    fi
}

show_help() {
    echo -e "${CYAN}=== APT-LOCK Management CLI ===${NC}"
    echo -e "Utility to lock/unlock APT installation and manage its boot service.\n"
    echo -e "Usage:"
    echo -e "  apt-lock <command>\n"
    echo -e "Commands:"
    echo -e "  ${GREEN}lock, --lock${NC}        Lock APT installation (block 'apt install')"
    echo -e "  ${GREEN}unlock, --unlock${NC}    Unlock APT installation temporarily"
    echo -e "  ${GREEN}status, --status${NC}    Show current APT status and boot service status"
    echo -e "  ${GREEN}enable-boot${NC}         Enable auto-lock on system boot"
    echo -e "  ${GREEN}disable-boot${NC}        Disable auto-lock on system boot"
    echo -e "  ${GREEN}install-service${NC}     Install systemd service to auto-lock APT on boot"
    echo -e "  ${GREEN}remove-service${NC}      Remove systemd service from the system"
    echo -e "  ${GREEN}uninstall${NC}           Completely uninstall apt-lock and restore normal APT"
    echo -e "  ${GREEN}help, -h, --help${NC}    Show this help message\n"
    echo -e "Examples:"
    echo -e "  sudo apt-lock lock"
    echo -e "  sudo apt-lock disable-boot"
    echo -e "  apt-lock status"
}

case "$1" in
    --lock|lock)
        check_root
        touch "$STATE_FILE"
        echo -e "${RED}🔒 APT installation has been LOCKED on this Host.${NC}"
        ;;
    --unlock|unlock)
        check_root
        rm -f "$STATE_FILE"
        echo -e "${GREEN}🔓 APT installation has been UNLOCKED on this Host.${NC}"
        ;;
    --status|status)
        if is_locked; then
            echo -e "APT status: ${RED}LOCKED${NC}"
        else
            echo -e "APT status: ${GREEN}UNLOCKED${NC}"
        fi
        
        # Check service installation and status
        if [ -f "$SERVICE_FILE" ]; then
            if systemctl is-enabled apt-lock-on-boot.service &>/dev/null; then
                echo -e "Auto-lock on boot: ${GREEN}ENABLED${NC}"
            else
                echo -e "Auto-lock on boot: ${YELLOW}DISABLED${NC}"
            fi
        else
            echo -e "Auto-lock on boot: ${RED}NOT INSTALLED${NC}"
        fi
        ;;
    enable-boot)
        check_root
        if [ ! -f "$SERVICE_FILE" ]; then
            echo -e "${YELLOW}Warning: Service is not installed. Installing it first...${NC}"
            $0 install-service
        fi
        systemctl enable apt-lock-on-boot.service
        echo -e "${GREEN}🔄 Auto-lock on boot has been ENABLED.${NC}"
        ;;
    disable-boot)
        check_root
        if systemctl is-enabled apt-lock-on-boot.service &>/dev/null; then
            systemctl disable apt-lock-on-boot.service
            echo -e "${YELLOW}🔄 Auto-lock on boot has been DISABLED.${NC}"
        else
            echo -e "Auto-lock on boot is already disabled."
        fi
        ;;
    install-service)
        check_root
        echo -e "Installing systemd service to auto-lock APT on boot..."
        cat > "$SERVICE_FILE" << 'EOF_SERVICE'
[Unit]
Description=Lock APT installation on boot
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/apt-lock lock
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_SERVICE
        systemctl daemon-reload
        echo -e "${GREEN}✅ Service installed successfully at $SERVICE_FILE.${NC}"
        ;;
    remove-service)
        check_root
        echo -e "Removing systemd service..."
        systemctl disable --now apt-lock-on-boot.service 2>/dev/null || true
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        echo -e "${GREEN}✅ Service removed successfully.${NC}"
        ;;
    uninstall)
        check_root
        echo -e "${YELLOW}Uninstalling APT-LOCK and restoring default APT commands...${NC}"
        $0 remove-service
        rm -f "$STATE_FILE"
        rm -f /usr/local/bin/apt /usr/local/bin/apt-get
        echo -e "${GREEN}✅ Default 'apt' and 'apt-get' commands have been restored.${NC}"
        echo -e "${GREEN}✅ APT-LOCK has been completely uninstalled.${NC}"
        rm -f "$0"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
EOF

  # 10.2 Create wrapper for apt
  cat > /usr/local/bin/apt << 'EOF'
#!/bin/bash
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
STATE_FILE="/var/lib/apt-lock-state"

# Detect 'install' or 'reinstall' command
is_install=false
for arg in "$@"; do
    if [[ "$arg" == "install" || "$arg" == "reinstall" ]]; then
        is_install=true
        break
    fi
done

if [ "$is_install" = true ] && [ -f "$STATE_FILE" ]; then
    echo -e "${RED}🚨 [SYSTEM BLOCK] 'apt install/reinstall' is disabled on this Host.${NC}"
    echo -e "${YELLOW}Please use Distrobox or Flatpak for installing packages!${NC}"
    echo -e "${CYAN}Tip: To temporarily bypass this block, run 'sudo apt-lock unlock' first.${NC}"
    echo -e "To lock again afterward, run 'sudo apt-lock lock'."
    exit 1
fi

exec /usr/bin/apt "$@"
EOF

  # 10.3 Create wrapper for apt-get
  cat > /usr/local/bin/apt-get << 'EOF'
#!/bin/bash
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
STATE_FILE="/var/lib/apt-lock-state"

# Detect 'install' or 'reinstall' command
is_install=false
for arg in "$@"; do
    if [[ "$arg" == "install" || "$arg" == "reinstall" ]]; then
        is_install=true
        break
    fi
done

if [ "$is_install" = true ] && [ -f "$STATE_FILE" ]; then
    echo -e "${RED}🚨 [SYSTEM BLOCK] 'apt-get install/reinstall' is disabled on this Host.${NC}"
    echo -e "${YELLOW}Please use Distrobox or Flatpak for installing packages!${NC}"
    echo -e "${CYAN}Tip: To temporarily bypass this block, run 'sudo apt-lock unlock' first.${NC}"
    echo -e "To lock again afterward, run 'sudo apt-lock lock'."
    exit 1
fi

exec /usr/bin/apt-get "$@"
EOF

  # 10.4 Grant execution permissions to all files
  chmod +x /usr/local/bin/apt-lock /usr/local/bin/apt /usr/local/bin/apt-get
  
  # 10.5 Setup and enable auto-lock service using the CLI itself
  info "Installing and enabling auto-lock on boot service..."
  /usr/local/bin/apt-lock install-service
  /usr/local/bin/apt-lock enable-boot

  # 10.6 Lock by default
  /usr/local/bin/apt-lock lock
  
  info "Setup successful! From now on, 'apt install' and 'apt-get install' are blocked on the Host."
else
  info "Skipped configuring APT block."
fi

# ============================================================
# STEP 11: Configure SUDO lock on Host
# ============================================================
section "STEP 11: Configure SUDO lock on Host"

if ask_choice "Do you want to enable the 'sudo-lock' block on this Host?"; then
  info "Setting up wrappers and manager CLI to block 'sudo'..."
  
  # 11.1 Create centralized sudo-lock manager
  cat > /usr/local/bin/sudo-lock << 'EOF'
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

STATE_FILE="/var/lib/sudo-lock-state"
SERVICE_FILE="/etc/systemd/system/sudo-lock-on-boot.service"

is_locked() {
    [ -f "$STATE_FILE" ]
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Please run with sudo.${NC}" >&2
        exit 1
    fi
}

show_help() {
    echo -e "${CYAN}=== SUDO-LOCK Management CLI ===${NC}"
    echo -e "Utility to lock/unlock SUDO usage and manage its boot service.\n"
    echo -e "Usage:"
    echo -e "  sudo-lock <command>\n"
    echo -e "Commands:"
    echo -e "  ${GREEN}lock, --lock${NC}        Lock SUDO usage (block 'sudo')"
    echo -e "  ${GREEN}unlock, --unlock${NC}    Unlock SUDO usage temporarily"
    echo -e "  ${GREEN}status, --status${NC}    Show current SUDO status and boot service status"
    echo -e "  ${GREEN}enable-boot${NC}         Enable auto-lock on system boot"
    echo -e "  ${GREEN}disable-boot${NC}        Disable auto-lock on system boot"
    echo -e "  ${GREEN}install-service${NC}     Install systemd service to auto-lock SUDO on boot"
    echo -e "  ${GREEN}remove-service${NC}      Remove systemd service from the system"
    echo -e "  ${GREEN}uninstall${NC}           Completely uninstall sudo-lock and restore normal SUDO"
    echo -e "  ${GREEN}help, -h, --help${NC}    Show this help message\n"
    echo -e "Examples:"
    echo -e "  sudo sudo-lock lock"
    echo -e "  sudo sudo-lock disable-boot"
    echo -e "  sudo-lock status"
}

case "$1" in
    --lock|lock)
        check_root
        touch "$STATE_FILE"
        echo -e "${RED}🔒 SUDO usage has been LOCKED on this Host.${NC}"
        ;;
    --unlock|unlock)
        check_root
        rm -f "$STATE_FILE"
        echo -e "${GREEN}🔓 SUDO usage has been UNLOCKED on this Host.${NC}"
        ;;
    --status|status)
        if is_locked; then
            echo -e "SUDO status: ${RED}LOCKED${NC}"
        else
            echo -e "SUDO status: ${GREEN}UNLOCKED${NC}"
        fi
        
        # Check service installation and status
        if [ -f "$SERVICE_FILE" ]; then
            if systemctl is-enabled sudo-lock-on-boot.service &>/dev/null; then
                echo -e "Auto-lock on boot: ${GREEN}ENABLED${NC}"
            else
                echo -e "Auto-lock on boot: ${YELLOW}DISABLED${NC}"
            fi
        else
            echo -e "Auto-lock on boot: ${RED}NOT INSTALLED${NC}"
        fi
        ;;
    enable-boot)
        check_root
        if [ ! -f "$SERVICE_FILE" ]; then
            echo -e "${YELLOW}Warning: Service is not installed. Installing it first...${NC}"
            $0 install-service
        fi
        systemctl enable sudo-lock-on-boot.service
        echo -e "${GREEN}🔄 Auto-lock on boot has been ENABLED.${NC}"
        ;;
    disable-boot)
        check_root
        if systemctl is-enabled sudo-lock-on-boot.service &>/dev/null; then
            systemctl disable sudo-lock-on-boot.service
            echo -e "${YELLOW}🔄 Auto-lock on boot has been DISABLED.${NC}"
        else
            echo -e "Auto-lock on boot is already disabled."
        fi
        ;;
    install-service)
        check_root
        echo -e "Installing systemd service to auto-lock SUDO on boot..."
        cat > "$SERVICE_FILE" << 'EOF_SERVICE'
[Unit]
Description=Lock SUDO on boot
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sudo-lock lock
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_SERVICE
        systemctl daemon-reload
        echo -e "${GREEN}✅ Service installed successfully at $SERVICE_FILE.${NC}"
        ;;
    remove-service)
        check_root
        echo -e "Removing systemd service..."
        systemctl disable --now sudo-lock-on-boot.service 2>/dev/null || true
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        echo -e "${GREEN}✅ Service removed successfully.${NC}"
        ;;
    uninstall)
        check_root
        echo -e "${YELLOW}Uninstalling SUDO-LOCK and restoring default SUDO command...${NC}"
        $0 remove-service
        rm -f "$STATE_FILE"
        rm -f /usr/local/bin/sudo
        echo -e "${GREEN}✅ Default 'sudo' command has been restored.${NC}"
        echo -e "${GREEN}✅ SUDO-LOCK has been completely uninstalled.${NC}"
        rm -f "$0"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
EOF

  # 11.2 Create wrapper for sudo
  cat > /usr/local/bin/sudo << 'EOF'
#!/bin/bash
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
STATE_FILE="/var/lib/sudo-lock-state"

# Check if the FIRST argument is exactly 'sudo-lock'
is_lock_manager=false
if [ "$1" = "sudo-lock" ]; then
    is_lock_manager=true
fi

if [ -f "$STATE_FILE" ] && [ "$is_lock_manager" = false ]; then
    echo -e "${RED}🚨 [SYSTEM BLOCK] 'sudo' is locked on this Host.${NC}"
    echo -e "${YELLOW}Please use Flatpak, Distrobox or normal user commands!${NC}"
    echo -e "${CYAN}Tip: To temporarily bypass this block, run: sudo sudo-lock unlock${NC}"
    echo -e "To lock again afterward, run: sudo sudo-lock lock."
    exit 1
fi

exec /usr/bin/sudo "$@"
EOF

  # 11.3 Grant execution permissions
  chmod +x /usr/local/bin/sudo-lock /usr/local/bin/sudo

  # 11.4 Setup and enable auto-lock service using the CLI itself
  info "Installing and enabling auto-lock on boot service..."
  /usr/local/bin/sudo-lock install-service
  /usr/local/bin/sudo-lock enable-boot

  # 11.5 Lock by default
  /usr/local/bin/sudo-lock lock

  info "Setup successful! From now on, 'sudo' commands are blocked on the Host."
else
  info "Skipped configuring SUDO block."
fi

# ============================================================
# COMPLETED
# ============================================================
section "COMPLETED"

echo ""
echo -e "${GREEN}All packages have been successfully installed!${NC}"
echo "To temporarily unlock APT, run: sudo apt-lock unlock"
echo "To lock APT again, run: sudo apt-lock lock"
echo "To restore normal APT installation commands and uninstall cleanly, simply run:"
echo "  sudo apt-lock uninstall"
echo ""
echo "To temporarily unlock SUDO, run: sudo sudo-lock unlock"
echo "To lock SUDO again, run: sudo sudo-lock lock"
echo "To restore normal SUDO command and uninstall cleanly, simply run:"
echo "  sudo sudo-lock uninstall"
echo ""

if ask_choice "Reboot now?"; then
  info "Rebooting..."
  reboot
else
  warn "Remember to reboot before use for changes to take effect."
fi