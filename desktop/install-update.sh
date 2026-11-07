#!/bin/sh
set -eu
parent_pid=$1
source_app=$2
target_app=$3
new_version=$4
update_cache=$5
relaunch=$6
exec >>"$update_cache/install.log" 2>&1

bundle_id=com.wowforever.konglish
plist=/usr/libexec/PlistBuddy
parent_dir=$(dirname "$target_app")
temporary="$parent_dir/.Konglish-install-$$.app"
previous="$parent_dir/.Konglish-previous.app"
replaced=0

cleanup() {
  if [ "$replaced" = 1 ] && [ ! -e "$target_app" ] && [ -d "$previous" ]; then
    /bin/mv "$previous" "$target_app"
  fi
  if [ -d "$temporary" ]; then /bin/rm -rf "$temporary"; fi
}
trap cleanup EXIT

attempts=0
while /bin/kill -0 "$parent_pid" 2>/dev/null; do
  attempts=$((attempts + 1))
  if [ "$attempts" -ge 150 ]; then exit 1; fi
  /bin/sleep 0.2
done

[ ! -L "$target_app" ] && [ ! -L "$source_app" ] && [ ! -L "$previous" ]
[ "$("$plist" -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist")" = "$bundle_id" ]
[ "$("$plist" -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")" = "$bundle_id" ]
[ "$("$plist" -c 'Print :CFBundleShortVersionString' "$source_app/Contents/Info.plist")" = "$new_version" ]
/usr/bin/codesign --verify --deep --strict "$source_app"
/usr/bin/ditto "$source_app" "$temporary"
/usr/bin/codesign --verify --deep --strict "$temporary"
if [ -e "$previous" ]; then
  [ "$("$plist" -c 'Print :CFBundleIdentifier' "$previous/Contents/Info.plist")" = "$bundle_id" ]
  /bin/rm -rf "$previous"
fi
/bin/mv "$target_app" "$previous"
replaced=1
/bin/mv "$temporary" "$target_app"
replaced=0
/bin/rm -f "$update_cache/pending.json"
# The verified download is disposable after the new app has replaced the old one.
/bin/rm -rf "$(dirname "$source_app")"
if [ "$relaunch" = 1 ]; then /usr/bin/open "$target_app"; fi
