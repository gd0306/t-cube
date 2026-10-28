# macOS signing and authenticated updates

T-Cube embeds the official Sparkle 2.10.0 binary framework, pinned in `Package.swift` and `Package.resolved`. The updater uses Sparkle's standard check, download, signature validation, install, and relaunch UI. Automatic checks start disabled; users can enable them in settings. Installations always require confirmation. `SUVerifyUpdateBeforeExtraction` requires authentication before unpacking an archive.

The checked-in appcast is intentionally empty. No release is published by building or pushing this repository. The default application has an empty `SUPublicEDKey`, so in-app update checks remain disabled with a visible explanation and a link to GitHub Releases. Setting a feed URL alone never enables updates. Existing installations without Sparkle need a one-time manual upgrade.

## Production prerequisites

1. Obtain a **Developer ID Application** identity and a notarization credential/profile from the Apple Developer account owner. An Apple Development identity is for local development and does not provide Developer ID distribution. The repository and build scripts do not create identities, alter the Keychain, or contain credentials.
2. The release owner should deliberately generate an Ed25519 key pair using Sparkle's `generate_keys` tool. This writes a private key to that owner's Keychain; back it up securely according to Sparkle's documentation. Never commit or upload the private key, include it in an app, or place it on the feed host. Only the base64 public key belongs in the build configuration.
3. Configure a durable HTTPS appcast endpoint. The repository's default is `https://raw.githubusercontent.com/gd0306/t-cube/master/docs/updates/appcast.xml`. It becomes public when the containing commit is on `master`; GitHub's raw content caching can delay visibility.

## Build and notarize

Increment both `CFBundleVersion` (monotonically increasing, used by Sparkle) and `CFBundleShortVersionString` in `Resources/Info.plist` for a release. Example, with values supplied by the release owner:

```bash
export TCUBE_SIGN_IDENTITY='Developer ID Application: Your Organization (TEAMID)'
export TCUBE_UPDATE_PUBLIC_KEY='YOUR_BASE64_ED25519_PUBLIC_KEY'
export TCUBE_UPDATE_FEED_URL='https://raw.githubusercontent.com/gd0306/t-cube/master/docs/updates/appcast.xml'
export TCUBE_NOTARY_PROFILE='your-existing-notarytool-profile'
bash scripts/build-dmg.sh
bash scripts/verify-dmg.sh
```

`build-app.sh` embeds Sparkle under `Contents/Frameworks` with symlinks and permissions preserved. The executable has `@executable_path/../Frameworks` in its runtime search paths. The script signs the installer/downloader XPC services, Autoupdate executable, Updater.app, framework, then app individually. A provided identity enables Hardened Runtime and secure timestamps. With no identity it produces an ad-hoc local app, which is not a notarized distribution build. Signing does not use `--deep`; verification does.

`build-dmg.sh` signs the disk image when an identity is supplied. With `TCUBE_NOTARY_PROFILE`, it submits the DMG, waits for Apple's result, staples and validates its ticket. The profile must already exist. Notarization requires a `Developer ID Application:` identity name. Merely selecting an Apple Development identity is insufficient. Without a profile, signing and packaging finish without claiming notarization. This build targets the build machine's architecture; create and validate separate architecture artifacts or deliberately adopt a universal build before distributing to both Intel and Apple silicon.

## Sign and publish the update

Sparkle's SwiftPM tools are in `.build/app/artifacts/sparkle/Sparkle/bin/` (inspect the resolved artifact directory if the package manager layout changes). Use the matching official `generate_appcast` tool on a directory containing the **final** notarized and stapled release archive. The tool reads the owner's signing key, produces the EdDSA signature and archive length, and includes version metadata. Alternatively use `sign_update` and follow the official publishing guide. Sign only after the final archive bytes are fixed; changing a DMG after signing invalidates its EdDSA signature.

Upload the archive to a GitHub Release or equivalent HTTPS host, then publish the generated appcast with the exact archive URL, `sparkle:edSignature`, length, `sparkle:version`, `sparkle:shortVersionString`, and minimum macOS version (15.0 for T-Cube). Never publish placeholder signatures or advertise an archive that is not yet accessible. The current feed does not require a separately signed feed; update **archives** always require EdDSA authentication. Optional signed-feed adoption needs Sparkle's additional configuration and signing workflow.

Validate on an older installed build with the production public key: manual check, enabled/disabled automatic checks across restart, a valid update install/relaunch, a rejected tampered archive, unavailable feed, and bad signature. Validate login enabled, disabled, and “requires approval” in a logged-in desktop; login registration happens only after the user changes the toggle. Keep testing off the user's actual launcher configuration or back it up first.

Release activation remains blocked until the owner provides the public key and controls its matching private key, a production signing identity, and notarization credentials. An empty appcast is valid but offers no update.

Primary references: [Sparkle setup](https://sparkle-project.org/documentation/), [programmatic integration](https://sparkle-project.org/documentation/programmatic-setup/), [manual nested signing](https://sparkle-project.org/documentation/sandboxing/#code-signing), [publishing](https://sparkle-project.org/documentation/publishing/), [Sparkle releases](https://github.com/sparkle-project/Sparkle/releases), [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice).
