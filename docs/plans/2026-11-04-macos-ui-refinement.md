# macOS existing interface refinement

Approved scope: follow the Impeccable audit in order, preserve the existing visual identity and all capabilities, and do not add a preview.

Implementation uses SwiftUI and AppKit only. Work proceeds inline and sequentially in the isolated `refactor/macos-ui-refinement` worktree.

- [x] Separate immediately saved desktop controls from staged appearance controls; name the save/reset scope explicitly. Extract appearance into its own file without changing configuration decoding or saved values.
- [x] Keep material, themes and size readily available. Group custom color/light, theme cycling, and interaction options into disclosures; retain every existing option and validation.
- [x] Make clipboard recording state and selected-content output clear. Move detailed limits/privacy information into a disclosure, retain explicit session-only storage, and put text cleaning behind a disclosure.
- [x] Group the existing status menu, consolidate placement and sizes, use native shortcut fields, and move gesture instructions to a help submenu. Verify nested size selection updates.
- [x] Use consistent readable auxiliary typography and system list selection colors. Check dark/light, long titles, disabled and empty states; retain accessibility labels and avoid new timers/rendering work.

Verification: run focused behavior tests for changed menu routing/state, existing clipboard/appearance/desktop tests and the full serial native suite. Render owned fixtures in both system appearances. Build a signed bundle; back up the installed app and user JSON, quit normally, install and verify executable equality and launch. Record desktop verification limitations separately from automated checks.
