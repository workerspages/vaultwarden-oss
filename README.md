# vaultwarden - S3/WebDAV 数据持久化版

基于 vaultwarden 官方镜像，支持将数据**加密**后自动同步到 **S3 存储桶** 或 **WebDAV 网盘**，特别适用于没有持久化存储卷的云服务、PaaS 平台。本项目默认开启了双架构（`linux/amd64`, `linux/arm64`）支持。

## 💡 工作原理

```text
容器启动 → 从 S3/WebDAV 恢复数据 → 启动 vaultwarden 服务 → 后台每 N 分钟自动备份数据到远端
```

1. **启动时恢复**: 容器启动阶段，使用 `rclone copy` 优先从远端拉取历史备份到本地 `/data/` 目录。
2. **定时备份**: 通过后台常驻脚本循环 `rclone sync`，单向将本地变化的数据同步到远端网盘。
3. **数据加密**: 可选 AES-256 高强度加密，实现文件名及文件内容的完全加密后再离开本地。

## ⚙️ 环境变量设置

| 变量名 | 必填 | 说明 | 默认值 |
|--------|------|------|--------|
| `STORAGE_TYPE` | ✅ | 存储类型: `s3` 或 `webdav` | - |
| `SYNC_INTERVAL` | ❌ | 同步间隔时长（分钟） | `5` |

### S3 配置（`STORAGE_TYPE=s3`）

| 变量名 | 必填 | 说明 | 默认值 |
|--------|------|------|--------|
| `S3_ENDPOINT` | ✅ | S3 端点 URL | - |
| `S3_ACCESS_KEY` | ✅ | Access Key | - |
| `S3_SECRET_KEY` | ✅ | Secret Key | - |
| `S3_BUCKET` | ✅ | 存储桶名称 | - |
| `S3_REGION` | ❌ | 区域 | `us-east-1` |
| `S3_PATH` | ❌ | 桶内子路径 | `vaultwarden` |

### WebDAV 配置（`STORAGE_TYPE=webdav`）

| 变量名 | 必填 | 说明 | 默认值 |
|--------|------|------|--------|
| `WEBDAV_URL` | ✅ | WebDAV 服务器 URL | - |
| `WEBDAV_USER` | ✅ | 用户名 | - |
| `WEBDAV_PASS` | ✅ | 密码 | - |
| `WEBDAV_VENDOR` | ❌ | 供应商类型 (`nextcloud`/`owncloud`/`other`) | `other` |
| `WEBDAV_PATH` | ❌ | 远端子路径 | `vaultwarden` |

### 🔒 加密配置（高度推荐使用）

设置 `ENCRYPT_PASSWORD` 即可启用 AES-256 加密。您的加密密码不仅保护文件内容，也保护文件名。下载时脚本会自动进行解密。

| 变量名 | 必填 | 说明 | 默认值 |
|--------|------|------|--------|
| `ENCRYPT_PASSWORD` | ❌ | 加密密码（设置后则启用加密） | - |
| `ENCRYPT_SALT` | ❌ | 加密盐值（进一步增强安全性） | - |

> ⚠️ **重要安全提示**：
> - ⚠️ 加密密码一旦设置后**不可更改或丢失**，否则已加密的备份数据将**绝对无法解密**。
> - 💡 建议同时设置 `ENCRYPT_PASSWORD` 和 `ENCRYPT_SALT` 获取最高安全性。
> - 🛑 首次启用加密时，远端目标**必须**为空目录；不能对已有的未加密备份直接应用加密，请先清理或更换备份路径。

## 🚀 部署指南 (针对无状态 PaaS)

在类似 Railway、Render、Fly.io、Koyeb 等 PaaS 平台部署时极其简单：

