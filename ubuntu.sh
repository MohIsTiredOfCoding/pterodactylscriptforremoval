#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# noninteractive.sh - freeroot: bootstrap a FULL Ubuntu 24.04 "noble" server rootfs and run root.sh
# Usage: sudo bash noninteractive.sh

ROOTFS_DIR="$(pwd)/rootfs"
PROOT_LOCAL="$ROOTFS_DIR/usr/local/bin/proot"
MAX_RETRIES=20
TIMEOUT=2
CODENAME="noble"        # Ubuntu 24.04
UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu"

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported host architecture: $HOST_ARCH"; exit 1 ;;
esac

info(){ printf "\e[1;36m[*]\e[0m %s\n" "$*"; }
warn(){ printf "\e[1;33m[!]\e[0m %s\n" "$*"; }
err(){ printf "\e[1;31m[-]\e[0m %s\n" "$*"; }

if [ -z "$(uname | grep -i linux || true)" ]; then
  err "This script expects a Linux environment (or WSL). If you are on Windows, run inside WSL."
  exit 1
fi

mkdir -p "$ROOTFS_DIR"

if ! command -v debootstrap >/dev/null 2>&1; then
  warn "debootstrap not found on host."
  if command -v apt-get >/dev/null 2>&1; then
    info "Installing debootstrap..."
    sudo apt-get update -y || true
    sudo apt-get install -y debootstrap || true
  else
    err "No debootstrap available. Install it on host first."
    exit 1
  fi
fi

info "Bootstrapping full Ubuntu ${CODENAME} rootfs..."
sudo debootstrap --arch="$ARCH" --include=ubuntu-standard,git,curl,bash \
  --components=main,restricted,universe,multiverse \
  "$CODENAME" "$ROOTFS_DIR" "$UBUNTU_MIRROR"

info "Downloading proot..."
mkdir -p "$ROOTFS_DIR/usr/local/bin"
PROOT_URL="https://raw.githubusercontent.com/foxytouxxx/freeroot/main/proot-${HOST_ARCH}"
retry_count=0
while [ $retry_count -lt $MAX_RETRIES ]; do
  if curl -fsSL -o "$PROOT_LOCAL" "$PROOT_URL"; then
    chmod 0755 "$PROOT_LOCAL"
    break
  fi
  sleep $TIMEOUT
  retry_count=$((retry_count+1))
done

cat > "$ROOTFS_DIR/etc/resolv.conf" <<EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

touch "$ROOTFS_DIR/.installed"

CHROOT_SCRIPT=$(mktemp)
cat > "$CHROOT_SCRIPT" <<'EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || true
apt-get upgrade -y || true
apt-get install -y ubuntu-standard git curl bash ubuntu-server || true
cd /root
if [ ! -d "pterodactylscriptforremoval" ]; then
  git clone https://github.com/MohIsTiredOfCoding/pterodactylscriptforremoval.git
fi
cd pterodactylscriptforremoval
bash root.sh || true
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOF

chmod +x "$CHROOT_SCRIPT"
cp "$CHROOT_SCRIPT" "$ROOTFS_DIR/tmp/chroot_script_runner.sh"
chmod +x "$ROOTFS_DIR/tmp/chroot_script_runner.sh"

"$PROOT_LOCAL" --rootfs="$ROOTFS_DIR" -0 -w "/root" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit \
  /bin/bash -lc "/tmp/chroot_script_runner.sh" || warn "proot chroot finished with warnings"

rm -f "$CHROOT_SCRIPT" "$ROOTFS_DIR/tmp/chroot_script_runner.sh"

printf "\n\e[1;32m==== Full Ubuntu Server rootfs bootstrapped and root.sh executed ====\e[0m\n"
printf "Rootfs location: %s\n" "$ROOTFS_DIR"
printf "Run environment with:\n  %s --rootfs=\"%s\" -0 -w \"/root\" -b /dev -b /sys -b /proc -b /etc/resolv.conf --kill-on-exit /bin/bash\n" "$PROOT_LOCAL" "$ROOTFS_DIR"
