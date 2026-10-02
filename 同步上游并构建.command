#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

clear
echo "========================================"
echo " CodexIsland 上游同步与本地构建"
echo "========================================"
echo
echo "将会："
echo "  1. 获取官方最新版本"
echo "  2. 创建本地备份分支"
echo "  3. 合并更新并保留本地功能"
echo "  4. 运行测试并构建新应用"
echo

if SYNC_BUILD_APP=1 ./scripts/sync-upstream.sh; then
  echo
  echo "✓ 处理完成"
  echo
  echo "应用位置："
  echo "$SCRIPT_DIR/build/CodexIsland.app"
  echo
  echo "可以打开 build 文件夹查看新版本。"
else
  status=$?
  echo
  echo "✗ 未能自动完成（错误代码：$status）"
  echo
  if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    echo "检测到合并冲突，本地功能没有被覆盖。"
    echo "解决冲突后可执行："
    echo "  ./scripts/sync-upstream.sh --continue"
    echo
    echo "如需取消这次合并："
    echo "  ./scripts/sync-upstream.sh --abort"
  else
    echo "请查看上方提示；项目文件不会被强制覆盖。"
  fi
fi

echo
read -r -p "按 Enter 键关闭窗口…"
