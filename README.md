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

## 🛠️ GitHub Actions 与自动构建生态

如果您自己 Fork 此项目，该程序已经自带了一套完整的全自动发布工作流（位于 `.github/workflows/docker-build.yml`）。

当您修改程序代码并 Push 后，系统会自动使用 `Docker Buildx` 环境编译多平台并发版（涵盖 `linux/amd64` 和 `linux/arm64`）：
- **默认推送**：直接推流更新至 GitHub 原生源 `ghcr.io`。
- **Docker Hub 同步（可选）**：如需同步发布到 Docker Hub，请进入存储库的 `Settings -> Secrets and variables -> Actions`，补充设定 `DOCKERHUB_USERNAME` 以及 `DOCKERHUB_TOKEN` 凭据。系统感知相关 Secrets 存在时会自动启用同步推送！
