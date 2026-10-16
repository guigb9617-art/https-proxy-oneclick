#!/usr/bin/env bash
set -Eeuo pipefail
# Fresh Ubuntu/Debian VPS only. Certbot manual DNS-01: NOT auto-renewed.
log(){ printf '\n[INFO] %s\n' "$*"; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
[[ ${EUID} -eq 0 ]] || die "Run as root: sudo bash install.sh"
for c in apt-get systemctl ss python3 dpkg-query; do command -v "$c" >/dev/null || die "Missing: $c"; done
if dpkg-query -W -f='${Status}' tinyproxy 2>/dev/null | grep -qx 'install ok installed'; then
  die "Tinyproxy already installed; refusing to overwrite existing configuration."
fi
systemctl cat https-forward-proxy.service >/dev/null 2>&1 && die "Service already exists"
read -r -p 'HTTPS proxy domain (e.g. proxy.example.com): ' DOMAIN
DOMAIN=${DOMAIN,,}
[[ $DOMAIN =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ && $DOMAIN == *.* ]] || die "Invalid domain"
read -r -p 'Public HTTPS port [9999]: ' PUBLIC_PORT; PUBLIC_PORT=${PUBLIC_PORT:-9999}
read -r -p 'Local Tinyproxy port [9998]: ' LOCAL_PORT; LOCAL_PORT=${LOCAL_PORT:-9998}
for p in "$PUBLIC_PORT" "$LOCAL_PORT"; do
  [[ $p =~ ^[0-9]+$ ]] && (( p>=1024 && p<=65535 )) || die "Invalid port: $p"
  ss -H -ltn "( sport = :$p )" | grep -q . && die "Port $p already in use"
done
[[ $PUBLIC_PORT != "$LOCAL_PORT" ]] || die "Ports must differ"
read -r -p 'Proxy username [proxyuser]: ' PROXY_USER; PROXY_USER=${PROXY_USER:-proxyuser}
[[ $PROXY_USER =~ ^[a-zA-Z0-9_-]{3,32}$ ]] || die "Invalid username"
read -r -s -p 'Proxy password (min 16 chars; hidden): ' PROXY_PASS; printf '\n'
[[ ${#PROXY_PASS} -ge 16 && $PROXY_PASS != *' '* && $PROXY_PASS != *$'\t'* ]] || die "Password must be >=16 characters without whitespace"
printf '\nDomain: %s\nPublic port: %s\nLocal port: %s\nUser: %s\n' "$DOMAIN" "$PUBLIC_PORT" "$LOCAL_PORT" "$PROXY_USER"
printf 'DNS A record must point the domain to this VPS. DNS TXT validation will be interactive.\n'
read -r -p 'Proceed on a FRESH VPS? [y/N] ' YES
[[ $YES == y || $YES == Y ]] || exit 0
log "Installing packages"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y tinyproxy stunnel4 certbot curl dnsutils ca-certificates
for p in "$PUBLIC_PORT" "$LOCAL_PORT"; do
  ss -H -ltn "( sport = :$p )" | grep -q . && die "Port $p became occupied; stopping"
done
log "Requesting certificate. Add DNS TXT record and verify it before pressing Enter."
certbot certonly --manual --preferred-challenges dns -d "$DOMAIN"
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
[[ -s "$CERT_DIR/fullchain.pem" && -s "$CERT_DIR/privkey.pem" ]] || die "Certificate missing"
mkdir -p /etc/https-forward-proxy
chmod 700 /etc/https-forward-proxy
BASE=/etc/tinyproxy/tinyproxy.conf
[[ -f $BASE ]] || die "Tinyproxy configuration missing"
cp -a "$BASE" "/etc/https-forward-proxy/tinyproxy.original.$(date +%Y%m%d%H%M%S)"
export LOCAL_PORT PROXY_USER PROXY_PASS
python3 - <<'PY'
import os
p='/etc/tinyproxy/tinyproxy.conf'
with open(p) as f: lines=f.readlines()
remove={'Port','Listen','BasicAuth','Allow','Deny','ConnectPort'}
lines=[line for line in lines if not (line.strip() and not line.lstrip().startswith('#') and line.split(None,1)[0] in remove)]
lines += ['\n# https-proxy-oneclick\n', 'Port '+os.environ['LOCAL_PORT']+'\n', 'Listen 127.0.0.1\n', 'ConnectPort 443\n', 'BasicAuth '+os.environ['PROXY_USER']+' '+os.environ['PROXY_PASS']+'\n']
with open(p,'w') as f:f.writelines(lines)
PY
chmod 600 "$BASE"
unset PROXY_PASS
cat > /etc/https-forward-proxy/stunnel.conf <<EOF
foreground = yes
client = no
sslVersionMin = TLSv1.2
[https-forward-proxy]
accept = 0.0.0.0:$PUBLIC_PORT
connect = 127.0.0.1:$LOCAL_PORT
cert = $CERT_DIR/fullchain.pem
key = $CERT_DIR/privkey.pem
EOF
chmod 600 /etc/https-forward-proxy/stunnel.conf
cat > /etc/systemd/system/https-forward-proxy.service <<'EOF'
[Unit]
Description=HTTPS Forward Proxy (stunnel -> Tinyproxy)
After=network-online.target tinyproxy.service
Wants=network-online.target
Requires=tinyproxy.service
[Service]
Type=simple
ExecStart=/usr/bin/stunnel /etc/https-forward-proxy/stunnel.conf
Restart=on-failure
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable tinyproxy
systemctl restart tinyproxy
systemctl enable --now https-forward-proxy.service
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/restart-https-forward-proxy.sh <<'EOF'
#!/usr/bin/env bash
set -e
systemctl try-restart https-forward-proxy.service
EOF
chmod 750 /etc/letsencrypt/renewal-hooks/deploy/restart-https-forward-proxy.sh
log "Installation complete: https://$DOMAIN:$PUBLIC_PORT"
printf 'Windows test: curl.exe -sS -L --max-time 30 --proxy https://%s:%s -U %s -o NUL -w "HTTP: %%{http_code}\\n" https://www.google.com/\n' "$DOMAIN" "$PUBLIC_PORT" "$PROXY_USER"
printf 'IMPORTANT: Manual DNS certificates DO NOT AUTO-RENEW. See README.\n'
