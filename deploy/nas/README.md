# nanoMuse 家庭 NAS 部署草案

此目录在 rontian/nanoMuse Fork 中，仅保存 Compose、示例配置和运维脚本。无论更新源码还是重建容器，均不应该影响实际私有数据。尚未在 NAS 上执行部署验证。

## 1. NAS 目录（唯一推荐布局）

```text
/volume1/docker/nanoMuse/
├── source/                           # Git clone rontian/nanoMuse
│   ├── cloud/                        # Relay 源码
│   └── deploy/nas/                   # 本部署目录
├── config/                           # 私有配置，位于 Git 之外
│   ├── .env                          # Compose 插值路径/端口
│   ├── relay.env                     # 邮箱白名单、模型网关、密钥
│   ├── runtime-1.env                 # 可选，用户 1
│   └── runtime-2.env                 # 可选，用户 2
├── data/                             # 持久化文件，位于 Git 之外
│   ├── relay/cloud.db                # Relay SQLite, UID 10001
│   └── runtimes/
│       ├── user-1/
│       │   ├── data/                 # Agent Memory / 会话 / Token
│       │   └── workspace/            # 用户 1 文件
│       └── user-2/
│           ├── data/
│           └── workspace/
└── backups/
    ├── relay/
    ├── runtime-1/
    └── runtime-2/
```

`source` 目录名称可以自行更改成 `repo`、`src` 等，Compose 中 `../../cloud` 相对其所在的 `deploy/nas/compose.yaml` 解析，不依赖仓库文件夹的绝对名称。Linux 区分 `nanoMuse` 与 `nanomuse` 大小写。

不要将 `config`、`data`、`backups` 放进仓库；不要挂载整个 NAS 根目录或 Docker Socket 给任何 Agent。

## 2. 初始化（示例，不自动部署）

```bash
ROOT=/volume1/docker/nanoMuse
mkdir -p "$ROOT"
git clone https://github.com/rontian/nanoMuse.git "$ROOT/source"
# 此部署目录未合并主分支时，先切换到 Draft PR 分支：
git -C "$ROOT/source" switch chore/nas-deploy-scaffold-20261024

mkdir -p "$ROOT/config" "$ROOT/data/relay" "$ROOT/backups/"{relay,runtime-1,runtime-2}
mkdir -p "$ROOT/data/runtimes/user-1/"{data,workspace}
mkdir -p "$ROOT/data/runtimes/user-2/"{data,workspace}

cp "$ROOT/source/deploy/nas/.env.example" "$ROOT/config/.env"
cp "$ROOT/source/deploy/nas/relay.env.example" "$ROOT/config/relay.env"
# 启用对应 Runtime 之前再复制下两份并设不同 Token：
cp "$ROOT/source/deploy/nas/runtime.env.example" "$ROOT/config/runtime-1.env"
cp "$ROOT/source/deploy/nas/runtime.env.example" "$ROOT/config/runtime-2.env"

chmod 700 "$ROOT/config" "$ROOT/backups"
chmod 600 "$ROOT/config/"*.env
sudo chown 10001:10001 "$ROOT/data/relay"
sudo chown -R 1000:1000 "$ROOT/data/runtimes"
```

请根据 NAS 实际安装环境检查 `chown` / ACL / Docker 权限。所有 `REPLACE` 占位符需先编辑，不要将真实 Token 提交到公开仓库。

## 3. 家庭 Relay

Relay 从本 Fork 的 `cloud/Dockerfile` 构建；上游尚未核实存在可直接拉取的独立 Relay 镜像。配置存放在外部 `config/relay.env`：

- `PUBLIC_BASE=https://muse.rontian.top`。
- `SIGNUP_OPEN=0`，`ALLOWED_IDENTIFIERS` 在私有文件中设置为预定的两位家庭用户邮箱（不公开提交）。
- `CLOUD_SECRET`、`CLOUD_ADMIN_TOKEN` 分别使用不同的 `openssl rand -hex 32` 随机值。
- `UPSTREAM_BASE`、`UPSTREAM_KEY` 只接一个已经验证的 Magpie 或 CLIProxyAPI 上游。
- 替换 `CLOUD_MODELS` 占位模型 ID，确认代理支持；`IMPROVE_DEFAULT=0`、`CLOUD_ANY_MODEL_MEMBERS=0`。
- `CODE_SENDER=log` 仅用于 LAN 验证；长期部署时设置 `CODE_SENDER=smtp` 并保证白名单邮箱真实可收取验证码。

检查、构建和选择性启动：

```bash
ROOT=/volume1/docker/nanoMuse
docker compose --env-file "$ROOT/config/.env" -f "$ROOT/source/deploy/nas/compose.yaml" config
docker compose --env-file "$ROOT/config/.env" -f "$ROOT/source/deploy/nas/compose.yaml" build relay
# 审核完成后才手动执行：
# docker compose --env-file "$ROOT/config/.env" -f "$ROOT/source/deploy/nas/compose.yaml" up -d relay
```

