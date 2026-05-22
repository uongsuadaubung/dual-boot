#!/bin/bash
# ============================================================
#  Ubuntu 26.04 — Minimal Setup (Remove Snap & Optimize System)
#  Run with: sudo bash setup-ubuntu.sh
# ============================================================

set -e  # stop on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32'
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

# 1.5 Prevent Snapd from being reinstalled
info "Creating APT preference file /etc/apt/preferences.d/nosnap.pref..."
cat > /etc/apt/preferences.d/nosnap.pref << 'EOF'
# Prevent snapd from being reinstalled via APT
Package: snapd
Pin: release *
Pin-Priority: -10
EOF

info "Done. Snap has been completely removed and blocked."

# ============================================================
# STEP 2: Install Flatpak + GNOME Software (Alternative App Store)
# ============================================================
section "STEP 2: Install Flatpak + GNOME Software"

info "Updating package list..."
apt update

info "Installing Flatpak, GNOME Software, and Flatpak plugin..."
apt install -y flatpak gnome-software gnome-software-plugin-flatpak

info "Adding Flathub repository..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

info "Done. Note: A reboot is required for GNOME Software to show Flatpak apps."

# ============================================================
# STEP 3: Install zram-config (Compressed Swap in RAM)
# ============================================================
section "STEP 3: Install zram-config"

info "Installing zram to optimize RAM..."
apt install -y zram-config

info "Configuring vm.swappiness=150 to prioritize RAM compression..."
# Write optimal swappiness for zram into sysctl
echo "vm.swappiness=150" > /etc/sysctl.d/99-zram-swappiness.conf
# Apply configuration immediately
sysctl -p /etc/sysctl.d/99-zram-swappiness.conf || true

info "Done. Compressed zram swap will take full effect after reboot."

# ============================================================
# STEP 4: Install tuned + tuned-ppd (Power/Performance Optimization)
# ============================================================
section "STEP 4: Install tuned + tuned-ppd"

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
# STEP 5: Install Distrobox + Podman
# ============================================================
section "STEP 5: Install Distrobox + Podman"

info "Installing podman (backend for distrobox)..."
apt install -y podman

info "Installing distrobox..."
apt install -y distrobox

info "Done."

# ============================================================
# STEP 6: Install ibus-unikey (Vietnamese Keyboard)
# ============================================================
section "STEP 6: Install ibus-unikey"

info "Installing ibus and ibus-unikey..."
apt install -y ibus ibus-unikey

info "Done."
warn "After reboot: run 'im-config' and select IBus as default input method."
warn "Then run 'ibus-setup', go to Input Method -> Add -> Vietnamese -> Unikey."

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

# ============================================================
# STEP 9: Configure APT installation block on Host
# ============================================================
section "STEP 9: Configure APT installation block on Host"

if ask_choice "Do you want to enable the 'apt/apt-get install' block on this Host?"; then
  info "Setting up wrappers to block 'apt/apt-get install'..."
  
  # 9.1 Create wrapper for apt
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

  # 9.2 Create wrapper for apt-get
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
        continue # Remove this parameter so it is not passed to the real apt-get thật
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

  # 9.3 Grant execution permissions to wrapper files
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
echo -e "${GREEN}Successfully removed Snap, cleaned unnecessary packages, and configured Flatpak, zram, tuned, distrobox, and ibus-unikey!${NC}"
echo "To restore Snap in the future, delete the file: /etc/apt/preferences.d/nosnap.pref"
echo "To restore normal APT installation commands, simply run:"
echo "  sudo rm -f /usr/local/bin/apt /usr/local/bin/apt-get"
echo ""

if ask_choice "Reboot now?"; then
  info "Rebooting..."
  reboot
else
  warn "Remember to reboot before use for changes to take effect."
fi
