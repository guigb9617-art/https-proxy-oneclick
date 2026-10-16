# HTTPS Proxy One-Click 中文使用文档

[English README](README.md)

本项目用于在**全新 Ubuntu/Debian VPS** 上交互式部署 HTTPS 正向代理，采用 **stunnel + Tinyproxy + Certbot**，供 Chrome / ZeroOmega 或支持 HTTPS 代理的命令行工具使用。客户端无需安装 VPN 软件。

> **注意**：这是尚未在全新 VPS 上完成端到端验证的初版脚本。请先在测试机上试运行。**不要在已经安装 Tinyproxy 的服务器上运行**，脚本会主动拒绝覆盖现有配置。

## 一、工作原理

```text
Windows Chrome / ZeroOmega
       │
       │ HTTPS/TLS（用户名和密码）
       ▼
proxy.example.com:9999
       │
       ▼
stunnel（HTTPS 入口，使用 Let's Encrypt 证书）
       │
       ▼
127.0.0.1:9998
       │
       ▼
Tinyproxy（BasicAuth 认证、HTTP CONNECT）
       │
       ▼
目标 HTTPS 网站
```

HTTPS 代理的 TLS 加密用于保护**客户端到 VPS 代理入口**的连接；访问目标 HTTPS 网站时，浏览器还会与目标网站建立独立的 TLS 连接。

## 二、准备条件

- 一台全新的 Ubuntu/Debian VPS，具有 root / sudo 权限，系统使用 systemd。
- 一个可管理 DNS 解析的域名，例如 `proxy.example.com`。
- 为代理域名设置 A 记录，指向 VPS 公网 IPv4 地址。
- 能在域名 DNS 管理后台新增 TXT 记录，用于 Let's Encrypt 的 DNS-01 验证。
- 公网 HTTPS 代理端口（默认 TCP `9999`）可用，云防火墙和系统防火墙允许受信任客户端访问。
- VPS 可正常联网安装 apt 软件包，并能访问 Let's Encrypt。

**不要在已经运行 Tinyproxy 的生产服务器上执行。** 安装脚本会检查端口和现有 Tinyproxy 安装，但它不是升级/迁移工具，也不保证安装失败时自动回滚。

## 三、配置域名 DNS

假设域名为 `example.com`，VPS 公网 IP 为 `203.0.113.10`（示例地址），在 DNS 控制台新增：

| 类型 | 主机记录 | 记录值 |
| --- | --- | --- |
| A | proxy | 203.0.113.10 |

最终使用 `proxy.example.com`。如果使用 Cloudflare，请选择**仅 DNS**，不要开启橙云代理；本项目默认使用自定义 HTTPS 代理端口。

可以在 VPS 上验证：

```bash
getent ahostsv4 proxy.example.com
```

应能看到预期的 VPS IP。

## 四、安装

先阅读 [install.sh](install.sh) 内容，再在**全新 VPS** 上运行：

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/guigb9617-art/https-proxy-oneclick.git
cd https-proxy-oneclick
sudo bash install.sh
```

安装脚本将询问：

| 配置 | 示例 | 说明 |
| --- | --- | --- |
| HTTPS 代理域名 | proxy.example.com | 必须先解析到 VPS |
| 公网 HTTPS 端口 | 9999 | 可自定义，不能被占用 |
| 本地 Tinyproxy 端口 | 9998 | 仅监听 127.0.0.1 |
| 代理用户名 | proxyuser | 自定义 |
| 代理密码 | 自行设置 | 至少 16 位，不含空白字符 |

密码在终端输入时不会回显；**不要把密码、私钥或带有 Proxy-Authorization 的日志发到公开仓库**。

## 五、申请 Let's Encrypt 证书（手动 DNS 验证）

脚本会执行 Certbot，并暂停要求你添加 TXT 记录。例如：

```text
Please deploy a DNS TXT record under the name:
_acme-challenge.proxy.example.com

