# HTTPS Proxy One-Click

**[简体中文文档 / Chinese Guide](README.zh-CN.md)**

An interactive installer for an **HTTPS forward proxy** on Ubuntu/Debian: stunnel (TLS) → Tinyproxy (BasicAuth + CONNECT) → HTTPS sites.

## Features
- HTTPS proxy for Chrome / ZeroOmega / curl; no local VPN client required
- Let's Encrypt trusted TLS certificate using manual DNS-01 TXT verification
- Configurable hostname, ports, username and password
- systemd service, configuration backup and port checks
- Refuses to modify a server where Tinyproxy is already installed

## Architecture

```text
Chrome / ZeroOmega
  └─ HTTPS/TLS → proxy.example.com:9999 (stunnel)
                    └─ 127.0.0.1:9998 (Tinyproxy + BasicAuth)
                         └─ HTTPS websites
```

## Requirements
Fresh Ubuntu/Debian VPS with systemd and root access, DNS A record for your domain pointing to the VPS, and ability to add TXT records at the DNS provider. TCP 9999 must be allowed by your provider firewall. **Do not run this on your already-configured Tinyproxy VPS.**

## Install

Inspect the script first, then:

```bash
sudo bash install.sh
```

Enter domain, ports and credentials. Certbot will pause to display a TXT challenge. For `proxy.example.com` in zone `example.com`, add a TXT record named `_acme-challenge.proxy` with the **current Certbot token**. Verify the TXT record is visible on public DNS before pressing Enter.

## Verify from Windows

```cmd
curl.exe -sS -L --max-time 30 --proxy https://proxy.example.com:9999 -U proxyuser -o NUL -w "HTTP: %{http_code}\n" https://www.google.com/
```

Expect `HTTP: 200` when Google responds normally. Do not use `--proxy-insecure` in production. In ZeroOmega choose HTTPS, the hostname, port and proxy credentials.

## Service management

```bash
systemctl status https-forward-proxy
systemctl status tinyproxy
journalctl -u https-forward-proxy -n 50 --no-pager
```

## Certificate renewal (manual)

**Manual DNS-01 issuance does NOT automatically renew.** Before expiry, run:

```bash
sudo certbot certonly --manual --preferred-challenges dns --cert-name proxy.example.com -d proxy.example.com --force-renewal
sudo systemctl restart https-forward-proxy
```

Add the newly requested TXT token and verify it before pressing Enter. Unattended renewal requires a DNS API integration, which this project does not yet implement.

## Security and limitations
- Public proxies attract abuse. Use a strong unique password and monitor logs.
- Credentials are stored in a root-readable Tinyproxy config; TLS protects them in transit.
- Never commit passwords, DNS API tokens or private keys.
- The installer is for **fresh VPS only**, and is an initial release not yet tested end-to-end on a disposable VPS.
- Existing Nginx/V2Ray configurations are not intentionally modified, but installing Tinyproxy changes system services; use a clean server.
- Certificate issuance needs interactive DNS validation; firewall changes are not automated.

## License
MIT.
