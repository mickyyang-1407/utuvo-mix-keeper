#!/bin/sh
# 裝到 ~/Applications：開機自動開啟需要固定位置。
set -e
cd "$(dirname "$0")/.."
tools/make-dev-app.sh >/dev/null
pkill -x MixKeeper 2>/dev/null || true
sleep 1
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/MixKeeper.app"
ditto .build/MixKeeper.app "$HOME/Applications/MixKeeper.app"
open "$HOME/Applications/MixKeeper.app"
echo "$HOME/Applications/MixKeeper.app"
