#!/bin/bash
# 用法：
#   ./build.sh           编译出 build/ClipKeeper.app
#   ./build.sh install   编译并安装到 /Applications，然后启动
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ClipKeeper"
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
  -module-name "${APP_NAME}" \
  Sources/*.swift \
  -o "${APP_DIR}/Contents/MacOS/${APP_NAME}"

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

echo "==> 本地签名…"
codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || echo "    签名失败（不影响本机使用）"

echo "✅ 编译完成：$(pwd)/${APP_DIR}"

if [[ "${1:-}" == "install" ]]; then
  echo "==> 安装到 /Applications …"
  pkill -x "${APP_NAME}" 2>/dev/null || true
  sleep 0.5
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "${APP_DIR}" "/Applications/"
  open "/Applications/${APP_NAME}.app"
  echo "✅ 已安装并启动，看看屏幕右上角菜单栏里的剪贴板图标"
fi
