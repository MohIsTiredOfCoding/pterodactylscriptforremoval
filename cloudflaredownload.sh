#!/bin/sh
# Minimal Cloudflared install with certificate setup

set -e

echo ">>> Installing Cloudflared..."
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflared.list
apt update
apt install -y cloudflared

echo ">>> Installed Cloudflared version:"
cloudflared --version

echo ">>> DONE!"
