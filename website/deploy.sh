#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TCUBE_SITE_HOST="${TCUBE_SITE_HOST:?Set TCUBE_SITE_HOST to the authorized SSH target}"
DEPLOY_ID="$(date +%Y%m%d-%H%M%S)"
STAGE="$ROOT/.build/website/package-$DEPLOY_ID"
mkdir -p "$STAGE/public" "$STAGE/ops"
for file in index.html style.css app.js release.json; do cp "$ROOT/website/$file" "$STAGE/public/$file"; done
cp -R "$ROOT/website/assets" "$STAGE/public/assets"
cp "$ROOT/website/refresh-release.py" "$ROOT/website/t-cube-release-refresh.service" "$ROOT/website/t-cube-release-refresh.timer" "$STAGE/ops/"
find "$STAGE/public" -type f -exec chmod 644 {} +
find "$STAGE/public" -type d -exec chmod 755 {} +
COPYFILE_DISABLE=1 tar -czf "$STAGE.tar.gz" -C "$STAGE" public ops
ARCHIVE_SHA="$(shasum -a 256 "$STAGE.tar.gz" | cut -d ' ' -f 1)"
SSH_ARGS=(-o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o ConnectTimeout=20)
if [[ -n "${TCUBE_SITE_INTERFACE:-}" ]]; then SSH_ARGS+=(-o "ProxyCommand=nc -b $TCUBE_SITE_INTERFACE -w 25 %h %p"); fi
scp "${SSH_ARGS[@]}" "$STAGE.tar.gz" "${TCUBE_SITE_HOST}:/tmp/t-cube-$DEPLOY_ID.tar.gz"
ssh "${SSH_ARGS[@]}" "${TCUBE_SITE_HOST}" "bash -s -- '$DEPLOY_ID' '$ARCHIVE_SHA'" <<'REMOTE'
set -euo pipefail
DEPLOY_ID="$1"; EXPECTED_SHA="$2"
ARCHIVE="/tmp/t-cube-$DEPLOY_ID.tar.gz"
ACTUAL_SHA="$(sha256sum "$ARCHIVE" | cut -d ' ' -f 1)"
test "$ACTUAL_SHA" = "$EXPECTED_SHA"
RELEASE="/var/www/t-cube/releases/$DEPLOY_ID"
mkdir -p "$RELEASE"
tar -xzf "$ARCHIVE" -C "$RELEASE"
if command -v restorecon >/dev/null 2>&1; then restorecon -R "$RELEASE/public"; fi
test -s "$RELEASE/public/index.html"
test -s "$RELEASE/public/assets/social-preview.jpg"
test -s "$RELEASE/public/assets/nunito-sans-latin.woff2"
test -s "$RELEASE/public/assets/roboto-condensed-latin.woff2"
/usr/local/bin/python3 "$RELEASE/ops/refresh-release.py" --root "$RELEASE/public"
ORIGIN=http://tcube.gd306.cn
ORIGIN_PORT=80
if grep -Eq 'listen[[:space:]]+443[[:space:]]+ssl' /etc/nginx/t-cube-site.conf; then
    ORIGIN=https://tcube.gd306.cn
    ORIGIN_PORT=443
    sed -i 's|http://tcube.gd306.cn/|https://tcube.gd306.cn/|g' "$RELEASE/public/index.html"
fi
nginx -t
HOMEPAGE_BEFORE="$(sha256sum /var/www/html/index.html | cut -d ' ' -f 1)"
mkdir -p "/var/backups/t-cube-site/$DEPLOY_ID" /opt/t-cube-site
if test -e /var/www/html/t-cube || test -L /var/www/html/t-cube; then
    cp -a /var/www/html/t-cube "/var/backups/t-cube-site/$DEPLOY_ID/previous"
    if test ! -L /var/www/html/t-cube; then mv /var/www/html/t-cube "/var/backups/t-cube-site/$DEPLOY_ID/previous-directory"; fi
fi
install -m 644 "$RELEASE/ops/refresh-release.py" /opt/t-cube-site/refresh-release.py
install -m 644 "$RELEASE/ops/t-cube-release-refresh.service" /etc/systemd/system/t-cube-release-refresh.service
install -m 644 "$RELEASE/ops/t-cube-release-refresh.timer" /etc/systemd/system/t-cube-release-refresh.timer
ln -s "$RELEASE/public" "/var/www/html/.t-cube-$DEPLOY_ID"
mv -Tf "/var/www/html/.t-cube-$DEPLOY_ID" /var/www/html/t-cube
systemctl daemon-reload
systemctl enable --now t-cube-release-refresh.timer
systemctl start t-cube-release-refresh.service
systemctl is-active t-cube-release-refresh.timer
systemctl show t-cube-release-refresh.service -p Result -p ExecMainStatus
HOMEPAGE_AFTER="$(sha256sum /var/www/html/index.html | cut -d ' ' -f 1)"
test "$HOMEPAGE_BEFORE" = "$HOMEPAGE_AFTER"
nginx -t
curl -fsS --resolve "tcube.gd306.cn:$ORIGIN_PORT:127.0.0.1" "$ORIGIN/" -o "/tmp/t-cube-$DEPLOY_ID-https.html"
cmp "/tmp/t-cube-$DEPLOY_ID-https.html" /var/www/html/t-cube/index.html
sha256sum /var/www/html/t-cube/index.html /var/www/html/t-cube/style.css /var/www/html/t-cube/app.js
printf 'DEPLOYED %s\nHOMEPAGE_SHA256 %s\n' "$RELEASE" "$HOMEPAGE_AFTER"
rm -f "$ARCHIVE" "/tmp/t-cube-$DEPLOY_ID-https.html"
REMOTE
printf '%s\n' "$DEPLOY_ID" > "$ROOT/.build/website/deploy-id"
