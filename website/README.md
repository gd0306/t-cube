# T-Cube product page

Chinese-first bilingual static website for https://tcube.gd306.cn/.

- `index.html`, `style.css`, `app.js`: dependency-free page with keyboard material tabs, native image dialogs, remembered language selection, a keyboard-accessible system/light/dark theme switcher with a saved preference, and an interactive hero particle canvas.
- `copy.json`: reference bilingual copy inventory. It is not loaded by the page or included in deployment, and there is no automatic synchronization with `app.js`. Runtime translations are inline in `app.js` (`translations` and theme labels); update those and the matching default HTML text when changing visible copy, and keep this reference inventory aligned.
- `assets/`: actual native renders/UI captures from `docs/images/` and self-hosted Nunito Sans / Roboto Condensed fallbacks (OFL licenses included); installed Avenir Next / Avenir Next Condensed take priority.
- `release.json`: validated latest stable release with platform installers, sizes and checksums.
- `refresh-release.py`: credential-free GitHub stable-release refresh; rejects incomplete releases and keeps previous valid files if fetching or validation fails. Atomically updates JSON and the HTML's no-JavaScript fallback links.
- `t-cube-release-refresh.*`: hourly systemd refresh on the maintainer's existing server; not a browser background task.
- `deploy.sh`: package and deploy the public site plus server-side release-refresh tooling.
- `nginx/`, `configure-domain.sh`: dedicated-domain routing templates and HTTP bootstrap.
- `prepare-https.sh`, `enable-https.sh`: stage TLS configuration and install the server activation helper, then enable HTTPS after certificates are supplied.

Preview:

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory website
```

`deploy.sh` publishes only `index.html`, `style.css`, `app.js`, `release.json`, and `assets/` in each release's `public/` directory. It also transfers `refresh-release.py` and `t-cube-release-refresh.{service,timer}` in a separate `ops/` directory, then installs the refresh script at `/opt/t-cube-site/refresh-release.py` and the units under `/etc/systemd/system/`. These operations files stay outside the web root; `copy.json` and design/verification notes are not included in the deployment package.

Releases live under `/var/www/t-cube/releases/`; `/var/www/html/t-cube` selects the active release's `public/` directory. Prior releases and the existing domain homepage remain intact. Deployment and verification evidence is kept under ignored `.build/website/`.

Deploy using the maintainer's authorized SSH credentials (no credentials are stored in this repository):

```bash
TCUBE_SITE_HOST=root@your-server bash website/deploy.sh
```

`TCUBE_SITE_INTERFACE` is an optional troubleshooting parameter for binding SSH/SCP to a specific local interface when a proxy interferes. For example, this maintainer Mac has used `TCUBE_SITE_INTERFACE=en0`; verify the interface on the current machine before using it. Normal deployment needs only `TCUBE_SITE_HOST`.

`deploy.sh` backs up the active route, verifies the transfer, tests Nginx, switches an atomic symlink, starts the refresh service, and verifies that the domain homepage is unchanged.

Rollback: repoint `/var/www/html/t-cube` atomically to a retained release's `public/` directory. Do not remove releases while they are active or referenced by rollback backups.

The two static files are updated independently and atomically. Network errors, incomplete releases and invalid asset hosts are rejected before writes; a filesystem error between replacements can leave new validated JSON with the older valid HTML fallback, rather than breaking existing downloads.

Dedicated domain bootstrap (HTTP before certificate activation):

```bash
TCUBE_SITE_HOST=root@your-server bash website/configure-domain.sh
```

This installs `nginx/t-cube-site.conf` at `/etc/nginx/t-cube-site.conf` and includes it after the existing default servers, preserving their routing. The bootstrap serves the active product release directly at `http://tcube.gd306.cn/` (redirected to `https://tcube.gd306.cn/` after HTTPS activation); no `/t-cube` URL prefix is required. `/etc/nginx/t-cube-legacy-locations.conf` redirects old product paths to the new root while retaining asset paths and query parameters. The existing main HTTP site may first redirect an old link to HTTPS before it reaches the product redirect. GitHub repository and official release installer URLs remain on GitHub.

The root/index HTML and release metadata use `Cache-Control: no-cache` so browsers revalidate migration and release changes.

The configuration script backs up the main config and owned include files under `/var/backups/t-cube-site/domain-*`, runs `nginx -t`, gracefully reloads the running Nginx master with `nginx -s reload`, and verifies the new host, legacy asset redirect and unchanged personal homepage. A failed verification restores those backed-up configuration files. The HTTP bootstrap does not enable TLS by itself; see the HTTPS activation steps below. After the domain is configured, use `deploy.sh` normally; it now verifies the dedicated HTTP origin. Physical release directories and the refresh timer remain unchanged.

### Prepare and enable HTTPS

The prepared TLS template mirrors the existing main site's SSL cache, timeout and cipher settings. Stage it without changing the active HTTP site:

```bash
TCUBE_SITE_HOST=root@your-server bash website/prepare-https.sh
```

This stages `nginx/t-cube-site-https.conf` at `/etc/nginx/t-cube-site-https.conf.pending` and installs the repository's `website/enable-https.sh` as the server command `/usr/local/sbin/enable-tcube-https`. It leaves the active site configuration unchanged.

Upload the Nginx/PEM certificate bundle (leaf certificate followed by intermediate certificates) and matching unencrypted PEM private key to:

- `/opt/ssl/tcube.gd306.cn_nginx/tcube.gd306.cn_bundle.crt`
- `/opt/ssl/tcube.gd306.cn_nginx/tcube.gd306.cn.key`

Then run on the server:

```bash
sudo /usr/local/sbin/enable-tcube-https
```

The staged template lives at `/etc/nginx/t-cube-site-https.conf.pending`. The activation helper checks expiry, hostname coverage and key matching, sets private-key mode `600`, backs up the active site/legacy redirects/HTML, installs the TLS server, validates Nginx and reloads gracefully. It verifies the HTTPS response with normal certificate verification and enables the HTTP-to-HTTPS redirect; a failure restores the previous configuration and HTML. It also changes current canonical/share metadata and legacy redirects to HTTPS. The helper is not an automatic certificate-renewal service.

Future content deployments detect an enabled TLS server, preserve HTTPS metadata and verify that origin. Re-running `configure-domain.sh` preserves an already-enabled TLS server instead of reverting it to HTTP. The main site's existing certificate covers only `gd306.cn` and `www.gd306.cn`; the uploaded certificate must cover `tcube.gd306.cn` or a matching wildcard.
