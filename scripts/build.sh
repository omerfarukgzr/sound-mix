#!/bin/bash
# Tab Mixer'ı derler ve dist/ klasörüne "Tab Mixer.app" ile yayın zip'ini üretir.
#   scripts/build.sh            → derle ve paketle
#   scripts/build.sh --install  → ayrıca ~/Applications'a kur ve başlat
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP="dist/Tab Mixer.app"

# Apple Silicon + Intel için tek dosya
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/TabMixer"

# İkon
if [ ! -f Resources/AppIcon.icns ]; then
  TMP=$(mktemp -d)
  swift scripts/make_icon.swift "$TMP/icon.png"
  mkdir "$TMP/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
  mkdir -p Extension/icons
  for s in 16 32 48 128; do sips -z $s $s "$TMP/icon.png" --out "Extension/icons/$s.png" >/dev/null; done
  rm -rf "$TMP"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TabMixer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Extension "$APP/Contents/Resources/Extension"
codesign --force --deep --sign - "$APP"

ZIP="dist/TabMixer-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Hazır: $APP"
echo "Yayın dosyası: $ZIP"

if [ "${1:-}" = "--install" ]; then
  # Önce menü uygulamasını kapat; köprü yeni sürüm kopyalandıktan sonra kapatılıyor
  pkill -f "Tab Mixer.app/Contents/MacOS/TabMixer$" 2>/dev/null || true
  rm -rf "$HOME/Applications/Tab Mixer.app"
  cp -R "$APP" "$HOME/Applications/"
  # Chrome'un başlattığı köprü eski ikiliyle çalışmaya devam eder ve kendiliğinden kapanmaz.
  # Onu da kapat; eklenti bağlantı kopunca yeniden bağlanır ve Chrome yeni ikiliyi başlatır.
  # (Installer'ın "reload" komutu sadece eklenti dosyaları değiştiğinde gidiyor, ona güvenemeyiz.)
  pkill -f "Tab Mixer.app/Contents/MacOS/TabMixer chrome-extension://" 2>/dev/null || true
  open "$HOME/Applications/Tab Mixer.app"
  echo "Kuruldu: ~/Applications/Tab Mixer.app"
fi
