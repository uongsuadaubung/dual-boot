#!/bin/bash

# ============================================================
#  Bluefin/Fedora Silverblue Setup Script
#  Install fcitx5-lotus and perform post-install configurations
# ============================================================

set -e  # Dừng script nếu có lỗi xảy ra

# Mã màu ANSI để làm giao diện đẹp hơn
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
section() { echo -e "\n${BLUE}========== $1 ==========${NC}"; }

# 1. Kiểm tra môi trường chạy (Tránh chạy trong toolbox/distrobox/container)
if [ -f /run/.containerenv ] || [ -f /.dockerenv ]; then
  error "Script này đang chạy trong container (toolbox/distrobox)."
  error "Vui lòng chạy script trên máy host (hệ điều hành chính) để rpm-ostree hoạt động!"
  exit 1
fi

# 2. Kiểm tra các công cụ phụ thuộc (curl, jq, rpm-ostree)
for cmd in curl jq rpm-ostree; do
  if ! command -v "$cmd" &> /dev/null; then
    error "Không tìm thấy lệnh '$cmd'. Vui lòng cài đặt trước khi chạy script."
    exit 1
  fi
done

section "Bắt đầu thiết lập fcitx5-lotus cho Bluefin/Silverblue"

# 3. Lấy thông tin phiên bản mới nhất từ GitHub API
info "Đang kết nối GitHub API để lấy các gói cài đặt (.rpm)..."
API_URL="https://api.github.com/repos/LotusInputMethod/fcitx5-lotus/releases/latest"

