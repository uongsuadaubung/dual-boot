# đôi khi app trong distrobox muốn mở trình duyệt ngoài host ví dụ như để
# đăng nhập nhưng host không nhận được tín hiệu thì đây là cách fix

sudo apt update && sudo apt install -y python3-dbus xdg-desktop-portal && \
sudo touch /usr/local/bin/xdg-open && sudo chmod +x /usr/local/bin/xdg-open && \
sudo tee /usr/local/bin/xdg-open > /dev/null << 'EOF'
#!/usr/bin/python3
import sys, dbus, os, subprocess

# Trỏ chính xác về luồng D-Bus Session của máy Host
os.environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path=/run/user/{os.getuid()}/bus"

if len(sys.argv) < 2:
    sys.exit(1)

url = sys.argv[1]

try:
    # Phương án 1: Gọi qua D-Bus Portal truyền thẳng ra Host
    bus = dbus.SessionBus()
    obj = bus.get_object("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop")
    obj.OpenURI("", url, dbus.Dictionary({}, signature='sv'), dbus_interface="org.freedesktop.portal.OpenURI")
except Exception:
    try:
        # Phương án 2: Dự phòng bằng flatpak-spawn
        subprocess.run(["flatpak-spawn", "--host", "xdg-open", url], check=True)
    except Exception:
        try:
            # Phương án 3: Dự phòng bằng distrobox-host-exec
            subprocess.run(["distrobox-host-exec", "xdg-open", url], check=True)
        except Exception:
            sys.exit(1)
EOF
