# Desktop and clipboard tools implementation plan

> Agentic execution uses executing-plans and independent platform tasks with review before integration.

**Goal:** Deliver the user's approved desktop auto-hide and clipboard tools on macOS and Windows, including the requested separate image history of at most ten entries.

**Architecture:** Extend existing desktop window coordination and session-only clipboard history. Preserve existing configuration decoding, rendering/input behavior, focus-checked paste and default-off recording. Keep transient presentation geometry separate from saved resting positions. No new dependencies or cloud service.

**Approved requirements:** User selected suggestions 6 (edge collapse and full-screen hiding) and 7 (multi-text merge/cleanup), then requested text/image classification with ten recent images.

## Desktop task
- [x] Add independent default-off edge-collapse and full-screen-hide preferences. Place controls in existing appearance settings.
- [x] Test geometry: collapse only when a resting cube is near an outer usable edge; expose a narrow handle within the usable display; restore the actual resting frame on pointer entry; never persist collapsed coordinates. Leave ordinary interior placements unchanged.
- [x] Integrate a small native edge handle, delayed collapse, hover/drag/expanded-panel protection and settings/topology restoration. Manual tray hide remains hidden when full-screen exits. Full-screen hide restores only automatically hidden cubes, on the cube's display; exclude our own windows. Stop rendering while hidden/collapsed and release timers on shutdown.
- [x] Verify both state transitions and native window integration using isolated windows. Use supported public OS window information; require no new screen-recording permission. Verify detector fallback behavior when OS information is unavailable.

## Clipboard task
- [x] Test and add text/image categories. Preserve text limits (100 entries,64 KiB each,2 MiB total). Add at most10 images,8 MiB encoded each,32 MiB encoded total and16 megapixels each; oldest-first eviction. Keep only compressed image bytes plus bounded thumbnails; decode a bounded selected preview on demand.
- [x] Record new native image clipboard data only after enable/resume baseline; reject excluded/private/file-drop formats before reading; recheck sequence/generation after native reads. Deduplicate image payloads, promote duplicates and skip own writes. Clear/shutdown releases all image data. No persistence or export.
- [x] Add image thumbnails and preview with copy/focus-checked paste/delete/clear; use original normalized image payload for copy, without OCR or implicit snippet conversion.
- [x] Add multi-select text with deterministic visible order, newline joining, optional per-line trim and collapse of repeated blank lines. Show preview before copying/pasting/saving; never mutate original history. Enforce bounded merged output, clear stale selection on filters/deletion.
- [x] Test actual clipboard encoding with owned named pasteboards/fixtures, no real user clipboard in logs. Windows native smoke uses an owned receiver and image fixtures.

## Integration and acceptance
- [x] Independently review desktop state/position safety and clipboard size/privacy/paste paths; resolve important findings.
- [x] Run full Swift tests serially, Node22 typecheck/tests/build; inspect native/renderer screenshots. Distinguish automated evidence from manual desktop verification.
- [x] Bump dual-platform version, build/verify DMG, normally quit previous installed app, preserve it and all recursive user JSON files, install `/Applications/T-Cube.app`, compare executable hashes and launch.
- [x] Push master after verified integration; run Windows source matrix and actual NSIS installation CI; validate source and artifact checksums; publish dual-platform Release and verification record.
