#!/bin/bash

# MacAfk 双版本构建脚本
# 用于构建 Pro 版和 Lite 版（App Store）

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR/MacAfk"

BUILD_DIR="$PROJECT_DIR/Build"
ARCHIVE_DIR="$PROJECT_DIR/Archives"

echo "🏗️  MacAfk 双版本构建脚本"
echo "================================"

# 清理旧的构建产物
echo ""
echo "🧹 清理旧的构建产物..."
rm -rf "$BUILD_DIR"
rm -rf "$ARCHIVE_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$ARCHIVE_DIR"

# 构建 Pro 版（真实硬件亮度）
echo ""
echo "🚀 构建 MacAfk Pro（真实硬件亮度）..."
echo "   - 沙盒：禁用"
echo "   - 亮度控制：DisplayServices API"
echo "   - Bundle ID: com.snowywar.MacAfk"
echo ""

xcodebuild -scheme MacAfk \
    -configuration Release \
    -archivePath "$ARCHIVE_DIR/MacAfk-Pro.xcarchive" \
    archive

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_DIR/MacAfk-Pro.xcarchive" \
    -exportPath "$BUILD_DIR/MacAfk-Pro" \
    -exportOptionsPlist "$PROJECT_DIR/ExportOptions-Pro.plist"

echo "✅ MacAfk Pro 构建完成！"

# 构建 Lite 版（Gamma 调光，App Store 兼容）
echo ""
echo "🚀 构建 MacAfk Lite（App Store 版本）..."
echo "   - 沙盒：启用"
echo "   - 亮度控制：Gamma 调光"
echo "   - Bundle ID: com.snowywar.MacAfk.lite"
echo ""

xcodebuild -scheme MacAfk \
    -configuration Release-AppStore \
    -archivePath "$ARCHIVE_DIR/MacAfk-Lite.xcarchive" \
    archive

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_DIR/MacAfk-Lite.xcarchive" \
    -exportPath "$BUILD_DIR/MacAfk-Lite" \
    -exportOptionsPlist "$PROJECT_DIR/ExportOptions-Lite.plist"

echo "✅ MacAfk Lite 构建完成！"

# 创建 DMG（仅 Pro 版）
echo ""
echo "📦 创建 MacAfk Pro DMG..."

# 简单创建 DMG
hdiutil create -volname "MacAfk Pro" \
    -srcfolder "$BUILD_DIR/MacAfk-Pro" \
    -ov -format UDZO \
    "$BUILD_DIR/MacAfk-Pro-v1.0.dmg"

echo "✅ DMG 创建完成！"

# 显示结果
echo ""
echo "================================"
echo "🎉 构建完成！"
echo ""
echo "📁 构建产物位置："
echo "   Pro 版:  $BUILD_DIR/MacAfk-Pro/MacAfk Pro.app"
echo "   Pro DMG: $BUILD_DIR/MacAfk-Pro-v1.0.dmg"
echo "   Lite 版: $BUILD_DIR/MacAfk-Lite/MacAfk Lite.app"
echo ""
echo "📋 下一步："
echo "   1. Pro 版: 签名后发布到 GitHub/网站"
echo "   2. Lite 版: 提交到 App Store"
echo ""

