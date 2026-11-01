# Website titles / 0.18.1 (33)

Website entries now paint their existing saved name below the icon, using a single line with ellipsis. The caption shares the curved icon atlas, orientation and scale; its shared geometry is clickable only for websites and follows the existing launch/expand preference. Expanded faces show website captions and full-name hover/accessibility labels. Original titles remain unchanged in configuration. No favicon fetches, network requests, new persistent fields or additional face textures were introduced.

## Automated and visual checks

- macOS red regressions reproduced missing caption pixels, unchanged website-name artwork and absent title-click launch. Tooltip regression reproduced the missing per-entry full name; implementation then passed these cases.
- `swift test --no-parallel --scratch-path .build/tests` passed: 6 XCTest, 115 native Swift Testing and 114 core cases (235 total). Coverage includes website-only hit areas across all six faces, actual input callbacks, full-title tooltip queries, original-name preservation, single-line bounded rendering and affected-face texture reuse.
- `TCUBE_WEBSITE_PREVIEWS=1 swift test --no-parallel --scratch-path .build/tests --filter 'WebsiteTitle|hoveringAWebsite'` exported actual RealityKit renders and a SwiftUI expanded-panel render under ignored `.build/website-title-previews/`. Inspected dark/light cube renders, Chinese/Emoji, short titles and long-name ellipsis. The initial preview run identified tooltip fallback storage which was fixed before the complete passing suite and app build.
- Windows default/inactive glass hover now reuses native cursor samples through an optional non-persistent hoverPointer. Slime pointer semantics are unchanged; no extra polling or stationary state broadcasts are added. Ray-picking tooltip results are cached across unchanged point/pose/layout/artwork.
- Node 22 typecheck, build and 179 local tests passed (178 passed, one existing Win32-only test skipped on macOS). Added title UV/rotated-face hit cases, grapheme-safe ellipsis and native-only hover cases with no DOM movement.
- Owned headless Chrome UI verification passed against actual renderer code: atlas glyphs, rename updates, non-website caption removal, title click behavior in both modes, expanded truncation and full title/ARIA attributes. Screenshots under ignored `windows/.cache/website-titles/` were inspected. Platform tooltip bubble appearance itself was not separately captured.
- Independent review found and corrected the native fixture's IPC role: target/configuration edits run through the settings page, not the widget. A follow-up review verified native-only hover, authority/null clearing, cache gates and isolated fixtures; no important/critical issues remain.
- Release app build, mounted DMG files/signature/Applications-link verification and `git diff --check` passed.

## Local acceptance

Installed `/Applications/T-Cube.app` version0.18.1 build33, and checked its running executable path. Maintainer quit0.18.0 normally after the native computer-use service failed to connect; no forced termination or alternative GUI automation was used. Old application and all four existing JSON files (including nested JSON) were preserved under ignored `build/install-backups/0.18.1/20261102-011747/`. All JSON bytes matched the post-quit backup immediately after replacement.

Installed and built executable SHA-256: `e7dc7c7bfba2dc6905f8dc4f70e8d921f7bfe1157c65977abacf6b905684f1a9`; deep/strict signature verification passed. Manual interaction with the installed desktop UI was unavailable because the computer-use service remained disconnected. Local rendering was inspected through the isolated native preview artifacts; click and full-title behavior were verified by automated native tests, without replacing user data with fixtures or opening external websites.

Remote Windows installation and release publication verification will be recorded after CI completes.
