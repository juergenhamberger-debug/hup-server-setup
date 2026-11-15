#!/usr/bin/env bash
# Ersteinrichtung des Servers für das HUP-Befragungstool (Ubuntu 24.04, IONOS VPS).
# Aufruf einmalig als root in der IONOS-Remotekonsole:
#   curl -fsSL https://raw.githubusercontent.com/juergenhamberger-debug/hup-server-setup/main/setup.sh | bash
# Dieses Skript enthält keine Geheimnisse. Alle Passwörter und Schlüssel werden auf dem Server erzeugt.
set -euo pipefail

REPO="git@github.com:juergenhamberger-debug/hup-befragungstool.git"
APP_DIR="/opt/hup"
export DOMAIN="${DOMAIN:-umfrage.hamberger-partner.de}"
export DEBIAN_FRONTEND=noninteractive

step() { echo; echo "===== $* ====="; }

step "1/7 System aktualisieren"
apt-get update -q
apt-get -y -q -o Dpkg::Options::="--force-confold" upgrade
apt-get -y -q install ca-certificates curl git ufw unattended-upgrades gnupg rsync python3 openssl

step "2/7 Automatische Sicherheitsupdates (Neustart bei Bedarf um 04:30)"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'X'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
X
cat > /etc/apt/apt.conf.d/52hup-autoreboot <<'X'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
X

step "3/7 Auslagerungsspeicher (2 GB) für den Bau der Anwendung"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

step "4/7 Firewall: nur Web (80/443) offen, kein Fernzugang per SSH"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
# Falls SSH später doch geöffnet wird: nur mit Schlüssel, nie mit Passwort
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload ssh 2>/dev/null || true
ufw status

step "5/7 Docker installieren (offizielle Quelle)"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt-get update -q
apt-get -y -q install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
mkdir -p /etc/docker
echo '{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }' > /etc/docker/daemon.json
systemctl restart docker
docker --version

step "6/7 Lesezugang zum Code (Deploy-Schlüssel)"
install -d -m 700 /root/.ssh
[[ -f /root/.ssh/hup_deploy ]] || ssh-keygen -q -t ed25519 -N "" -C "hup-server-deploy" -f /root/.ssh/hup_deploy
cat > /root/.ssh/config <<'X'
Host github.com
  IdentityFile /root/.ssh/hup_deploy
  IdentitiesOnly yes
X
chmod 600 /root/.ssh/config
ssh-keyscan -t ed25519 github.com 2>/dev/null >> /root/.ssh/known_hosts

if ! git ls-remote "$REPO" >/dev/null 2>&1; then
  # Den ÖFFENTLICHEN Schlüssel kurzzeitig im Web anzeigen, damit er fehlerfrei bei GitHub eingetragen werden kann.
  # Er ist nicht geheim. Der private Schlüssel bleibt auf dem Server.
  PUBDIR="$(mktemp -d)"
  cp /root/.ssh/hup_deploy.pub "$PUBDIR/deploy-key.txt"
  (cd "$PUBDIR" && timeout 1800 python3 -m http.server 80 >/dev/null 2>&1) &
  IP="$(curl -fsS -4 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
  echo
  echo "Öffentlicher Schlüssel abrufbar unter:  http://$IP/deploy-key.txt"
  cat /root/.ssh/hup_deploy.pub
  echo
  echo "Warte, bis der Schlüssel bei GitHub als Deploy-Key (nur Lesen) eingetragen ist ..."
  until git ls-remote "$REPO" >/dev/null 2>&1; do sleep 10; done
  pkill -f "python3 -m http.server 80" || true
  rm -rf "$PUBDIR"
  echo "Zugriff auf GitHub funktioniert."
fi

step "7/7 Anwendung holen und starten"
if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" pull --quiet
else
  git clone --quiet "$REPO" "$APP_DIR"
fi
APP_DIR="$APP_DIR" bash "$APP_DIR/deploy/install.sh"

echo
echo "===== Fertig. ====="
echo "Server-IP: $(curl -fsS -4 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
echo "Befragung (nach DNS-Eintrag): https://$DOMAIN/s/referenz"
