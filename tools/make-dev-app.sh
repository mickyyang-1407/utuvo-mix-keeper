#!/bin/sh
# 測試用 .app（只放在 .build，不是出貨打包）。
set -e
cd "$(dirname "$0")/.."
swift build -c release >/dev/null
APP=.build/MixKeeper.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MixKeeper "$APP/Contents/MacOS/MixKeeper"
cp -R assets/pet "$APP/Contents/Resources/pet"
[ -d assets/house ] && cp -R assets/house "$APP/Contents/Resources/house"
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MixKeeper</string>
<key>CFBundleIdentifier</key><string>com.utuvo.mixkeeper.dev</string>
<key>CFBundleName</key><string>Mix Keeper</string>
<key>CFBundleDisplayName</key><string>Mix Keeper</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hant</string></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Switches to the right Terminal tab when you click a card.</string>
</dict></plist>
P
mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/zh-Hant.lproj"
printf '"CFBundleDisplayName" = "Mix Keeper";\n"CFBundleName" = "Mix Keeper";\n"NSAppleEventsUsageDescription" = "Switches to the right Terminal tab when you click a card.";\n' > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
printf '"CFBundleDisplayName" = "混音守門員";\n"CFBundleName" = "混音守門員";\n"NSAppleEventsUsageDescription" = "點卡片時切換到正確的 Terminal 分頁。";\n' > "$APP/Contents/Resources/zh-Hant.lproj/InfoPlist.strings"
codesign --force --sign - "$APP"
echo "$PWD/$APP"
