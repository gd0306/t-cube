# macOS common content library prototype

Branch: `feat/macos-content-library`. Local macOS experiment, version 0.16.0/build 26.

## Delivered

- Separate Foundation Codable library and atomic `content-library.json` store under Application Support/T-Cube. Invalid/unsupported data is preserved and blocks replacement. Launcher configuration is independent.
- Native SwiftUI list/detail panel: create/edit/delete, groups, favorites, stable displayed ordering, title/body/group/field search, multi-line body and separately usable labeled fields.
- Whole text rendering and field-value copy/paste actions. Explicit clipboard capture and dragging text into the panel/cube open an editable draft before saving.
- Menu-bar entry, application-menu entry, hover-only cube button and Command+Shift+Space registration. Esc dismisses and reactivates the original external app. Panel opens near the pointer and focuses search.
- Direct paste copies first, checks Accessibility permission, captured external process and original AX text input identity, then posts Command-V to that PID only. Missing permission, missing field, changed focus or changed clipboard falls back to copy/status. Paste does not submit forms.

## Verification

`swift test --scratch-path .build/tests` passed: 4 native XCTest cases, 57 native Swift Testing cases and 79 core cases. Three opt-in image export checks were skipped in this normal run. New regression cases cover validation/search/text rendering, round-trip persistence/corrupt preservation, save failures/filter selection/favorite ordering, and paste eligibility. Targeted core/model red-green verification recorded during implementation.

`swift build --scratch-path .build/snippet-app`, `bash scripts/build-app.sh --debug` and `git diff --check` passed. Native review fixes included PID-scoped event posting, editable-role validation, Carbon event ID filtering and durable pending text capture before the first view appearance.

Installed to `/Applications/T-Cube.app` and launched its content panel. Computer-use verification observed the empty list, focused search, new-content sheet, add-field controls, cancellation retaining zero records, Esc dismissal and Command+Shift+Space reopening. The initial global-only shortcut was not exercised by process-targeted computer input; the matching native app-menu shortcut was added and the observed reopen check passed. Physical global shortcut behavior outside T-Cube still needs user trial.

No fixture content was saved in the user's library. Cross-application paste was not manually exercised: the user must authorize this ad-hoc-signed T-Cube build under System Settings → Privacy & Security → Accessibility. Copy is available independently. Automated paste policy checks do not replace that manual permission-dependent verification.

Old bundled app backup: `build/backups/T-Cube-before-content-library.app`. The active experimental app is `/Applications/T-Cube.app`; `build/T-Cube.app` contains the same bundle. No merge, push or release was performed for this experiment.
