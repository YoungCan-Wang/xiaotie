#!/bin/bash
# 用法：
#   bash build.sh           编译出 build/小贴.app
#   bash build.sh install   编译并安装到 /Applications，然后启动
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="小贴"               # 应用名：/Applications/小贴.app
EXEC_NAME="Xiaotie"          # 可执行文件名
BUNDLE_ID="local.xiaotie.app"
LEGACY_BUNDLE_ID="local.clipkeeper.app"
APP_DIR="build/${APP_NAME}.app"
ARCH="$(uname -m)"   # arm64 或 x86_64

if ! command -v swiftc >/dev/null 2>&1; then
  echo "没找到 swiftc。请先在终端运行：xcode-select --install"
  exit 1
fi

echo "==> 编译（${ARCH}）…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

swiftc -O \
  -target "${ARCH}-apple-macos13.0" \
  -module-name "${EXEC_NAME}" \
  Sources/*.swift \
  -o "${APP_DIR}/Contents/MacOS/${EXEC_NAME}"

cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"

echo "==> 生成图标…"
ICONSET="build/AppIcon.iconset"
rm -rf "${ICONSET}"
if swift Scripts/make_icon.swift "${ICONSET}" >/dev/null 2>&1 \
   && iconutil -c icns "${ICONSET}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "    图标已生成"
else
  echo "    图标生成失败（不影响使用）"
fi

echo "==> 签名…"
# 优先用钥匙串里的开发者证书签名：签名身份固定，以后重新编译「辅助功能」权限不会失效。
# 没有证书就用本地临时签名，每次重新编译后需要重新开启一次权限。
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Apple Development|Mac Developer|Developer ID Application/ {print $2; exit}' || true)"
if [[ -n "${IDENTITY}" ]] && codesign --force --deep --sign "${IDENTITY}" "${APP_DIR}" >/dev/null 2>&1; then
  echo "    已用开发者证书签名，以后重新编译不用再授权"
else
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || echo "    签名失败（不影响本机使用）"
  echo "    没找到开发者证书，用的本地临时签名：每次重新编译后要重新开启辅助功能权限"
fi

echo "✅ 编译完成：$(pwd)/${APP_DIR}"

if [[ "${1:-}" == "install" ]]; then
  echo "==> 安装到 /Applications …"
  # 关掉正在运行的旧版本：以前的 ClipKeeper、旧的 Electron 版小贴、上次装的小贴
  pkill -x ClipKeeper 2>/dev/null || true
  pkill -f "/Applications/${APP_NAME}.app/" 2>/dev/null || true
  sleep 0.8
  if [[ -d "/Applications/ClipKeeper.app" ]]; then
    rm -rf "/Applications/ClipKeeper.app"
    tccutil reset Accessibility "${LEGACY_BUNDLE_ID}" >/dev/null 2>&1 || true
    echo "    已删除旧的 ClipKeeper.app（历史记录和设置会自动搬到小贴）"
  fi
  # 签名变了的话，系统设置里旧的授权看着是开的，其实已经失效：清掉，让它重新申请
  OLD_REQ="$(codesign -d -r- "/Applications/${APP_NAME}.app" 2>&1 | grep designated || true)"
  NEW_REQ="$(codesign -d -r- "${APP_DIR}" 2>&1 | grep designated || true)"
  if [[ "${OLD_REQ}" != "${NEW_REQ}" ]]; then
    tccutil reset Accessibility "${BUNDLE_ID}" >/dev/null 2>&1 || true
    echo "    签名有变化，已清掉旧的辅助功能授权，启动后点菜单栏里的提示重新开启一次"
  fi
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "${APP_DIR}" "/Applications/"
  open "/Applications/${APP_NAME}.app"
  echo "✅ 小贴已安装并启动，看看屏幕右上角菜单栏里的剪贴板图标"
fi
