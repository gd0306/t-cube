# T-Cube product page

Chinese-first bilingual static website for https://www.gd306.cn/t-cube/.

- `index.html`, `style.css`, `app.js`: dependency-free page, keyboard material tabs, native image dialogs and remembered language selection.
- `assets/`: actual native renders/UI captures from `docs/images/` and self-hosted Manrope fonts (OFL license included).
- `release.json`: validated latest stable release with platform installers, sizes and checksums.
- `refresh-release.py`: credential-free GitHub stable-release refresh; rejects incomplete releases and keeps previous valid files if fetching or validation fails. Atomically updates JSON and the HTML's no-JavaScript fallback links.
- `t-cube-release-refresh.*`: hourly systemd refresh on the maintainer's existing server; not a browser background task.

Preview:

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory website
```

Only HTML/CSS/JS, `release.json`, and `assets/` are publicly deployed. Operations scripts and design/verification notes remain outside the web root. Releases live under `/var/www/t-cube/releases/`; `/var/www/html/t-cube` selects the active release. Prior releases and the existing domain homepage remain intact. Deployment and verification evidence is kept under ignored `.build/website/`.

Deploy using the maintainer's authorized SSH credentials (no credentials are stored in this repository):

```bash
TCUBE_SITE_HOST=root@your-server bash website/deploy.sh
```

On this maintainer Mac, `TCUBE_SITE_INTERFACE=en0` selects the previously verified direct network route when ordinary SSH is intercepted by a local proxy. `deploy.sh` backs up the active route, verifies the transfer, tests Nginx, switches an atomic symlink, starts the refresh service, and verifies that the domain homepage is unchanged.

Rollback: repoint `/var/www/html/t-cube` atomically to a retained release's `public/` directory. Do not remove releases while they are active or referenced by rollback backups.

The two static files are updated independently and atomically. Network errors, incomplete releases and invalid asset hosts are rejected before writes; a filesystem error between replacements can leave new validated JSON with the older valid HTML fallback, rather than breaking existing downloads.
