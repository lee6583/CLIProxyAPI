# Render 免费版持久化方案（GitStore）

适用场景：不升级 Render、不要付费磁盘/数据库，但要避免账号在睡眠/重启后清空。

## 1. 问题根因

Render 免费实例会休眠并可能重建实例；本地文件系统是临时的。
如果 CLIProxyAPI 使用默认本地 `auth-dir` 存 token，实例重建后会丢失认证文件。

直接后果：

1. 管理面板 `auth-files` 变空（账号数 = 0）
2. `/v1/models` 不再包含 `gpt-5.3-codex`
3. Cursor/Codex 报错：`unknown provider for model gpt-5.3-codex`

## 2. 免费持久化思路

使用 CLIProxyAPI 内置 `GitStore`：

1. 启动时从 Git 仓库拉取 `auths/` 和 `config/`
2. 新增/更新账号时自动 commit + push
3. 实例重建后再次 clone，账号自动恢复

这样不依赖 Render 付费磁盘。

## 3. Render 配置（无付费）

仓库内提供了 Render Blueprint 模板：[render.yaml](../render.yaml)

至少配置以下环境变量：

1. `CLIPROXY_API_KEYS`：对外 API key，逗号分隔
2. `MANAGEMENT_PASSWORD`：管理 API 密钥
3. `GITSTORE_GIT_URL`：Git 仓库地址（如 `https://github.com/<you>/<repo>.git`）
4. `GITSTORE_GIT_TOKEN`：可写入该仓库的 token（建议 Fine-grained PAT，最小权限 Contents: Read/Write）

可选：

1. `GITSTORE_GIT_USERNAME`：默认 `git`
2. `GITSTORE_LOCAL_PATH`：默认模板值 `/tmp/cliproxy`

## 4. 一次性回灌历史账号（可选）

如果线上已经出现“账号清空”，可从本地 `codex_tokens` 批量回灌：

```bash
cd /path/to/CLIProxyAPI
./scripts/reseed_auth_files.sh \
  --base-url https://your-cliproxyapi.onrender.com \
  --management-key '<MANAGEMENT_PASSWORD>' \
  --source-dir /path/to/chatgpt_register/codex_tokens
```

默认只在远端账号数为 0 时执行；如需强制重传可加 `--always`。

## 5. 验收（必须）

使用脚本做端到端检查：

```bash
cd /path/to/CLIProxyAPI
python3 ./scripts/verify_cpa_stack.py \
  --base-url https://your-cliproxyapi.onrender.com \
  --management-key '<MANAGEMENT_PASSWORD>' \
  --api-key '<CLIPROXY_API_KEYS中的任意一个>' \
  --model gpt-5.3-codex
```

通过标准：

1. `auth-files count > 0`
2. `/v1/models` 包含 `gpt-5.3-codex`
3. `/v1/responses` 返回 `status=completed`

## 6. 建议的巡检

每天或每次部署后至少跑一次：

```bash
python3 ./scripts/verify_cpa_stack.py --base-url ... --management-key ... --api-key ...
```

如果失败，优先执行第 4 步回灌脚本，再看 Render 日志。