with the following value:
<本次 Certbot 生成的随机字符串>
```

在 `example.com` 的 DNS 控制台新增：

| 类型 | 主机记录 | 记录值 |
| --- | --- | --- |
| TXT | _acme-challenge.proxy | 本次 Certbot 提示的字符串 |

注意：主机记录一般填写 `_acme-challenge.proxy`，**不要重复拼接根域名**。不同 DNS 控制台可能有不同填写规则。

在**另一个 SSH 会话**中检查：

```bash
nslookup -type=TXT _acme-challenge.proxy.example.com 8.8.8.8
```

确认返回的 TXT 值与**本次正在等待的 Certbot** 提示完全一致，再回到 Certbot 按 Enter。

如果 Certbot 已失败退出，重新运行会生成新的 TXT 值；不能直接复用旧值。

## 六、验证服务

在 VPS 上检查：

```bash
systemctl status tinyproxy --no-pager
systemctl status https-forward-proxy --no-pager
ss -lntp | grep -E ':9998 |:9999 '
```

在 Windows CMD 中测试（将域名和用户名换成实际值）：

```cmd
curl.exe -sS -L --max-time 30 --proxy https://proxy.example.com:9999 -U proxyuser -o NUL -w "HTTP: %{http_code}\n" https://www.google.com/
```

输入密码后，目标网站正常响应时通常显示：

```text
HTTP: 200
```

**不要加 `--proxy-insecure`**；正式证书应该通过系统信任链验证。

## 七、Chrome / ZeroOmega 配置

创建一个代理情景模式，设置：

| 选项 | 内容 |
| --- | --- |
| 代理协议 | **HTTPS**（不是 HTTP） |
| 代理服务器 | proxy.example.com |
| 端口 | 9999 |
| 用户名 | 安装时填写的代理用户名 |
| 密码 | 安装时设置的密码 |

保存设置，点击「应用选项」，在扩展图标中选择该情景模式，再测试 Google。部分浏览器扩展版本的代理认证支持方式可能不同，若出现认证窗口，按提示输入账号密码。

## 八、常用维护命令

```bash
# 查看状态
sudo systemctl status tinyproxy https-forward-proxy --no-pager

# 查看 HTTPS 入口日志
sudo journalctl -u https-forward-proxy -n 50 --no-pager

# 重启代理
sudo systemctl restart tinyproxy https-forward-proxy

# 查看证书
sudo certbot certificates
```

## 九、证书续期：当前版本需要手动操作

**重要：本项目使用 Certbot 手动 DNS-01 验证，不能自动续期。**

请在证书到期前手动执行（将域名替换为实际域名）：

```bash
sudo certbot certonly --manual --preferred-challenges dns --cert-name proxy.example.com -d proxy.example.com --force-renewal
sudo systemctl restart https-forward-proxy
```

根据新的 TXT 挑战值更新 DNS，确认生效后再按 Enter。证书续期成功后重启 stunnel 服务使其加载新证书。

脚本虽然创建了证书部署后的服务重启钩子，但**这不代表手动 DNS 证书能够自动续期**。如需无人值守续期，必须额外实现并验证 DNS 服务商 API 插件或认证钩子。

## 十、安全注意事项与常见问题

- **公网代理可能被扫描或滥用。** 请使用强密码，尽可能在防火墙中限制来源 IP，并监控流量与日志。
- Tinyproxy 账号密码保存在服务器本地配置文件中，脚本将其设为仅 root 可读；请妥善保护 VPS。
- 证书私钥位于 `/etc/letsencrypt/live/...`，**不得上传 GitHub**。
- Windows 报 `curl: (60)`：检查域名是否匹配证书、证书链是否有效、是否误用 IP 连接。
- Windows 报 `curl: (28)`：检查 DNS、端口监听及防火墙。
- Windows 报 `curl: (56)`：检查服务日志、TLS 协议以及链路是否被重置。
- 收到 `HTTP 407`：检查代理用户名和密码。
- DNS TXT 返回 `NXDOMAIN`：确认记录保存到正确 DNS 区域、主机记录没有重复域名、等待公共 DNS 可查询后再继续。

## 十一、项目文件

```text
https-proxy-oneclick/
├── install.sh       # 交互式安装脚本
├── README.md        # 英文文档
├── README.zh-CN.md  # 本中文文档
├── LICENSE          # MIT 许可证
└── .gitignore
```

## 许可证

MIT。项目仍处于初版阶段，建议先在测试 VPS 上完成端到端验证，再用于正式环境。
