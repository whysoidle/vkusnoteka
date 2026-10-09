#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:?Pass the built app bundle path}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
if ! codesign --verify --deep --strict "$APP_PATH"; then
  # Flutter's PDFium build hook can update a valid nested signature after an
  # incremental Xcode build sealed the app. Repair only personal ad-hoc builds,
  # and only after every nested library passes its own verification.
  SIGNATURE_INFO=$(codesign -dv "$APP_PATH" 2>&1)
  case "$SIGNATURE_INFO" in
    *Signature=adhoc*)
      for LIBRARY in "$APP_PATH"/Contents/Frameworks/*.framework "$APP_PATH"/Contents/Frameworks/*.dylib; do
        [[ -e "$LIBRARY" ]] || continue
        codesign --verify --deep --strict "$LIBRARY"
      done
      codesign --force --sign - --preserve-metadata=entitlements,requirements,flags "$APP_PATH"
      ;;
    *) exit 1 ;;
  esac
fi
codesign --verify --deep --strict "$APP_PATH"
mkdir -p "$TASK_ROOT/dist"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/recipe-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP_PATH" "$STAGE/Вкуснотека.app"
ln -s /Applications "$STAGE/Applications"
printf 'Перед обновлением закройте приложение.\nПеретащите «Вкуснотека» в папку Applications; если она уже установлена, выберите «Заменить».\nБаза, настройки и скачанная модель хранятся отдельно и сохраняются при обновлении.\nПри переходе с прежнего названия после установки можно удалить только старый RecipeVault.app.\nПодключение Яндекс Диска (WebDAV) находится в настройках.\n' > "$STAGE/Установка.txt"
DMG="$TASK_ROOT/dist/Vkusnoteka-macOS-$VERSION.dmg"
ZIP="$TASK_ROOT/dist/Vkusnoteka-macOS-$VERSION.zip"
hdiutil create -volname 'Вкуснотека' -srcfolder "$STAGE" -ov -format UDZO "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Вкуснотека.app" "$ZIP"
cd "$TASK_ROOT/dist"
shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > "Vkusnoteka-macOS-$VERSION.sha256"
echo "Created $DMG and $ZIP"
