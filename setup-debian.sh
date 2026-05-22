#!/bin/bash
# ============================================================
#  Debian 13 Trixie — Setup for Intel 12500H
#  Run with: sudo bash setup.sh
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

info "Updating sources.list to include contrib and non-free..."
cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-backports main contrib non-free non-free-firmware
EOF

apt update
info "Done."

# ============================================================
# STEP 2: Install required firmware
# ============================================================
section "STEP 2: Install required firmware"

info "Installing firmware for Intel + other devices..."
apt install -y \
  firmware-linux \
  firmware-linux-nonfree \
  firmware-misc-nonfree \
  firmware-sof-signed \
  intel-microcode

info "Done."

# ============================================================
# STEP 3: Install tuned + tuned-ppd (Power profile management)
# ============================================================
section "STEP 3: Install tuned"

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

# ============================================================
# STEP 4: Install Distrobox + Podman
# ============================================================
section "STEP 4: Install Distrobox"

info "Installing podman (backend for distrobox)..."
apt install -y podman

info "Installing distrobox..."
apt install -y distrobox

info "Done."

# ============================================================
# STEP 5: Install ibus-unikey (Vietnamese Keyboard)
# ============================================================
section "STEP 5: Install ibus-unikey"

apt install -y ibus ibus-unikey

info "Done."
warn "After reboot: run 'im-config' and select IBus as default input method."
warn "Then run 'ibus-setup', go to Input Method -> Add -> Vietnamese -> Unikey."

# ============================================================
# STEP 6: Install zram-tools (Compressed Swap in RAM)
# ============================================================
section "STEP 6: Install zram-tools"

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

# ============================================================
# STEP 7: Install Flatpak + Flathub (for GNOME Software)
# ============================================================
section "STEP 7: Install Flatpak"

apt install -y flatpak gnome-software-plugin-flatpak

info "Adding Flathub repository..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

info "Done. A reboot is required for GNOME Software to show Flatpak apps."

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

# ============================================================
# STEP 10: Configure APT installation block on Host
# ============================================================
section "STEP 10: Configure APT installation block on Host"

if ask_choice "Do you want to enable the 'apt/apt-get install' block on this Host?"; then
  info "Setting up wrappers to block 'apt/apt-get install'..."
  
  # 10.1 Create wrapper for apt
  cat > /usr/local/bin/apt << 'EOF'
#!/bin/bash
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

is_install=false
bypass=false
new_args=()

for arg in "$@"; do
    if [[ "$arg" == "install" ]]; then
        is_install=true
    elif [[ "$arg" == "--force" ]]; then
        bypass=true
        continue # Remove this parameter so it is not passed to the real apt
    fi
    new_args+=("$arg")
done

if [ "$is_install" = true ] && [ "$bypass" = false ]; then
    echo -e "${RED}🚨 [SYSTEM BLOCK] 'apt install' is disabled on this Host.${NC}"
    echo -e "${YELLOW}Please use Distrobox or Flatpak for installing packages!${NC}"
    echo -e "${CYAN}Tip: To bypass this block and install directly on the Host, append '--force'.${NC}"
    echo -e "Example: sudo apt install <package_name> --force"
    exit 1
else
    exec /usr/bin/apt "${new_args[@]}"
fi
EOF

  # 10.2 Create wrapper for apt-get
  cat > /usr/local/bin/apt-get << 'EOF'
#!/bin/bash
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

is_install=false
bypass=false
new_args=()

for arg in "$@"; do
    if [[ "$arg" == "install" ]]; then
        is_install=true
    elif [[ "$arg" == "--force" ]]; then
        bypass=true
        continue # Remove this parameter so it is not passed to the real apt-get
    fi
    new_args+=("$arg")
done

if [ "$is_install" = true ] && [ "$bypass" = false ]; then
    echo -e "${RED}🚨 [SYSTEM BLOCK] 'apt-get install' is disabled on this Host.${NC}"
    echo -e "${YELLOW}Please use Distrobox or Flatpak for installing packages!${NC}"
    echo -e "${CYAN}Tip: To bypass this block and install directly on the Host, append '--force'.${NC}"
    echo -e "Example: sudo apt-get install <package_name> --force"
    exit 1
else
    exec /usr/bin/apt-get "${new_args[@]}"
fi
EOF

  # 10.3 Grant execution permissions to wrapper files
  chmod +x /usr/local/bin/apt
  chmod +x /usr/local/bin/apt-get
  
  info "Setup successful! From now on, 'apt install' and 'apt-get install' are blocked on the Host."
else
  info "Skipped configuring APT block."
fi

# ============================================================
# COMPLETED
# ============================================================
section "COMPLETED"

echo ""
echo -e "${GREEN}All packages have been successfully installed!${NC}"
echo "To restore normal APT installation commands, simply run:"
echo "  sudo rm -f /usr/local/bin/apt /usr/local/bin/apt-get"
echo ""
echo "  After reboot:"
echo "  - GPU will run in Intel iGPU mode"
echo ""

if ask_choice "Reboot now?"; then
  info "Rebooting..."
  reboot
else
  warn "Remember to reboot before use for changes to take effect."
fi