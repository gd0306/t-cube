# Windows signed updates

Windows 0.16.0 uses the pinned `electron-updater` 6.8.11 NSIS updater. The runtime uses the public HTTPS GitHub feed for `gd0306/t-cube`; no API credential is embedded. The publisher identity is baked into the installer from `TCUBE_UPDATE_PUBLISHER`, not accepted from renderer requests or runtime URLs. With no publisher configured, update checks, downloads and installation are disabled and settings links to Releases for manual installation.

Automatic checks default to off and persist in the application's `userData/lifecycle-preferences.json`. Enabling automatic checks schedules one check every six hours. Every download prompts the user; every installation prompts again. Closing T-Cube does not automatically install an update. Login startup is independent and reads the actual OS login state; startup and CI never enable it automatically.

## Signing a release

Supply an owner-controlled Authenticode certificate via electron-builder's `CSC_LINK` and `CSC_KEY_PASSWORD` secrets (Windows-specific `WIN_CSC_LINK` and `WIN_CSC_KEY_PASSWORD` are also supported by the builder). Set `TCUBE_UPDATE_PUBLISHER` to the exact certificate publisher subject name. Keep the same trusted identity on subsequent releases, and coordinate certificate rotation before release. The repository contains no signing certificate or fabricated key. Existing certificate-store or external signing setups can use the equivalent electron-builder Windows signing configuration.

Run `npm ci`, `npm run build`, then `npm run package:win` in `windows/` on Windows. Packaging uses `--publish never`, so generating an installer never publishes it. The configured GitHub provider causes electron-builder to generate `app-update.yml` inside the packaged resources and release update metadata such as `latest.yml`. Keep `verifyUpdateCodeSignature: true` and the updater's default Authenticode verification. Do not override its signature verifier.

Publish the exact verified `T-Cube-0.16.0-windows-x64-setup.exe`, its `.blockmap`, and `latest.yml` together on the Windows release tag. Verify the metadata references that installer, compare SHA-512/hash and file size against the uploaded asset, and run the actual installer verification before publishing. Unsigned installers may still be distributed for manual installation with the publisher environment omitted; such builds visibly leave updates disabled.

## Local data maintenance

The maintenance page exports a portable version-1 JSON archive containing the validated Windows configuration and the macOS-compatible content-library schema. macOS application launcher paths cannot be imported as Windows paths; they fail validation instead of silently changing launch targets. Import previews retain validated data behind an opaque five-minute, single-use token. Confirmation first validates both live files and creates a local pre-import archive, then atomically replaces both files. A failed replacement restores original bytes (including absence of a previously missing file). Corrupt live data is never replaced by import/export. Stores share path locks so ordinary settings and content edits cannot interleave with a restore. Export destinations cannot alias either live data file through case, symlinks or hard links.

Official references: [electron-builder v26 auto-update](https://www.electron.build/v26/docs/features/auto-update/), [Windows signing](https://www.electron.build/v26/docs/features/code-signing/), [Electron login items](https://www.electronjs.org/docs/latest/api/app#appsetloginitemsettingssettings-macos-windows).
