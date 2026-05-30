#!/bin/bash
# ============================================================
#  Ubuntu 26.04 — Minimal Setup (Remove Snap & Optimize System)
#  Run with: sudo bash setup-ubuntu.sh
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
# STEP 1: Completely remove and block Snapd (Hold)
# ============================================================
section "STEP 1: Completely remove and block Snapd"

if ask_choice "Do you want to completely remove and block Snapd?"; then
  # 1.1 Scan and purge all Snap packages using snap list
  if command -v snap >/dev/null 2>&1; then
    info "Snap detected. Scanning and removing snap packages..."
    
    # Loop to remove snaps until none remain (or no more can be removed due to dependencies)
    while true; do
      # Get list of snaps (skip header line)
      snaps=$(snap list 2>/dev/null | awk 'NR>1 {print $1}' || true)
      
      if [ -z "$snaps" ]; then
        info "No snap packages left to remove."
        break
      fi
      
      info "Current snap packages on the system: $(echo $snaps | tr '\n' ' ')"
      
      removed_in_this_pass=0
      for snap_app in $snaps; do
        info "Removing snap: $snap_app..."
        # Use --purge to completely clear configuration data
        if snap remove --purge "$snap_app" 2>/dev/null; then
          info "Successfully removed: $snap_app"
          removed_in_this_pass=$((removed_in_this_pass + 1))
        else
          warn "Could not remove: $snap_app (due to dependencies, will retry in the next pass)."
        fi
      done
      
      # If no snaps were removed in this pass, break loop to avoid infinite loop
      if [ "$removed_in_this_pass" -eq 0 ]; then
        warn "Cannot automatically remove remaining snaps. Continuing with system cleanup..."
        break
      fi
    done
  else
    info "Snap is not installed or not available. Continuing with system cleanup..."
  fi

  # 1.2 Stop and disable Snapd services
  info "Stopping and disabling snapd services..."
  systemctl stop snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
  systemctl disable snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true

  # 1.3 Completely purge snapd via APT
  info "Purging snapd package..."
  apt-get purge -y snapd || true
  info "Automatically cleaning up related libraries (autoremove)..."
  apt-get autoremove --purge -y || true

  # 1.4 Clean up redundant snap directories
  info "Deleting redundant snap directories..."
  rm -rf /var/cache/snapd/
  rm -rf /var/snap
  rm -rf /var/lib/snapd
  rm -rf /var/log/snapd
  rm -rf /snap
  rm -rf "$HOME/snap" 2>/dev/null || true
  if [ -n "$SUDO_USER" ]; then
    rm -rf "/home/$SUDO_USER/snap" 2>/dev/null || true
  fi

  # 1.5 Prevent Snapd from being reinstalled
  info "Creating APT preference file /etc/apt/preferences.d/nosnap.pref..."
  cat > /etc/apt/preferences.d/nosnap.pref << 'EOF'
# Prevent snapd from being reinstalled via APT
Package: snapd
Pin: release *
Pin-Priority: -10
EOF

  info "Done. Snap has been completely removed and blocked."
else
  info "Skipped STEP 1."
fi

# ============================================================
# STEP 2: Install Flatpak + GNOME Software (Alternative App Store)
# ============================================================
section "STEP 2: Install Flatpak + GNOME Software"

if ask_choice "Do you want to install Flatpak + GNOME Software?"; then
  info "Updating package list..."
  apt update

  info "Installing Flatpak, GNOME Software, and Flatpak plugin..."
  apt install -y flatpak gnome-software gnome-software-plugin-flatpak

  info "Adding Flathub repository..."
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  info "Done. Note: A reboot is required for GNOME Software to show Flatpak apps."
else
  info "Skipped STEP 2."
fi

# ============================================================
# STEP 3: Install zram-config (Compressed Swap in RAM)
# ============================================================
section "STEP 3: Install zram-config"

