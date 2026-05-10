# Hermes + Railway + Hermes Web UI（单服务方案）

这套文件是给 **Railway 上已经在跑 Hermes 的同一个 service** 用的。

## 为什么不是单独新建一个 Railway service？

我检查了 `hermes-web-ui` 的实现后，发现它不仅代理 Hermes gateway，还会：

- 直接调用本地 `hermes` CLI
- 直接读本地 sessions / logs / profiles / config
- 依赖本地持久化数据目录

而 Railway 的 volume 是 **按 service 隔离** 的。

所以如果把 `hermes-web-ui` 放到一个完全独立的新 service：

- 它看不到你当前 Hermes service 的本地状态
- sessions / logs / profiles / memory 会不一致
- 很多 dashboard 功能会残缺

**结论：Railway 上最合适的是“同一个 service 内同时跑 gateway + web UI”，再由一个公共端口反代：**

- `/telegram` -> Hermes gateway (`127.0.0.1:8642`)
- 其他路径 -> Hermes Web UI (`127.0.0.1:8648`)

---

## 目录说明

- `Dockerfile`：替换你 repo 根目录里的 Dockerfile
- `railway.json`：替换你 repo 根目录里的 railway.json
- `scripts/railway-start-webui.sh`：Railway 启动脚本
- `scripts/railway-webui-proxy.mjs`：公共入口反向代理

---

## 这个方案做了什么

1. 安装 Node 24
2. 安装 `hermes-web-ui`
3. Hermes gateway 继续跑在内部 `8642`
4. Hermes Web UI 跑在内部 `8648`
5. Railway 暴露的 `$PORT` 由一个轻量代理接管：
   - `/telegram` 转发到 gateway
   - 其它请求全部转发到 web UI
6. 把 `HOME` 对齐到 `HERMES_HOME`，并创建 `.hermes -> /opt/data` 的兼容链接，避免 web UI 找不到 Hermes 数据目录

---

## Railway 里需要的环境变量

至少保留你现在 Hermes 已经在用的：

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ALLOWED_USERS`
- `TELEGRAM_WEBHOOK_SECRET`
- `HERMES_MODEL`
- `HERMES_MODEL_PROVIDER`
- 以及你当前 provider 需要的 API key

建议新增：

- `HERMES_WEBUI_AUTH_TOKEN=<你自定义的长随机字符串>`

如果不设置 `HERMES_WEBUI_AUTH_TOKEN`，Web UI 会自己生成 token，并写到：

- `/opt/data/.hermes-web-ui/.token`

---

## Railway 部署步骤

1. 用这个目录里的文件替换你仓库对应文件
2. 推送到 GitHub
3. 等 Railway 自动重新部署
4. 部署成功后访问：
   - `https://你的域名/`
5. 如果设置了 `HERMES_WEBUI_AUTH_TOKEN`，打开：
   - `https://你的域名/#/?token=你的token`
6. Telegram webhook 仍然继续走：
   - `https://你的域名/telegram`

---

## 登录后怎么用

- **Chat**：网页里直接聊天
- **Sessions**：查看历史会话
- **Jobs**：管理 cron/scheduled jobs
- **Profiles**：管理 Hermes profiles
- **Logs**：看 gateway / agent 日志
- **Settings**：改模型、显示、内存、平台设置
- **Terminal**：网页终端

---

## 故障排查

### Web UI 打不开
看 Railway logs，重点查：

- `railway-webui.log`
- `railway-gateway.log`

### `/telegram` 不工作
确认：

- `TELEGRAM_WEBHOOK_SECRET` 已设置
- `TELEGRAM_WEBHOOK_URL` 最终是 `https://你的域名/telegram`
- Railway 公开域名是当前 service 的域名

### 打开页面后提示未授权
检查：

- URL 里是否带了 `#/?token=...`
- 或者你是否已经在 Web UI 里设置了用户名/密码登录

---

## 重要说明

这个目录里的文件是我根据你当前 Railway 部署结构和 `hermes-web-ui` 源码行为整理出的 **可落地方案**。

和我前面口头建议的“单独新 service”相比，**这是修正后的更靠谱版本**：

> 在 Railway 上，Hermes Web UI 更适合同一个 service 内部署，而不是拆出去单独一个 service。
