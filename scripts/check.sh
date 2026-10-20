#!/usr/bin/env bash
# 不签名地编译两个平台 + 跑核心逻辑测试，用来快速发现编译错误。
# 输出写到 build/check.log，出错时把末尾几十行贴出来即可。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
log=build/check.log
: > "$log"

echo "== LedgerCore 测试" | tee -a "$log"
(cd LedgerCore && swift test 2>&1) | tee -a "$log" | tail -5

scripts/bootstrap.sh --no-open >> "$log" 2>&1

for target in DNSManager-macOS DNSManager-iOS; do
  if [[ "$target" == *iOS ]]; then dest='generic/platform=iOS Simulator'; else dest='platform=macOS'; fi
  echo "== 编译 $target" | tee -a "$log"
  xcodebuild -project DNSManager.xcodeproj -scheme "$target" -destination "$dest" \
    -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 \
    | tee -a "$log" | grep -E "error:|warning: .*(deprecated|unavailable)|BUILD (SUCCEEDED|FAILED)" || true
done
echo "完整日志：$log"