if ask_choice "Do you want to install and configure zram-config?"; then
  info "Installing zram to optimize RAM..."
  apt install -y zram-config

  info "Configuring vm.swappiness=150 to prioritize RAM compression..."
  # Write optimal swappiness for zram into sysctl
  echo "vm.swappiness=150" > /etc/sysctl.d/99-zram-swappiness.conf
  # Apply configuration immediately
  sysctl -p /etc/sysctl.d/99-zram-swappiness.conf || true

  info "Done. Compressed zram swap will take full effect after reboot."
else
  info "Skipped STEP 3."
fi

# ============================================================
# STEP 4: Install tuned + tuned-ppd (Power/Performance Optimization)
# ============================================================
section "STEP 4: Install tuned + tuned-ppd"

if ask_choice "Do you want to install and configure tuned + tuned-ppd?"; then
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
  info "Skipped STEP 4."
fi

# ============================================================
# STEP 5: Install Distrobox + Podman
# ============================================================
section "STEP 5: Install Distrobox + Podman"

if ask_choice "Do you want to install Distrobox + Podman?"; then
  info "Installing podman (backend for distrobox)..."
  apt install -y podman

  info "Installing distrobox..."
  apt install -y distrobox

  info "Done."
else
  info "Skipped STEP 5."
fi

# ============================================================
# STEP 6: Install fcitx5-lotus (Vietnamese Keyboard)
# ============================================================
section "STEP 6: Install fcitx5-lotus"

if ask_choice "Do you want to install fcitx5-lotus?"; then
  info "Purging ibus (if exists) as it conflicts with fcitx5-lotus..."
  apt-get purge -y ibus || true
  apt-get autoremove --purge -y || true

  info "Adding fcitx5-lotus repository..."
  CODENAME=$(grep '^UBUNTU_CODENAME=' /etc/os-release | cut -d'=' -f2)
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://fcitx5-lotus.pages.dev/pubkey.gpg | gpg --dearmor -o /etc/apt/keyrings/fcitx5-lotus.gpg
  echo "deb [signed-by=/etc/apt/keyrings/fcitx5-lotus.gpg] https://fcitx5-lotus.pages.dev/apt/$CODENAME $CODENAME main" | tee /etc/apt/sources.list.d/fcitx5-lotus.list

  info "Updating packages and installing fcitx5-lotus..."
  apt-get update
  apt-get install -y fcitx5-lotus

  info "Configuring environment variables for non-root user..."
  if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    USER_GROUP=$(id -gn "$SUDO_USER")
  else
    USER_HOME="$HOME"
    USER_GROUP=$(id -gn)
  fi

  BASH_PROFILE="$USER_HOME/.bash_profile"
  touch "$BASH_PROFILE"
  if [ -n "$SUDO_USER" ]; then
    chown "$SUDO_USER:$USER_GROUP" "$BASH_PROFILE"
  fi

  if ! grep -q "XMODIFIERS=@im=fcitx" "$BASH_PROFILE" 2>/dev/null; then
    cat <<EOF >> "$BASH_PROFILE"

# fcitx5-lotus environment variables
export XMODIFIERS=@im=fcitx
export QT_IM_MODULE=fcitx
export QT_IM_MODULES="wayland;fcitx"
export GLFW_IM_MODULE=ibus
EOF
    info "Environment variables added to $BASH_PROFILE."
  else
    info "Environment variables already configured in $BASH_PROFILE."
  fi

  info "Done."
else
  info "Skipped STEP 6."
fi
warn "After reboot: run 'im-config' and select Fcitx 5 as default input method."
warn "Then configure Fcitx 5 to add and customize your Vietnamese layout."

# ============================================================
# STEP 7: Configure Dual Boot (Time Synchronization with Windows)
# ============================================================
section "STEP 7: Configure Dual Boot (Time Synchronization)"

if ask_choice "Is your system running alongside Windows (Dual Boot)?"; then
  info "Configuring real-time clock (RTC) to local time..."
  timedatectl set-local-rtc 1 --adjust-system-clock || true
  info "Time synchronization configured successfully."
else
  info "Skipped Dual Boot configuration."
fi

# ============================================================
# STEP 8: Remove unnecessary packages (System Cleanup)
# ============================================================
section "STEP 8: Remove unnecessary packages"

