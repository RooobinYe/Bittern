#!/bin/bash
# 让模拟器上的 Bittern 显示真实持仓：把本地 "Bittern Local" scheme 里的 SnapTrade 凭据传给
# Debug 版 App，由 DebugSnapTradeCredentialsInjector 存进这台模拟器的 Keychain。
#
# Keychain 是每台模拟器独立的，所以同一台只需运行一次；换了模拟器或抹掉后再运行。
# 凭据只通过环境变量传给 App，不会打印。scheme 放在 xcuserdata 下，不入库。
#
# 用法: bash scripts/use-real-holdings.sh [设备名或 UDID]
#   默认使用当前开着的模拟器。这台上还没装 App 时，会先构建并安装当前代码。
#   可以用环境变量 BITTERN_LOCAL_SCHEME 指定其他 scheme 文件。
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID=com.robinye.Bittern
DERIVED=build/RealHoldingsDerived
MAIN_CHECKOUT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
LOCAL_SCHEME=${BITTERN_LOCAL_SCHEME:-"$MAIN_CHECKOUT/Bittern.xcodeproj/xcuserdata/$USER.xcuserdatad/xcschemes/Bittern Local.xcscheme"}

parse_credentials() {
  python3 -I - "$1" <<'PY'
import shlex
import sys
import xml.etree.ElementTree as ET

wanted = {
    "BITTERN_SNAPTRADE_CLIENT_ID",
    "BITTERN_SNAPTRADE_CONSUMER_KEY",
    "BITTERN_SNAPTRADE_USER_ID",
    "BITTERN_SNAPTRADE_USER_SECRET",
}
found = {}
for variable in ET.parse(sys.argv[1]).iter("EnvironmentVariable"):
    key = variable.get("key")
    value = (variable.get("value") or "").strip()
    if key in wanted and variable.get("isEnabled") == "YES" and value:
        found[key] = value

missing = sorted(wanted - set(found))
if missing:
    sys.exit("本地 scheme 缺少：" + " ".join(missing))

for key, value in found.items():
    print(f"export SIMCTL_CHILD_{key}={shlex.quote(value)}")
PY
}

resolve_device() {
  xcrun simctl list devices available -j | python3 -I -c '
import json
import sys

wanted = sys.argv[1]
devices = [d for group in json.load(sys.stdin)["devices"].values() for d in group]
booted = [d for d in devices if d["state"] == "Booted"]

if wanted:
    matches = [d for d in devices if wanted in (d["udid"], d["name"])]
    if not matches:
        sys.exit(f"找不到模拟器：{wanted}")
    matches.sort(key=lambda d: d["state"] != "Booted")
    device = matches[0]
elif len(booted) == 1:
    device = booted[0]
elif booted:
    names = "、".join(d["name"] for d in booted)
    sys.exit(f"有多台模拟器开着（{names}），请指定一台：bash scripts/use-real-holdings.sh 设备名")
else:
    sys.exit("没有开着的模拟器。先打开一台，或指定一台：bash scripts/use-real-holdings.sh 设备名")

print(device["udid"], device["state"], device["name"], sep="\t")
' "$1"
}

# ── 凭据：先读出来，缺了就直接失败，不做后面的事 ─────────────────────────
if [ ! -f "$LOCAL_SCHEME" ]; then
  echo "找不到本地 scheme：$LOCAL_SCHEME" >&2
  exit 1
fi
credentials=$(parse_credentials "$LOCAL_SCHEME")

# ── 模拟器 ────────────────────────────────────────────────────────────
device=$(resolve_device "${1:-}")
IFS=$'\t' read -r UDID STATE NAME <<< "$device"

if [ "$STATE" != "Booted" ]; then
  echo "==> 启动模拟器 $NAME"
  xcrun simctl boot "$UDID"
  xcrun simctl bootstatus "$UDID" -b > /dev/null
fi

# ── App：已经装了就不动它，避免覆盖正在用的版本 ──────────────────────────
if ! xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" > /dev/null 2>&1; then
  echo "==> $NAME 上还没装 Bittern，构建并安装当前代码"
  xcodebuild -project Bittern.xcodeproj -scheme Bittern -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" build -quiet
  xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/Bittern.app"
fi

# ── 启动：环境变量只在这一步才导出 ────────────────────────────────────
eval "$credentials"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" > /dev/null

echo "已在 $NAME 上启动 Bittern。App 会把凭据存进这台模拟器的 Keychain，之后正常打开也能看到持仓。"
