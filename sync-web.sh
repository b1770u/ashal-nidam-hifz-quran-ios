#!/bin/bash
# Copies the shared web app from the Android project (same index.html, data, vendor files)
# into www/ and injects the iOS adapter scripts. Run after changing the Android web app.
set -e
cd "$(dirname "$0")"
SRC="${ANDROID_PROJECT:-$HOME/ashal-nidam-hifz-quran}/app/src/main/assets"
VERSION=$(node -p "require('./package.json').version")
[ -f "$SRC/index.html" ] || { echo "Android web app not found at $SRC"; exit 1; }
rm -rf www && mkdir -p www
cp -r "$SRC/." www/
cp ios-web/ios-bridge.js ios-web/ios-post.js www/
python3 -I - www/index.html "$VERSION" <<'PY'
import sys
p, ver = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read()
main = '  <script>\n'
assert s.count(main) == 1, 'main inline script not found'
s = s.replace(main, f'  <script>window.__IOS_APP_VERSION__ = "{ver}";</script>\n  <script src="ios-bridge.js"></script>\n' + main, 1)
end = '  </script>\n</body>'
assert s.count(end) == 1, 'end of main script not found'
s = s.replace(end, '  </script>\n  <script src="ios-post.js"></script>\n</body>', 1)
open(p, 'w', encoding='utf-8').write(s)
PY
echo "www synced from $SRC (v$VERSION)"
