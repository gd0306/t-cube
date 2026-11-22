#!/bin/bash
# Configure the maintainer-authorized HTTP origin without replacing other vhosts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TCUBE_SITE_HOST="${TCUBE_SITE_HOST:?Set TCUBE_SITE_HOST to the authorized SSH target}"
CHANGE_ID="domain-$(date +%Y%m%d-%H%M%S)"
ARCHIVE="$ROOT/.build/website/$CHANGE_ID.tar.gz"
mkdir -p "$ROOT/.build/website"
COPYFILE_DISABLE=1 tar -czf "$ARCHIVE" -C "$ROOT/website/nginx" t-cube-site.conf t-cube-legacy-locations.conf
SSH_ARGS=(-o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o ConnectTimeout=20)
if [[ -n "${TCUBE_SITE_INTERFACE:-}" ]]; then SSH_ARGS+=(-o "ProxyCommand=nc -b $TCUBE_SITE_INTERFACE -w 25 %h %p"); fi
scp "${SSH_ARGS[@]}" "$ARCHIVE" "$TCUBE_SITE_HOST:/tmp/$CHANGE_ID.tar.gz"
ssh "${SSH_ARGS[@]}" "$TCUBE_SITE_HOST" "bash -s -- '$CHANGE_ID'" <<'REMOTE'
set -euo pipefail
CHANGE_ID="$1"
BACKUP="/var/backups/t-cube-site/$CHANGE_ID"
mkdir -p "$BACKUP/incoming"
nginx -t
cp -p /etc/nginx/nginx.conf "$BACKUP/nginx.conf"
for name in t-cube-site.conf t-cube-legacy-locations.conf; do
    if test -e "/etc/nginx/$name"; then cp -p "/etc/nginx/$name" "$BACKUP/$name"; fi
done
HOMEPAGE_BEFORE="$(sha256sum /var/www/html/index.html | cut -d ' ' -f 1)"
rollback() {
    cp -p "$BACKUP/nginx.conf" /etc/nginx/nginx.conf
    for name in t-cube-site.conf t-cube-legacy-locations.conf; do
        if test -e "$BACKUP/$name"; then cp -p "$BACKUP/$name" "/etc/nginx/$name"; else rm -f "/etc/nginx/$name"; fi
    done
    if nginx -t; then nginx -s reload; fi
}
trap 'result=$?; rollback; exit "$result"' ERR
tar -xzf "/tmp/$CHANGE_ID.tar.gz" -C "$BACKUP/incoming"
install -m 644 "$BACKUP/incoming/t-cube-site.conf" /etc/nginx/t-cube-site.conf
install -m 644 "$BACKUP/incoming/t-cube-legacy-locations.conf" /etc/nginx/t-cube-legacy-locations.conf
python3 - <<'PY'
from pathlib import Path
path = Path('/etc/nginx/nginx.conf')
text = path.read_text()
# Keep the dedicated host after the pre-existing default servers. Installing
# it in conf.d would otherwise change which server is the implicit default.
site = 'include /etc/nginx/t-cube-site.conf;'
if site not in text:
    anchor = 'include /etc/nginx/tide-accounts.conf;'
    if text.count(anchor) != 1:
        raise SystemExit('Cannot locate the verified http-level include anchor')
    text = text.replace(anchor, anchor + '\n    ' + site)
legacy = 'include /etc/nginx/t-cube-legacy-locations.conf;'
if legacy not in text:
    anchor = 'include /etc/nginx/excel-tool-location.conf;'
    if text.count(anchor) != 1:
        raise SystemExit('Cannot locate the verified main-site HTTPS server')
    text = text.replace(anchor, anchor + '\n        ' + legacy)
path.write_text(text)
PY
nginx -t
nginx -s reload
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS --max-time 3 --resolve tcube.gd306.cn:80:127.0.0.1 http://tcube.gd306.cn/ -o "$BACKUP/new-origin.html" && cmp -s "$BACKUP/new-origin.html" /var/www/html/t-cube/index.html; then break; fi
    sleep 0.2
done
cmp "$BACKUP/new-origin.html" /var/www/html/t-cube/index.html
curl -fsS --resolve www.gd306.cn:443:127.0.0.1 https://www.gd306.cn/ -o "$BACKUP/main-homepage.html"
cmp "$BACKUP/main-homepage.html" /var/www/html/index.html
REDIRECT="$(curl -sS -o /dev/null -w '%{redirect_url}' --resolve www.gd306.cn:443:127.0.0.1 'https://www.gd306.cn/t-cube/assets/app-icon.png?check=1')"
test "$REDIRECT" = 'http://tcube.gd306.cn/assets/app-icon.png?check=1'
HOMEPAGE_AFTER="$(sha256sum /var/www/html/index.html | cut -d ' ' -f 1)"
test "$HOMEPAGE_BEFORE" = "$HOMEPAGE_AFTER"
trap - ERR
rm -f "/tmp/$CHANGE_ID.tar.gz"
printf 'ORIGIN http://tcube.gd306.cn/\nBACKUP %s\nHOMEPAGE_SHA256 %s\n' "$BACKUP" "$HOMEPAGE_AFTER"
REMOTE
