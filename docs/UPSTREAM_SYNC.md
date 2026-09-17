# Keeping local features when upstream updates

Run the synchronization script from the repository root whenever CodexIsland
publishes a new version:

```bash
./scripts/sync-upstream.sh
```

The script fetches `origin/main`, creates a `codex/backup-before-upstream-*`
backup branch, merges instead of replacing local history, and runs the test
suite before committing. To build the app as part of the same operation:

```bash
SYNC_BUILD_APP=1 ./scripts/sync-upstream.sh
```

If Git reports conflicts, review and stage the resolved files, then run:

```bash
./scripts/sync-upstream.sh --continue
```

Use `./scripts/sync-upstream.sh --abort` to return to the exact pre-merge state.
The backup branch remains available even after a successful merge.

Local builds intentionally omit the official Sparkle update feed. Otherwise an
official release could replace the customized binary after a restart. The
release workflow explicitly enables Sparkle only for official distribution
builds. Your preferences remain in the normal CodexIsland UserDefaults domain.

## 上游更新时保留本地功能

CodexIsland 发布新版本后，在项目根目录执行：

```bash
./scripts/sync-upstream.sh
```

脚本会获取 `origin/main`，自动创建
`codex/backup-before-upstream-*` 备份分支，通过合并保留本地历史，
并在提交前运行测试。如果希望同时构建应用：

```bash
SYNC_BUILD_APP=1 ./scripts/sync-upstream.sh
```

如果发生冲突，脚本会停下，不会覆盖任何本地代码。解决冲突并将文件
加入暂存区后，执行：

```bash
./scripts/sync-upstream.sh --continue
```

如果希望取消本次合并，执行 `./scripts/sync-upstream.sh --abort`。

本地定制构建会有意关闭官方 Sparkle 更新源，避免重启后官方原版覆盖定制功能。
只有正式发布脚本才会启用 Sparkle。外观、服务显示和任务提醒等偏好仍保存在
CodexIsland 原有的 UserDefaults 中。
