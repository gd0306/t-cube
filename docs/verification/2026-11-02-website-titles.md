# Website titles / 0.18.1 (33)

Website entries now paint their existing saved name below the icon, using a single line with ellipsis. The caption shares the curved icon atlas, orientation and scale; its shared geometry is clickable only for websites and follows the existing launch/expand preference. Expanded faces show website captions and full-name hover/accessibility labels. Original titles remain unchanged in configuration. No favicon fetches, network requests, new persistent fields or additional face textures were introduced.

## Automated and visual checks

- macOS red regressions reproduced missing caption pixels, unchanged website-name artwork and absent title-click launch. Tooltip regression reproduced the missing per-entry full name; implementation then passed these cases.
- `swift test --no-parallel --scratch-path .build/tests` passed: 6 XCTest, 115 native Swift Testing and 114 core cases (235 registered: 230 executed/passed, five opt-in render/profile tests skipped). Coverage includes website-only hit areas across all six faces, actual input callbacks, full-title tooltip queries, original-name preservation, single-line bounded rendering and affected-face texture reuse.
- `TCUBE_WEBSITE_PREVIEWS=1 swift test --no-parallel --scratch-path .build/tests --filter 'WebsiteTitle|hoveringAWebsite'` exported actual RealityKit renders and a SwiftUI expanded-panel render under ignored `.build/website-title-previews/`. Inspected dark/light cube renders, Chinese/Emoji, short titles and long-name ellipsis. The initial preview run identified tooltip fallback storage which was fixed before the complete passing suite and app build. The final invocation of the same preview command passed all five selected tests, including the enabled native-render export.
- Windows default/inactive glass hover now reuses native cursor samples through an optional non-persistent hoverPointer. Slime pointer semantics are unchanged; no extra polling or stationary state broadcasts are added. Ray-picking tooltip results are cached across unchanged point/pose/layout/artwork.
- Node 22 typecheck, build and 179 local tests passed (178 passed, one existing Win32-only test skipped on macOS). Added title UV/rotated-face hit cases, grapheme-safe ellipsis and native-only hover cases with no DOM movement.
- Owned headless Chrome UI verification passed against actual renderer code: atlas glyphs, rename updates, non-website caption removal, title click behavior in both modes, expanded truncation and full title/ARIA attributes. Screenshots under ignored `windows/.cache/website-titles/` were inspected. Platform tooltip bubble appearance itself was not separately captured.
- Independent review found and corrected the native fixture's IPC role: target/configuration edits run through the settings page, not the widget. A follow-up review verified native-only hover, authority/null clearing, cache gates and isolated fixtures; no important/critical issues remain.
- Release app build, mounted DMG files/signature/Applications-link verification and `git diff --check` passed.

## Local acceptance

Installed `/Applications/T-Cube.app` version0.18.1 build33, and checked its running executable path. Maintainer quit0.18.0 normally after the native computer-use service failed to connect; no forced termination or alternative GUI automation was used. Old application and all four existing JSON files (including nested JSON) were preserved under ignored `build/install-backups/0.18.1/20261102-011747/`. All JSON bytes matched the post-quit backup immediately after replacement.

Installed and built executable SHA-256: `e7dc7c7bfba2dc6905f8dc4f70e8d921f7bfe1157c65977abacf6b905684f1a9`; deep/strict signature verification passed. Manual interaction with the installed desktop UI was unavailable because the computer-use service remained disconnected. Local rendering was inspected through the isolated native preview artifacts; click and full-title behavior were verified by automated native tests, without replacing user data with fixtures or opening external websites.

## Remote acceptance and publication

[Windows source installation CI](https://github.com/gd0306/t-cube/actions/runs/41331184061) passed on Windows 2022 and 2025 at `b7537372b3225f3a951e412872b3fa884b55fb28`; all179 target-platform unit tests passed. Native smoke verified the inactive widget with a real projected title point and native cursor, complete tooltip/ARIA text, expanded captions/ellipsis, existing paste/templates/backup and rendering behavior. Inspected the real Windows hover and expanded-panel captures. No website was launched.

[Actual NSIS installation verification](https://github.com/gd0306/t-cube/actions/runs/41331216402) passed on its second attempt with no source changes. The first attempt timed out in the existing individual-field paste step: the owned receiver did not append after a logged paste batch; both source-matrix jobs and the identical installer rerun passed the full native flow. The source commit file and build-provided installer checksum were checked after downloading the successful artifact.

Published [0.18.1](https://github.com/gd0306/t-cube/releases/tag/v0.18.1). Remote tag and installer `SOURCE_COMMIT.txt` both match `b7537372b3225f3a951e412872b3fa884b55fb28`. Release is public/non-draft/non-prerelease. All remote asset digests match local artifacts; the publicly downloaded manifest is byte-identical.

| Asset | SHA-256 |
| --- | --- |
| T-Cube-0.18.1-macos-arm64.dmg | f637f5c5df0bf5c0ecf5b705c5fafe794c17937c8edf8b10b53a63f93468d334 |
| T-Cube-0.18.1-windows-x64-setup.exe | aa9be5f46fb3f5f4bd554c5988b6268e2f01918c3dc2e15242ab4614a3a3382d |
| SHA256SUMS.txt | 8b3eb441ea4f02da76dce96b75620485df531c9ab4d669a2da716611b466718b |

The [native expanded-panel preview](../images/website-titles-expanded.png) contains only owned sample entries. Existing ad-hoc macOS signing and unsigned Windows distribution remain as disclosed in the release notes.
