#!/bin/bash
# Installed on the server as /usr/local/sbin/enable-tcube-https.
set -euo pipefail
CERT=/opt/ssl/tcube.gd306.cn_nginx/tcube.gd306.cn_bundle.crt
KEY=/opt/ssl/tcube.gd306.cn_nginx/tcube.gd306.cn.key
PENDING=/etc/nginx/t-cube-site-https.conf.pending
ACTIVE=/etc/nginx/t-cube-site.conf
LEGACY=/etc/nginx/t-cube-legacy-locations.conf
PAGE=/var/www/html/t-cube/index.html
for path in "$CERT" "$KEY" "$PENDING"; do
    if ! test -s "$path"; then printf 'Missing or empty file: %s\n' "$path" >&2; exit 1; fi
done
openssl x509 -in "$CERT" -noout -checkend 0
HOST_CHECK="$(openssl x509 -in "$CERT" -noout -checkhost tcube.gd306.cn)"
printf '%s\n' "$HOST_CHECK"
if ! printf '%s\n' "$HOST_CHECK" | grep -Fq 'does match certificate'; then exit 1; fi
CERT_PUBLIC="$(openssl x509 -in "$CERT" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum | cut -d ' ' -f 1)"
KEY_PUBLIC="$(openssl pkey -in "$KEY" -passin pass: -pubout -outform DER | sha256sum | cut -d ' ' -f 1)"
if test "$CERT_PUBLIC" != "$KEY_PUBLIC"; then printf 'Certificate and private key do not match.\n' >&2; exit 1; fi
chmod 600 "$KEY"
nginx -t
BACKUP="/var/backups/t-cube-site/https-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
cp -p "$ACTIVE" "$BACKUP/t-cube-site.conf"
cp -p "$LEGACY" "$BACKUP/t-cube-legacy-locations.conf"
cp -p "$PAGE" "$BACKUP/index.html"
rollback() {
    cp -p "$BACKUP/t-cube-site.conf" "$ACTIVE"
    cp -p "$BACKUP/t-cube-legacy-locations.conf" "$LEGACY"
    cp -p "$BACKUP/index.html" "$PAGE"
    if nginx -t; then nginx -s reload; fi
}
trap 'result=$?; rollback; exit "$result"' ERR
install -m 644 "$PENDING" "$ACTIVE"
sed -i 's|http://tcube.gd306.cn/|https://tcube.gd306.cn/|g' "$LEGACY" "$PAGE"
nginx -t
nginx -s reload
verified=false
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS --max-time 5 --resolve tcube.gd306.cn:443:127.0.0.1 https://tcube.gd306.cn/ -o "$BACKUP/https.html" 2>"$BACKUP/https-check.err" && cmp -s "$BACKUP/https.html" "$PAGE"; then verified=true; break; fi
    sleep 0.2
done
if test "$verified" != true; then
    cat "$BACKUP/https-check.err" >&2
    printf 'HTTPS verification did not pass; restoring the previous configuration.\n' >&2
    false
fi
REDIRECT="$(curl -sS --max-time 5 -o /dev/null -w '%{redirect_url}' --resolve tcube.gd306.cn:80:127.0.0.1 http://tcube.gd306.cn/)"
test "$REDIRECT" = 'https://tcube.gd306.cn/'
trap - ERR
printf 'HTTPS enabled: https://tcube.gd306.cn/\nBackup: %s\n' "$BACKUP"
