#!/usr/bin/env bash
# 生成 Xcode 工程并打开。
#   scripts/bootstrap.sh            # 第一次会提示输入开发者团队 ID，存到 .team-id（不进 git）
#   DEVELOPMENT_TEAM=XXXXXXXXXX scripts/bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "安装 xcodegen……"
    brew install xcodegen
  else
    echo "需要 xcodegen：先装 Homebrew（https://brew.sh），再运行 brew install xcodegen" >&2
    exit 1
  fi
fi

if [[ -z "${DEVELOPMENT_TEAM:-}" && -f .team-id ]]; then
  DEVELOPMENT_TEAM="$(tr -d '[:space:]' < .team-id)"
fi
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "iCloud 同步需要付费开发者账号的团队 ID（10 位，developer.apple.com › Membership 里能看到）。"
  read -r -p "团队 ID：" DEVELOPMENT_TEAM
  echo "$DEVELOPMENT_TEAM" > .team-id
fi
export DEVELOPMENT_TEAM

xcodegen generate
if [[ "${1:-}" != "--no-open" ]]; then
  open DNSManager.xcodeproj
fi
