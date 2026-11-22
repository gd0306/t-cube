#!/bin/bash
# Stage the HTTPS config and activation command; keep HTTP active until certificates exist.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TCUBE_SITE_HOST="${TCUBE_SITE_HOST:?Set TCUBE_SITE_HOST to the authorized SSH target}"
CHANGE_ID="https-ready-$(date +%Y%m%d-%H%M%S)"
STAGE="$ROOT/.build/website/$CHANGE_ID"
mkdir -p "$STAGE"
cp "$ROOT/website/nginx/t-cube-site-https.conf" "$STAGE/"
cp "$ROOT/website/enable-https.sh" "$STAGE/"
COPYFILE_DISABLE=1 tar -czf "$STAGE.tar.gz" -C "$STAGE" t-cube-site-https.conf enable-https.sh
SSH_ARGS=(-o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o ConnectTimeout=20)
if [[ -n "${TCUBE_SITE_INTERFACE:-}" ]]; then SSH_ARGS+=(-o "ProxyCommand=nc -b $TCUBE_SITE_INTERFACE -w 25 %h %p"); fi
scp "${SSH_ARGS[@]}" "$STAGE.tar.gz" "$TCUBE_SITE_HOST:/tmp/$CHANGE_ID.tar.gz"
ssh "${SSH_ARGS[@]}" "$TCUBE_SITE_HOST" "bash -s -- '$CHANGE_ID'" <<'REMOTE'
set -euo pipefail
CHANGE_ID="$1"
BACKUP="/var/backups/t-cube-site/$CHANGE_ID"
mkdir -p "$BACKUP/incoming"
nginx -t
ACTIVE_BEFORE="$(sha256sum /etc/nginx/t-cube-site.conf | cut -d ' ' -f 1)"
for path in /etc/nginx/t-cube-site-https.conf.pending /usr/local/sbin/enable-tcube-https; do
    if test -e "$path"; then cp -p "$path" "$BACKUP/$(basename "$path")"; fi
done
tar -xzf "/tmp/$CHANGE_ID.tar.gz" -C "$BACKUP/incoming"
install -d -m 750 /opt/ssl/tcube.gd306.cn_nginx
install -m 644 "$BACKUP/incoming/t-cube-site-https.conf" /etc/nginx/t-cube-site-https.conf.pending
install -m 750 "$BACKUP/incoming/enable-https.sh" /usr/local/sbin/enable-tcube-https
bash -n /usr/local/sbin/enable-tcube-https
# Parse the prepared template without enabling it or placing substitute certs
# in the maintainer's certificate directory. The existing main certificate is
# used only for this isolated nginx -t parser check, never for the new vhost.
python3 - "$BACKUP" <<'PY'
from pathlib import Path
import sys
text = Path('/etc/nginx/t-cube-site-https.conf.pending').read_text()
text = text.replace('/opt/ssl/tcube.gd306.cn_nginx/tcube.gd306.cn_bundle.crt', '/opt/ssl/gd306.cn_nginx/gd306.cn_bundle.crt')
text = text.replace('/opt/ssl/tcube.gd306.cn_nginx/tcube.gd306.cn.key', '/opt/ssl/gd306.cn_nginx/gd306.cn.key')
Path(sys.argv[1], 'syntax-check.conf').write_text('events {}\nhttp {\ninclude /etc/nginx/mime.types;\n' + text + '\n}\n')
PY
nginx -t -c "$BACKUP/syntax-check.conf"
nginx -t
ACTIVE_AFTER="$(sha256sum /etc/nginx/t-cube-site.conf | cut -d ' ' -f 1)"
test "$ACTIVE_BEFORE" = "$ACTIVE_AFTER"
rm -f "/tmp/$CHANGE_ID.tar.gz"
printf 'PREPARED /etc/nginx/t-cube-site-https.conf.pending\nCERT /opt/ssl/tcube.gd306.cn_nginx/tcube.gd306.cn_bundle.crt\nKEY /opt/ssl/tcube.gd306.cn_nginx/tcube.gd306.cn.key\nACTIVATE /usr/local/sbin/enable-tcube-https\nBACKUP %s\n' "$BACKUP"
REMOTE