# Gọi API và lọc ra các file .rpm chính (loại bỏ debuginfo và debugsource)
ASSETS_DATA=$(curl -s "$API_URL" | jq -r '
  .assets[] 
  | select(.name | endswith(".rpm") and (contains("debuginfo") | not) and (contains("debugsource") | not)) 
  | "\(.name)\t\(.browser_download_url)"
')

if [ -z "$ASSETS_DATA" ]; then
  error "Không thể lấy danh sách gói cài đặt từ GitHub API."
  exit 1
fi

# Chuyển đổi dữ liệu thành mảng
mapfile -t ASSETS_ARR <<< "$ASSETS_DATA"
NUM_OPTIONS=${#ASSETS_ARR[@]}

if [ "$NUM_OPTIONS" -eq 0 ]; then
  error "Không tìm thấy file .rpm nào phù hợp trong bản phát hành mới nhất."
  exit 1
fi

SELECTED_LINE=""
if [ "$NUM_OPTIONS" -eq 1 ]; then
  SELECTED_LINE="${ASSETS_ARR[0]}"
  FILENAME=$(echo "$SELECTED_LINE" | cut -f1)
  info "Tìm thấy 1 gói cài đặt: $FILENAME. Tự động lựa chọn."
else
  info "Tìm thấy nhiều gói cài đặt fcitx5-lotus (.rpm):"
  for i in "${!ASSETS_ARR[@]}"; do
    name=$(echo "${ASSETS_ARR[$i]}" | cut -f1)
    echo -e "  [$((i+1))] $name"
  done
  
  while true; do
    read -p "👉 Chọn gói muốn cài đặt (1-$NUM_OPTIONS): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$NUM_OPTIONS" ]; then
      SELECTED_LINE="${ASSETS_ARR[$((choice-1))]}"
      break
    else
      warn "Lựa chọn không hợp lệ. Vui lòng chọn lại."
    fi
  done
fi

FILENAME=$(echo "$SELECTED_LINE" | cut -f1)
DOWNLOAD_URL=$(echo "$SELECTED_LINE" | cut -f2)

info "Bạn đã chọn: $FILENAME"

# 4. Tải file .rpm về thư mục tạm
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

info "Đang tải xuống $FILENAME..."
curl -L -o "$TMP_DIR/$FILENAME" "$DOWNLOAD_URL"

# 5. Cài đặt qua rpm-ostree
info "Đang tiến hành cài đặt $FILENAME qua rpm-ostree (áp dụng trực tiếp --apply-live)..."
LIVE_APPLIED=false
if rpm-ostree install --apply-live "$TMP_DIR/$FILENAME"; then
  info "Đã cài đặt và áp dụng live thành công!"
  LIVE_APPLIED=true
else
  warn "Áp dụng trực tiếp --apply-live thất bại hoặc không được hỗ trợ. Đang cài đặt chuẩn (yêu cầu reboot)..."
  rpm-ostree install "$TMP_DIR/$FILENAME"
fi

if [ "$LIVE_APPLIED" = true ]; then
  info "Đang kích hoạt và chạy dịch vụ fcitx5-lotus-server cho người dùng hiện tại..."
  CURRENT_USER=$(whoami)
  if sudo systemctl enable --now fcitx5-lotus-server@"$CURRENT_USER".service 2>/dev/null; then
    info "Đã khởi động dịch vụ fcitx5-lotus-server thành công!"
  else
    warn "Khởi động dịch vụ thất bại, đang thử chạy systemd-sysusers và thử lại..."
    if sudo systemd-sysusers && sudo systemctl enable --now fcitx5-lotus-server@"$CURRENT_USER".service; then
      info "Đã khởi động dịch vụ fcitx5-lotus-server thành công!"
    else
      error "Không thể khởi động dịch vụ fcitx5-lotus-server. Bạn có thể cần reboot để áp dụng."
    fi
  fi
fi

section "Cấu hình biến môi trường Fcitx5"
echo -e "💡 Để bộ gõ tiếng Việt Fcitx5-Lotus hoạt động chính xác trên các ứng dụng (GTK, Qt, Wayland),"
echo -e "   bạn cần cấu hình các biến môi trường IM."
read -p "👉 Bạn có muốn tự động cấu hình các biến này không? (y/n): " setup_env

if [[ "$setup_env" == "y" || "$setup_env" == "Y" ]]; then
  ENV_DIR="$HOME/.config/environment.d"
  mkdir -p "$ENV_DIR"
  cat << 'EOF' > "$ENV_DIR/fcitx.conf"
XMODIFIERS=@im=fcitx
QT_IM_MODULE=fcitx
QT_IM_MODULES="wayland;fcitx"
GLFW_IM_MODULE=ibus
EOF
  info "Đã ghi cấu hình biến môi trường vào: $ENV_DIR/fcitx.conf"
  info "Biến cấu hình:"
  cat "$ENV_DIR/fcitx.conf"
else
  info "Đã bỏ qua thiết lập biến môi trường."
fi

section "Cấu hình Tối ưu systemd-oomd"
echo -e "💡 Tối ưu hóa systemd-oomd giúp chống treo đơ máy (chuột/bàn phím) khi bị nghẽn RAM/zRAM."
read -p "👉 Bạn có muốn cấu hình systemd-oomd không? (y/n): " setup_oomd

if [[ "$setup_oomd" == "y" || "$setup_oomd" == "Y" ]]; then
  read -p "👉 Nhập ngưỡng áp lực bộ nhớ muốn cấu hình (Mặc định: 40%): " PRESSURE_LIMIT
  PRESSURE_LIMIT=${PRESSURE_LIMIT:-40}
  
  TARGET_DIR="/etc/systemd/system/user-.slice.d"
  TARGET_FILE="$TARGET_DIR/10-oomd.conf"
  
  info "Tạo thư mục cấu hình: $TARGET_DIR (yêu cầu sudo)..."
  sudo mkdir -p "$TARGET_DIR"
  
  info "Ghi cấu hình tối ưu vào $TARGET_FILE..."
  cat << EOF | sudo tee "$TARGET_FILE" > /dev/null
[Slice]
# Ép systemd-oomd phải kill các tiến trình trong user slice nếu RAM/zRAM bị nghẽn
ManagedOOMMemoryPressure=kill

# Nếu hệ thống bị nghẽn quá mức cấu hình trong 20 giây, tiến trình lỗi sẽ bị trảm
ManagedOOMMemoryPressureLimit=${PRESSURE_LIMIT}%
EOF

  info "Nạp lại cấu hình hệ thống (daemon-reload)..."
  sudo systemctl daemon-reload
  
  info "Khởi động lại dịch vụ systemd-oomd..."
  sudo systemctl restart systemd-oomd
  
  info "Cấu hình OOMD hoàn tất với ngưỡng ${PRESSURE_LIMIT}%!"
  echo "--------------------------------------------------"
  systemctl show user-.slice --property=ManagedOOMMemoryPressure --property=ManagedOOMMemoryPressureLimit
  echo "--------------------------------------------------"
else
  info "Đã bỏ qua cấu hình systemd-oomd."
fi

section "Hoàn tất thiết lập!"
echo -e "🎉 Quá trình cài đặt hoàn thành thành công."
if [ "$LIVE_APPLIED" = true ]; then
  echo -e "💡 Lớp package đã được áp dụng trực tiếp (live) và dịch vụ đã khởi chạy."
  echo -e "⚠️ Bạn cần ĐĂNG XUẤT và ĐĂNG NHẬP lại (hoặc khởi động lại máy) để các biến môi trường được kích hoạt."
else
  echo -e "⚠️ Bạn cần khởi động lại máy tính để hệ điều hành nạp lớp package mới và áp dụng biến môi trường."
fi
read -p "👉 Bạn có muốn khởi động lại hệ thống ngay bây giờ? (y/n): " reboot_now

if [[ "$reboot_now" == "y" || "$reboot_now" == "Y" ]]; then
  info "Đang khởi động lại hệ thống..."
  systemctl reboot
else
  info "Đã bỏ qua khởi động lại. Vui lòng tự khởi động lại máy sau."
fi
