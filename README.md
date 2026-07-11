# Mihomo Proxy V2.0

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
├── run.sh                       # ★ 交互式部署向导
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
├── subconverter/
│   ├── base/
│   │   └── pref.toml         # SubConverter-Extended 配置
│   └── stats/
└── scripts/
    ├── apply-config.sh          # ★ 渲染模板 → 生成 config.yaml
    ├── generate-secret.sh
    ├── backup.sh
    ├── restore.sh
    └── update.sh
```

---

## 端口规划

| 功能         | 端口  |
|--------------|-------|
| Mixed        | 9070  |
| SOCKS5       | 9071  |
| HTTP         | 9072  |
| API          | 9073  |
| Dashboard    | 9075  |
| DNS          | 1053  |
| SubConverter | 25500 |

---

## 首次部署

### 1. 上传项目到路由器

```sh
scp -r ./mihomo root@192.168.1.1:/opt/mihomo
ssh root@192.168.1.1
```

### 2. 运行部署向导

```sh
cd /opt/mihomo
sh run.sh
```

`run.sh` 会依次：询问订阅链接（`.env` 已填就跳过）→ 确认/修改 `HOST_IP` → 自动生成 Secret（已存在就跳过）→ 调用 `apply-config.sh` 渲染 `config/config.yaml` → 打印 Zashboard / API / SubConverter 面板地址和 Secret → 询问是否立即 `docker compose up -d`。

不想用向导，也可以手动分步执行，见下方「手动分步操作」。

### 3. 访问 Dashboard

浏览器打开：`http://192.168.1.1:9075`

首次连接填入：
- API 地址：`http://192.168.1.1:9073`
- Secret：`.env` 文件中 `SECRET=` 的值

---

## 手动分步操作

不想用 `run.sh` 向导，也可以自己分步执行：

### 1. 编辑 .env 文件

```sh
vi /opt/mihomo/.env
```

需要填写的两项：

```env
# 你的原始订阅链接（V2Ray / SS / Trojan / VMess 等均可）
# 如果链接本身包含 & ? = # 等特殊字符，需要用英文双引号包起来
SUBSCRIPTION_URL=https://你的订阅链接

# Secret 暂时留空，下一步自动生成
SECRET=
```

订阅转换统一走本地自建的 SubConverter-Extended（`subconverter` 容器），不需要额外配置。

### 2. 生成 Secret

```sh
cd /opt/mihomo
sh scripts/generate-secret.sh
```

### 3. 生成配置文件

```sh
sh scripts/apply-config.sh
```

此步骤读取 `.env` 中的订阅链接和 Secret，渲染成 `config/config.yaml`。

### 4. 启动服务

```sh
docker compose up -d
```

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

## 订阅转换说明

`apply-config.sh` 处理 `SUBSCRIPTION_URL` 时分两种情况：

1. **内容本身是 Mihomo 可用格式**（含 `proxies:` 字段）→ 直接使用原链接，Mihomo 自己定期刷新，节点始终最新。
2. **内容不是 Mihomo 可用格式**（比如常见的 base64 节点链接列表）→ 脚本自己解码、拆出节点链接，交给本地 `subconverter` 容器（SubConverter-Extended）转换成节点列表写入 `config.yaml`。

第 2 种情况生成的是**运行脚本那一刻的静态快照**：SubConverter-Extended 出于反屏蔽考虑，设计上不会主动连接远程订阅服务器，所以没法像传统 subconverter 后端那样"实时"转换。机场后台更换节点后，需要手动重新执行 `sh scripts/update.sh`（或 `apply-config.sh` + 重启 mihomo）才能同步。

SubConverter-Extended 默认开启了运行仪表盘（`statistics.enabled = true`），可访问 `http://192.168.1.1:25500/dashboard` 查看转换统计（首次启动/首次转换耗时略长属正常现象）。统计数据持久化在 `subconverter/stats/`，仅内网访问，未开启 Basic Auth。

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

- 检查 `.env` 中 `SUBSCRIPTION_URL` 是否正确、是否需要用双引号包起来（见上方说明）
- 确认 `subconverter` 容器已启动：`docker compose ps`，未启动则 `apply-config.sh` 会直接报错退出
- 在浏览器中测试最终链接是否可访问：
  查看 `config/config.yaml` 中 `proxy-providers.subscription.url` 的值，在浏览器打开
- 重新运行 `sh scripts/apply-config.sh`，观察终端输出的解析节点数量和转换结果

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
| `SUBSCRIPTION_URL` | 原始订阅链接，含特殊字符需加双引号 | _(必填)_ |
| `SUBCONVERTER_PORT` | 本地 SubConverter-Extended 监听端口 | `25500` |
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