Relay 容器 `8787` → NAS 宿主机 `127.0.0.1:8787`，由 NPS 向 VPS Nginx 转发。如果 NPC/NPS 客户端运行在独立容器内，不能假设 NAS Host 的 `127.0.0.1` 可访问，需选择受防火墙保护的 NAS IP。

## 4. 两个 Runtime，默认不部署

Runtime 直接使用官方 `ghcr.io/nano-muse/nanomuse:1.0.5` 镜像（上线前确认实际版本）。两个服务在 `compose.runtime.yaml` 中使用不同的 Compose profiles，普通 Relay 部署不会启动它们。

| 服务 | NAS 宿主机端口 | 配置（仓库外） | 持久化（仓库外） |
| --- | --- | --- | --- |
| `runtime-1` | `127.0.0.1:8788` | `config/runtime-1.env` | `data/runtimes/user-1/` |
| `runtime-2` | `127.0.0.1:8789` | `config/runtime-2.env` | `data/runtimes/user-2/` |

单独启用第一个实例：

```bash
ROOT=/volume1/docker/nanoMuse
docker compose --env-file "$ROOT/config/.env" \
  -f "$ROOT/source/deploy/nas/compose.yaml" \
  -f "$ROOT/source/deploy/nas/compose.runtime.yaml" \
  --profile runtime-1 up -d runtime-1
# 第二位用户使用 --profile runtime-2 up -d runtime-2
```

**如何给用户分配 Runtime？** 当前 Relay 管理后台没有原生的“账号自动绑定 Runtime”选项。管理员创建独立容器及其独立的 `NANOMUSE_SERVER_TOKEN`、数据卷和工作空间；用户通过私有 LAN/VPN 入口访问该 Runtime Web（使用实例自己的 Token），然后在 Runtime Web 内用**自己的白名单 Relay 账号**登录。确认 Hub 中显示独立设备后，iPhone/Mac 即可在同一账号下选择该执行节点。`NANOMUSE_CLOUD_BASE_URL` 仅指定 Relay 地址，**不能自动完成账号登录**。

绝不能共享两个用户的 Runtime Token、容器或数据目录；Runtime Web 的高权限 API 不得未经额外访问控制公开暴露。普通手机或 Mac 通过 Relay Hub 远程调用 Runtime 时，**不需要开放 Runtime Web 域名**。

## 5. 域名、NPS 映射与仓库责任

VPS Nginx 的虚拟主机只放在私有 `rontian/os_nginx_vhost` 中，不在本 Fork 重复维护：

| 公网域名 | VPS Nginx 代理 NPS 本地端口 | NAS 端口 | 默认状态 |
| --- | --- | --- | --- |
| `muse.rontian.top` | `127.0.0.1:23426` | `8787` | Relay 预备上线 |
| `agent1.muse.rontian.top` | `127.0.0.1:23427` | `8788` | Nginx 模板禁用 |
| `agent2.muse.rontian.top` | `127.0.0.1:23428` | `8789` | Nginx 模板禁用 |

这是**候选端口规划**，实际 VPS/NPS 端口占用尚未检验。NPS TCP 端口应仅供 VPS 本机 Nginx 使用，避免公网直连；两个 Runtime 的 Nginx 配置先以 `.conf.disabled` 留存，确保默认不被加载。TLS、WSS `/v1/hub`、反向代理转发、管理员访问限制由 VPS Nginx 负责。

## 6. 备份与升级

```bash
bash /volume1/docker/nanoMuse/source/deploy/nas/scripts/backup-relay.sh
# 若更换根目录：
# NANOMUSE_DEPLOY_ENV_FILE=/other/config/.env bash /other/source/deploy/nas/scripts/backup-relay.sh
```

脚本在运行中的容器内调用 SQLite 在线 Backup API，并把 `cloud.db` 和 `relay.env` 一起保存到外部 `backups/relay/`。其中含密钥，**异地备份前必须加密**。恢复时须同时恢复配套的 `CLOUD_SECRET` 与数据库；不能直接 `cp` 使用 WAL 的 `cloud.db`。Runtime 的 `data` 与 `workspace` 也要分别备份。

正式上线前要验证登录、SMTP、模型、白名单拒绝、账号隔离、会话同步、WebSocket、Hub、Runtime 授权、备份与恢复。升级需要固定 Fork commit 和镜像版本，并为数据库前向迁移准备配套回退快照。

## 参考资料与许可

- [自建 Relay](https://github.com/nano-muse/nanoMuse/blob/main/docs/self-hosting.md)
- [Agent Runtime Docker](https://github.com/nano-muse/nanoMuse/blob/main/docs/deployment.md)
- [GPL-3.0-or-later](https://github.com/nano-muse/nanoMuse/blob/main/LICENSE)

本目录不包含对上游应用源码的功能修改；自建镜像或分发时遵守许可证。