1. **镜像拉取**: 指定镜像为 `ghcr.io/workerspages/vaultwarden-oss:latest` 或 `docker.io/workerspages/vaultwarden-oss:latest`。
2. **端口设置**: 容器默认通过 Cloudflare 兼容的 HTTP 端口暴露服务：**`8080`**。
3. **注入变量**: 填补上述的环境变量表，依据您使用的存储方案分配 S3 或是 WebDAV 的密钥信息。
4. **启动服务**: 容器将会在拉取云端数据后，在 `8080` 端口开启 Vaultwarden 面板服务。

> **性能提示**: 建议将 `SYNC_INTERVAL` 维持在建议的 5-10 分钟左右，以避免过于频繁的网络 I/O 带来的微小性能影响。

## 📦 现有数据迁移指南

如果你手头已经有现成的 Vaultwarden/Bitwarden 数据，想要让新部署的 PaaS 环境自动接管它，你需要按以下步骤将数据整理并上传至对应的对象存储或网盘（WebDAV）端点。

### 第一步：处理核心数据库 (关键)

Vaultwarden 数据库默认开启 WAL 模式，这意味着你最新的密码数据可能分散在 `db.sqlite3`、`db.sqlite3-wal` 和 `db.sqlite3-shm` 这三个独立文件中。

**方案 A：合成热备份单文件（强烈推荐 👍）**
在存有数据的旧服务器终端执行以下命令，将日志安全无损地合并为一个没有锁的完整快照：
\`\`\`bash
sqlite3 data/db.sqlite3 ".backup data/db_backup.sqlite3"
\`\`\`
生成完毕后，你只需要保留并提取这一个 **`db_backup.sqlite3`** 文件即可。（推荐原因：我们定制的镜像如果在启动时只发现 `db_backup.sqlite3` 备份文件，会自动将它安全转化为了正式环境主数据库，杜绝一切日志不匹配风险）

**方案 B：原样打包搬运（如确无命令行条件）**
如果你无法执行系统命令，请**务必确保在旧平台完全彻底关停服务**（防止后续写入丢失）的情况下，将 `db.sqlite3` 以及附属跟随的 `.wal` / `.shm` 等文件全部视作不可分割的整体保留。

### 第二步：向云端远端上传数据

登录你配置好的网盘或 S3 服务后台中，创建与环境变量 `S3_PATH` 或 `WEBDAV_PATH` 完全一致的那个最终路径目录（比如就叫 `vaultwarden` 文件夹）。将提取出的精华数据直接上传至该目录下：

- **数据库：** 刚刚合成的 `db_backup.sqlite3`（方案 A），**或者** `db.sqlite3*` 全套文件（方案 B）。
- **密钥环：** `rsa_key.pem` 与 `rsa_key.pub.pem`
- **附件目录：** `attachments` 文件夹（最重要的附件文件区）
- *(注：`tmp`、旧版本产生的特殊日志等临时文件纯属无用垃圾，可以直接抛弃，不要上传。)*

### 第三步：在容器启动前连接配置
完成数据投递后，直接去部署你 PaaS 平台的实例。只要云端密钥和访问路径填写无误，新的容器启动时就会在终端输出：
`[Init] Restoring data from remote: ...`
并自动把你放进去的数据“反向”抓取到容器的空卷中执行无缝挂载识别并最终拉起服务。登入面板，你的一切都在原位！

## 🛠️ GitHub Actions 与自动构建生态

如果您自己 Fork 此项目，该程序已经自带了一套完整的全自动发布工作流（位于 `.github/workflows/docker-build.yml`）。

当您修改程序代码并 Push 后，系统会自动使用 `Docker Buildx` 环境编译多平台并发版（涵盖 `linux/amd64` 和 `linux/arm64`）：
- **默认推送**：直接推流更新至 GitHub 原生源 `ghcr.io`。
- **Docker Hub 同步（可选）**：如需同步发布到 Docker Hub，请进入存储库的 `Settings -> Secrets and variables -> Actions`，补充设定 `DOCKERHUB_USERNAME` 以及 `DOCKERHUB_TOKEN` 凭据。系统感知相关 Secrets 存在时会自动启用同步推送！
