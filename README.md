# Mihomo Proxy V1.0

基于 Docker Compose 部署在 OpenWrt (x86_x64) 上的 Mihomo 代理服务器。

- 模式：代理服务器（Mixed / SOCKS5 / HTTP）
- 无 TUN / 无 TProxy / 不修改路由表
- Web 管理：Zashboard
- DNS：Fake-IP，支持 Windows AD 域环境（moolo.net → 192.168.1.3，请在**config.yaml.template**修改为自己的域名和域控DNS）

---

## 目录结构

```text
/opt/mihomo
├── .env                         # ★ 所有配置都在这里编辑
├── compose.yaml
├── backup/
├── cache/
├── config/
│   ├── config.yaml              # 自动生成，不要手动编辑
│   └── config.yaml.template     # 配置模板
├── dashboard/
├── logs/
├── providers/
│   ├── proxy/
│   └── ruleset/
└── scripts/
    ├── apply-config.sh          # ★ 渲染模板 → 生成 config.yaml
    ├── generate-secret.sh
    ├── backup.sh
    ├── restore.sh
    └── update.sh
```

---

## 端口规划

| 功能      | 端口 |
|-----------|------|
| Mixed     | 9070 |
| SOCKS5    | 9071 |
| HTTP      | 9072 |
| API       | 9073 |
| Dashboard | 9075 |
| DNS       | 1053 |

---

## 首次部署

### 1. 上传项目到路由器

```sh
scp -r ./mihomo root@192.168.1.1:/opt/mihomo
ssh root@192.168.1.1
```

### 2. 编辑 .env 文件

```sh
vi /opt/mihomo/.env
```

需要填写的三项：

```env
# 你的原始订阅链接（V2Ray / SS / Trojan / VMess 等均可）
SUBSCRIPTION_URL=https://你的订阅链接

# subconverter 公共后端（默认即可，也可填自建地址）
SUBCONVERTER_URL=https://sub.xeton.dev

# Secret 暂时留空，下一步自动生成
SECRET=
```

### 3. 生成 Secret

```sh
cd /opt/mihomo
sh scripts/generate-secret.sh
```

### 4. 生成配置文件

```sh
sh scripts/apply-config.sh
```

此步骤读取 `.env` 中的订阅链接和 Secret，渲染成 `config/config.yaml`。

### 5. 启动服务

```sh
docker compose up -d
```

### 6. 访问 Dashboard

浏览器打开：`http://192.168.1.1:9075`

首次连接填入：
- API 地址：`http://192.168.1.1:9073`
- Secret：`.env` 文件中 `SECRET=` 的值

---

## 客户端使用

在需要使用代理的设备上，配置以下任一代理地址：

| 类型   | 地址        | 端口 |
|--------|-------------|------|
| Mixed  | 192.168.1.1 | 9070 |
| SOCKS5 | 192.168.1.1 | 9071 |
| HTTP   | 192.168.1.1 | 9072 |

DNS（可选）：`192.168.1.1:1053`（Fake-IP 模式）

---

## 更换订阅链接

1. 编辑 `.env`，修改 `SUBSCRIPTION_URL=` 的值
2. 重新生成配置并重启：

```sh
cd /opt/mihomo
sh scripts/apply-config.sh
docker compose restart mihomo
```

或一步完成（同时检查镜像更新）：

```sh
sh scripts/update.sh
```

---

## 升级镜像

```sh
cd /opt/mihomo
sh scripts/update.sh
```

脚本会依次：重新渲染配置 → `docker compose pull` → `docker compose up -d`

---

## 备份

```sh
cd /opt/mihomo
sh scripts/backup.sh
```

备份内容：`config/`（含模板）、`providers/`、`.env`
保留最新 5 个，命名：`mihomo_backup_YYYYMMDD_HHMMSS.tar.gz`

---

## 恢复

```sh
cd /opt/mihomo

# 恢复最新备份
sh scripts/restore.sh

# 恢复指定备份
sh scripts/restore.sh backup/mihomo_backup_20250101_120000.tar.gz
```

恢复后启动：

```sh
sh scripts/apply-config.sh
docker compose up -d
```

---

## 迁移到新服务器

```sh
# 旧机器备份
sh /opt/mihomo/scripts/backup.sh

# 复制整个目录到新机器
scp -r /opt/mihomo root@新服务器IP:/opt/mihomo

# 新机器上启动
ssh root@新服务器IP
cd /opt/mihomo
sh scripts/apply-config.sh
docker compose up -d
```

---

## 故障排查

### 查看日志

```sh
docker compose logs -f mihomo
docker compose logs -f zashboard
```

### 检查容器状态

```sh
docker compose ps
```

### Mihomo 启动失败

- 检查 `config/config.yaml` 是否存在（需先运行 `apply-config.sh`）
- YAML 格式错误：`cat config/config.yaml` 检查内容
- 端口占用：`ss -tlnp | grep 9070`

### 订阅拉取失败

- 检查 `.env` 中 `SUBSCRIPTION_URL` 是否正确
- 在浏览器中测试转换 URL 是否可访问：
  查看 `config/config.yaml` 中 `proxy-providers.subscription.url` 的值，在浏览器打开
- 可尝试更换 `SUBCONVERTER_URL` 为其他公共后端：
  - `https://api.v1.mk`
  - `https://sub.mi200.top`

### Secret 重置

```sh
sh scripts/generate-secret.sh
sh scripts/apply-config.sh
docker compose restart mihomo
```

---

## .env 配置项说明

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `SUBSCRIPTION_URL` | 原始订阅链接 | _(必填)_ |
| `SUBCONVERTER_URL` | subconverter 后端地址 | `https://sub.xeton.dev` |
| `SECRET` | Dashboard/API 认证密钥 | _(由脚本生成)_ |
| `HOST_IP` | 本机 IP | `192.168.1.1` |
| `CHINA_DNS` | 国内/域控 DNS | `192.168.1.3` |
| `FOREIGN_DOH` | 国外 DoH 主 | `https://1.1.1.1/dns-query` |
| `FOREIGN_DOH_FALLBACK` | 国外 DoH 备 | `https://dns.google/dns-query` |

---

## 策略组说明

| 策略组 | 说明 |
|--------|------|
| 🚀 节点选择 | 手动选择节点 |
| ♻ 自动选择 | 延迟最低节点（自动测速） |
| 🎯 全球直连 | 直连，不走代理 |
| 🤖 OpenAI | ChatGPT / OpenAI |
| 📦 GitHub | GitHub |
| 🍎 Apple | Apple 服务 |
| Ⓜ Microsoft | 微软服务 |
| 📨 Telegram | Telegram |
| 🌍 国外网站 | 通用国外流量 |
| 🐟 漏网之鱼 | 兜底规则 |

默认各应用组均引用「🚀 节点选择」，在 Dashboard 中可单独调整。

---

## 项目原则

1. 不启用 TUN
2. 不修改 OpenWrt 路由
3. 所有配置集中在 `.env`，`config.yaml` 自动生成
4. 使用官方推荐配置 + MetaCubeX 官方规则集
5. 长期维护优先，迁移友好
