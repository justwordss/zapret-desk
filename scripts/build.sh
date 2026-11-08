#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/.build-local}"
GO="${GO_BINARY:-go}"
ARCHS="${ARCHS:-arm64 amd64}"
mkdir -p "$BUILD/cache/go" "$BUILD/cache/swift" "$BUILD/gopath" "$ROOT/dist"
export GOCACHE="$BUILD/cache/go" GOPATH="${GOPATH:-$BUILD/gopath}"
APP="$ROOT/dist/Zapret Desk.app"
CONTENTS="$APP/Contents"
RES="$CONTENTS/Resources"
mkdir -p "$CONTENTS/MacOS" "$RES/bin" "$RES/Data" "$RES/Licenses"
cd "$ROOT/backend"
for command in zapretd zaprctl batconv deskbridge; do
  parts=()
  for arch in $ARCHS; do
    CGO_ENABLED=0 GOOS=darwin GOARCH="$arch" "$GO" build -trimpath -ldflags '-s -w -X main.version=desk-0.3.1' -o "$BUILD/$command.$arch" "./cmd/$command"
    parts+=("$BUILD/$command.$arch")
  done
  /usr/bin/lipo -create "${parts[@]}" -output "$RES/bin/$command"
  /usr/bin/codesign --force --sign - "$RES/bin/$command"
done
/usr/bin/ditto --norsrc --noextattr --noacl "$ROOT/backend/lists" "$RES/Data/lists"
/usr/bin/ditto --norsrc --noextattr --noacl "$ROOT/backend/fakes" "$RES/Data/fakes"
/usr/bin/ditto --norsrc --noextattr --noacl "$ROOT/backend/strategies" "$RES/Data/strategies"
/usr/bin/ditto --norsrc --noextattr --noacl "$ROOT/Flowseal/lists" "$RES/Data/lists"
/usr/bin/ditto --norsrc --noextattr --noacl "$ROOT/Flowseal/fakes" "$RES/Data/fakes"
# Generated files preserve the current upstream BAT options; no command is executed.
"$RES/bin/batconv" --in "$ROOT/Flowseal" --out "$RES/Data/strategies" --lists "$RES/Data/lists" --fakes "$RES/Data/fakes" --game-filter off > "$BUILD/conversion-report.txt"
# Hashes identify unchanged pre-metadata bundled strategies for a safe upgrade.
for f in "$RES/Data/strategies"/*.toml; do
  legacy_hash=$(/usr/bin/sed -E '/^game_(tcp|udp|ports) = /d' "$f" | /usr/bin/shasum -a 256)
  printf '%s  %s\n' "${legacy_hash%% *}" "${f##*/}"
done > "$RES/Data/strategy-migrations.tsv"
printf '# Managed by Zapret Desk\n' > "$RES/Data/lists/list-general-user.txt"
printf '# Managed by Zapret Desk\n' > "$RES/Data/lists/list-exclude-user.txt"
# Optional empty CIDR lists are omitted rather than interpreted as match-all.
cp "$ROOT/backend/LICENSE" "$RES/Licenses/zapret-for-mac.txt"
cp "$ROOT/ThirdParty/Flowseal-LICENSE.txt" "$RES/Licenses/Flowseal.txt"
cp "$ROOT/ThirdParty/zapret-LICENSE.txt" "$RES/Licenses/zapret.txt"
TG_RUNTIME="${TELEGRAM_RUNTIME:-$BUILD/tg-dist/tgws}"
if [ ! -x "$TG_RUNTIME/tgws" ]; then BUILD_DIR="$BUILD" "$ROOT/scripts/build-telegram.sh"; fi
/usr/bin/ditto --norsrc --noextattr --noacl "$TG_RUNTIME" "$RES/TGProxy"
cp "$ROOT/telegram/LICENSE" "$RES/Licenses/tg-ws-proxy.txt"
/usr/bin/ditto --norsrc --noextattr --noacl "$ROOT/ThirdParty/TG-Dependencies" "$RES/Licenses/TG-Dependencies"
cp "$ROOT/Assets/AppIcon.icns" "$RES/AppIcon.icns"
parts=()
for arch in $ARCHS; do
  target="$arch"; [ "$arch" != amd64 ] || target=x86_64
  swiftc -O -parse-as-library -swift-version 5 -module-cache-path "$BUILD/cache/swift" -target "$target-apple-macosx13.0" "$ROOT"/Sources/ZapretDesk/*.swift -o "$BUILD/ZapretDesk.$arch"
  parts+=("$BUILD/ZapretDesk.$arch")
done
/usr/bin/lipo -create "${parts[@]}" -output "$CONTENTS/MacOS/ZapretDesk"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ZapretDesk</string>
<key>CFBundleIdentifier</key><string>io.zapretdesk.app</string>
<key>CFBundleName</key><string>Zapret Desk</string>
<key>CFBundleDisplayName</key><string>Zapret Desk</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.1</string>
<key>CFBundleVersion</key><string>8</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" "$ROOT/dist/ZapretDesk-macOS.zip"
printf '\nBuilt: %s\n' "$APP"
