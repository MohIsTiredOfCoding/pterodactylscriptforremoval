#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# noninteractive.sh - freeroot: bootstrap a FULL Ubuntu 24.04 "noble" server rootfs
# Usage: sudo bash noninteractive.sh
# Note: run on a Linux host (Debian/Ubuntu/WSL recommended). If on Windows, use WSL.

ROOTFS_DIR="$(pwd)/rootfs"
PROOT_LOCAL="$ROOTFS_DIR/usr/local/bin/proot"
MAX_RETRIES=20
TIMEOUT=2

# Config
CODENAME="noble"        # Ubuntu 24.04
UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu"

# Detect architecture
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported host architecture: $HOST_ARCH"; exit 1 ;;

esac

# Helper: print with color
info(){ printf "\e[1;36m[*]\e[0m %s\n" "$*"; }
warn(){ printf "\e[1;33m[!]\e[0m %s\n" "$*"; }
err(){ printf "\e[1;31m[-]\e[0m %s\n" "$*"; }

# Ensure running on a Linux-like environment
if [ -z "$(uname | grep -i linux || true)" ]; then
  err "This script expects a Linux environment (or WSL). If you are on Windows, run inside WSL."
  exit 1
fi

mkdir -p "$ROOTFS_DIR"

# Check for debootstrap; if missing try to install it (only works when apt is available)
if ! command -v debootstrap >/dev/null 2>&1; then
  warn "debootstrap not found on host."
  if command -v apt-get >/dev/null 2>&1; then
    info "Attempting to install debootstrap with apt-get..."
    sudo apt-get update -y || true
    sudo apt-get install -y debootstrap || {
      warn "apt-get failed to install debootstrap. You may need to install debootstrap manually."
    }
  else
    warn "No apt-get available to auto-install debootstrap. Please install debootstrap on host, then re-run."
    err "Install instructions (Debian/Ubuntu): sudo apt-get install debootstrap"
    exit 1
  fi
fi

# Bootstrap Ubuntu rootfs
info "Starting debootstrap for Ubuntu ${CODENAME} (${ARCH}) into ${ROOTFS_DIR}..."
sudo debootstrap --arch="$ARCH" --include=ubuntu-standard \
  --components=main,restricted,universe,multiverse \
  "$CODENAME" "$ROOTFS_DIR" "$UBUNTU_MIRROR"

info "debootstrap finished."

# Fetch proot (matching original freeroot style)
info "Downloading proot for host arch (${HOST_ARCH})..."
mkdir -p "$ROOTFS_DIR/usr/local/bin"
PROOT_URL="https://raw.githubusercontent.com/foxytouxxx/freeroot/main/proot-${HOST_ARCH}"

retry_count=0
while [ $retry_count -lt $MAX_RETRIES ]; do
  if curl -fsSL -o "$PROOT_LOCAL" "$PROOT_URL"; then
    chmod 0755 "$PROOT_LOCAL"
    info "proot downloaded to $PROOT_LOCAL"
    break
  fi
  warn "failed to download proot (attempt $((retry_count+1))/$MAX_RETRIES). Retrying..."
  sleep $TIMEOUT
  retry_count=$((retry_count+1))
done

if [ ! -x "$PROOT_LOCAL" ]; then
  err "Could not download proot. Aborting."
  exit 1
fi

# Fix resolv.conf inside rootfs so apt works in chroot
info "Configuring resolv.conf inside rootfs..."
cat > "$ROOTFS_DIR/etc/resolv.conf" <<EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

touch "$ROOTFS_DIR/.installed"

printf "\n\e[1;37m====================================================\e[0m\n"
printf "  Bootstrapped Ubuntu %s in: %s\n" "$CODENAME" "$ROOTFS_DIR"
printf "  Next: entering proot -> finishing package upgrades and server meta-packages\n"
printf "\e[1;37m====================================================\e[0m\n\n"

info "Entering the new rootfs via proot to finalize setup (noninteractive)..."

CHROOT_SCRIPT=$(mktemp)
cat > "$CHROOT_SCRIPT" <<'EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || true
apt-get upgrade -y || true
apt-get install -y ubuntu-standard || true
apt-get install -y ubuntu-server
apt-get install -y sudo net-tools curl wget ca-certificates gnupg lsb-release apt-transport-https || true
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOF

chmod +x "$CHROOT_SCRIPT"
cp "$CHROOT_SCRIPT" "$ROOTFS_DIR/tmp/chroot_script_runner.sh"
chmod +x "$ROOTFS_DIR/tmp/chroot_script_runner.sh"

"$PROOT_LOCAL" --rootfs="$ROOTFS_DIR" -0 -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit \
  /bin/bash -lc "/tmp/chroot_script_runner.sh" || warn "proot chroot finished with warnings"

rm -f "$CHROOT_SCRIPT" "$ROOTFS_DIR/tmp/chroot_script_runner.sh"

info "Finalization complete. Your rootfs should now be a full Ubuntu ${CODENAME} server installation."

printf "\n\e[1;32m==== MISSION COMPLETED: Full Ubuntu Server rootfs bootstrapped ====\e[0m\n"
printf "Rootfs location: %s\n" "$ROOTFS_DIR"
printf "You can now run the environment with:\n"
printf "  %s --rootfs=\"%s\" -0 -w \"/root\" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit /bin/bash\n" "$PROOT_LOCAL" "$ROOTFS_DIR"
printf "\n"