if ask_choice "Do you want to run unnecessary packages cleanup (STEP 8)?"; then
  # 8.1 Accessibility tools
  if ask_choice "Do you want to remove accessibility tools (orca, brltty, speech-dispatcher)?"; then
    info "Removing unnecessary accessibility tools..."
    apt-get purge -y orca brltty speech-dispatcher speech-dispatcher-audio-plugins || true
  else
    info "Skipped removing accessibility tools."
  fi

  # 8.2 Printer and scanner services
  if ask_choice "Do you want to remove printer and scanner services (cups, sane, hplip)?"; then
    info "Removing printer and scanner services..."
    apt-get purge -y cups cups-bsd cups-client cups-common sane-utils sane-airscan hplip hplip-data printer-driver-* || true
  else
    info "Skipped removing printer and scanner services."
  fi

  # 8.3 Legacy network or mobile network packages
  if ask_choice "Do you want to remove old network tools (telnet, modemmanager)?"; then
    info "Removing telnet and modemmanager..."
    apt-get purge -y telnet inetutils-telnet modemmanager || true
  else
    info "Skipped removing telnet and modemmanager."
  fi

  # 8.4 Automatically clean up unused dependencies (autoremove)
  if ask_choice "Do you want to automatically clean up unused dependencies (autoremove)?"; then
    info "Automatically cleaning up unused dependencies (autoremove)..."
    apt-get autoremove --purge -y || true
  else
    info "Skipped autoremove."
  fi

  # 8.5 Clear APT download cache
  if ask_choice "Do you want to clear the APT download cache (apt clean)?"; then
    info "Clearing APT download cache..."
    apt-get clean || true
  else
    info "Skipped clearing APT download cache."
  fi

  info "Done. System cleaned up according to your choices."
else
  info "Skipped STEP 8."
fi

# ============================================================
# STEP 9: Configure APT installation block on Host
# ============================================================
section "STEP 9: Configure APT installation block on Host"

if ask_choice "Do you want to enable the 'apt/apt-get install' block on this Host?"; then
  info "Setting up wrappers to block 'apt/apt-get install'..."
  
  # 9.1 Create centralized apt-lock manager
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

  # 9.2 Create wrapper for apt
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

  # 9.3 Create wrapper for apt-get
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

  # 9.4 Grant execution permissions to all files
  chmod +x /usr/local/bin/apt-lock /usr/local/bin/apt /usr/local/bin/apt-get
  
  # 9.5 Setup and enable auto-lock service using the CLI itself
  info "Installing and enabling auto-lock on boot service..."
  /usr/local/bin/apt-lock install-service
  /usr/local/bin/apt-lock enable-boot

  # 9.6 Lock by default
  /usr/local/bin/apt-lock lock
  
  info "Setup successful! From now on, 'apt install' and 'apt-get install' are blocked on the Host."
else
  info "Skipped configuring APT block."
fi

# ============================================================
# STEP 10: Configure SUDO lock on Host
# ============================================================
section "STEP 10: Configure SUDO lock on Host"

if ask_choice "Do you want to enable the 'sudo-lock' block on this Host?"; then
  info "Setting up wrappers and manager CLI to block 'sudo'..."
  
  # 10.1 Create centralized sudo-lock manager
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

  # 10.2 Create wrapper for sudo
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

  # 10.3 Grant execution permissions
  chmod +x /usr/local/bin/sudo-lock /usr/local/bin/sudo

  # 10.4 Setup and enable auto-lock service using the CLI itself
  info "Installing and enabling auto-lock on boot service..."
  /usr/local/bin/sudo-lock install-service
  /usr/local/bin/sudo-lock enable-boot

  # 10.5 Lock by default
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
echo -e "${GREEN}Successfully removed Snap, cleaned unnecessary packages, and configured Flatpak, zram, tuned, distrobox, and fcitx5-lotus!${NC}"
echo "To restore Snap in the future, delete the file: /etc/apt/preferences.d/nosnap.pref"
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
