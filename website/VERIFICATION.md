# Website deployment acceptance — 2026-11-21

Production: https://www.gd306.cn/t-cube/

## Scope

New Chinese-first, bilingual product website. No native application code, package version, user application data or installer assets were changed. Existing site homepage and unrelated services are preserved.

## Product and content

- Current GitHub latest was re-read during this task: `v0.22.11`, with macOS arm64 DMG and Windows x64 EXE, checksums and source marker.
- Five complete feature categories follow repository documentation and source, with real native renders and UI captures. Old settings captures showing an Apply flow were excluded.
- Search/multi-entry merge are assigned to the full history manager, rather than claimed as a shared quick-panel capability. Privacy distinguishes volatile history from explicitly saved content; optional GitHub release checks are disclosed.
- Hardware/permission/platform boundaries and unsigned/not-notarized installer requirements are stated. No invented adoption statistics, testimonials, performance benchmarks or universal DDC compatibility claims.

## Browser and functional checks

- Local Playwright: Chinese and English at `320`, `390`, `768`, `1024`, `1440` CSS pixels, with no horizontal page overflow after fixing the native-render container.
- Language toggle and reload persistence; keyboard material tabs (Home/End/arrows); enlarged-image dialog and Escape; native-motion dialog; feature accordion; loaded product images; reduced-motion behavior all passed.
- JavaScript syntax, deployment shell syntax and Python compilation passed.
- Release-refresh validation rejects a foreign download host and incomplete metadata while retaining current HTML/JSON. A simulated future version updates both platform links, checksums and the no-JavaScript fallback version. This is a local simulation, not a new software release.
- The Impeccable detector was run once. Small functional text was enlarged; physical key-cap shadow was softened. Remaining layout warnings were reviewed against rendered results: section insets use padding-block and a max-width child, desktop input imagery uses an actual display-edge diagram, and the two-platform separator is a structural divider. They are not represented as zero warnings.

## Production deployment

- Release directory: `/var/www/t-cube/releases/20261121-134210/public`.
- Active path `/var/www/html/t-cube` is an atomic symlink. Only static public files are exposed; deployment and refresh operations scripts are outside the web root.
- Nginx configuration tests passed before/after publication; no Nginx configuration change or reload was needed.
- Existing homepage SHA-256 before/after: `036013d0010b2c62e9129319e96172eb50a3972b4188937c44199be5cb631a60`.
- Public HTTPS HTML/CSS/JS and 16 assets (19 files) were downloaded and matched to local SHA-256, byte for byte. `release.json` was fetched separately because its server refresh timestamp intentionally differs.
- `t-cube-release-refresh.service`: first production refresh succeeded with `Result=success`, `ExecMainStatus=0`. Its hourly timer is active. No GitHub credential is used; failed network/validation refreshes retain valid existing links.

- Production Playwright: Chinese and English at `320`, `390`, `1440` pixels all matched viewport width; material tab, motion dialog and Escape passed, with no broken product images or JavaScript page errors. The displayed installer URLs match current release metadata.
- Both public installer links returned HTTP `206` for an unauthenticated one-byte range probe.

Local evidence: `.build/website/` (deployment receipt, public-file hash manifest, browser checks, refresh checks). Browser captures were initially written to `output/playwright/` by the Playwright skill.

## Optical redesign — 2026-11-21

Following the user's request, Impeccable A/B assessments independently examined the previous black page. The review and resolution are recorded in `UI-REVIEW.md`. The new page uses a deep-blue animated optical stage alternating with light ice-blue content, fewer generic headings and no repeated instructional captions. Hero effects are user-pausable, pause when offscreen/hidden, and respect reduced motion. Desktop/compact paint caps are 30/20fps with bounded pixel density. Local bilingual layout/interaction and motion-control checks passed; selected body-text contrast is 4.89–5.87:1. The latest download updater remains functional and was retested against invalid, incomplete and simulated future releases. CSS/JS/share-image cache keys were advanced for immediate delivery of the redesigned assets.

The optical revision was published to `/var/www/t-cube/releases/20261121-140304/public`. Nginx validation and the credential-free release-refresh service succeeded; the active timer remains enabled. Existing domain homepage SHA-256 remains `036013d0010b2c62e9129319e96172eb50a3972b4188937c44199be5cb631a60`. Public HTTPS HTML and versioned CSS were fetched and matched to the local files byte-for-byte. Previous website releases remain available for rollback.

Production browser verification also passed Chinese/English at 320/390/1440 pixels, material switching, the native-motion dialog, image loading and live version metadata, with zero page errors. Production motion checks verified changing canvas frames, paused frames, pause persistence, offscreen suspension/re-entry, reduced-motion static frames and localized control labels. Public versioned JavaScript and the refreshed share image also matched local bytes.


## Unified refinement — 2026-11-21

The user's follow-up replaces alternating dark/light sections with one continuous blue-grey surface (`#192938`). CSS was consolidated into a single coherent theme rather than stacking more overrides. The product name leads the hero, material preview and launcher content share a section, the repeated screenshot gallery is removed, feature headings are shorter, and detailed specifications start collapsed. Essential functionality, FAQ, platform requirements, latest downloads and accessible motion controls remain.

Chinese fallback text was regenerated from canonical translation values; the obsolete substring-replacement artifact “辅助桌面工具” is absent, and “辅助功能授权” is correct. An independent read-only review verified the provided desktop/mobile renders and parity of translated fallback elements, without finding blocking issues.

Local Chinese/English checks at 320/390/768/1024/1440 passed with no document horizontal overflow. Material tabs, keyboard selection, enlarged images, demo/Escape, feature details, image loading and reduced motion passed. Motion controls, persistence and offscreen pause/resume passed; selected body-text contrast is approximately 7.33–8.16:1. Release refresh validation still rejects invalid/incomplete data and updates a simulated future version correctly. The mechanical detector reported 12 wrapper-padding warnings; these were checked against actual child spacing and rendered layout, rather than presented as zero warnings or blindly padded.

Evidence for this refinement is under `.build/website/unified/`.

The unified version was deployed to `/var/www/t-cube/releases/20261121-150804/public`. Nginx tests passed, the release refresh service returned `Result=success`/`ExecMainStatus=0`, and the active timer was preserved. The existing domain homepage hash remains unchanged. Public HTML, CSS, JavaScript and share-image downloads match the corresponding local files byte-for-byte.
