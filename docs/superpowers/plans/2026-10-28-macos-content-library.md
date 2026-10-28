# macOS Common Content Library Implementation Plan

**Goal:** Implement the user-approved first macOS prototype, install locally, and verify saving, search, favorites, whole/field copy, hotkey invocation and paste back to the originating field.

**Architecture:** Independent Codable library and atomic store in CubeCore; observable editor/library UI in SwiftUI; AppKit controller provides invocation, clipboard and focus-checked paste. Existing launcher configuration remains untouched.

**Spec:** User-approved discussion in this conversation: ordinary office staff repeatedly copying/filling common information; first iteration includes groups, favorites, search and copy/paste. Templates are a later enhancement.

## Constraints
- macOS 15+, Swift 6; no extra dependencies.
- Separate content-library.json; preserve invalid files, report failures; tests use temporary stores.
- Manual save/drop from clipboard only; no background clipboard history.
- Fixed Command+Shift+Space global shortcut with registration-error feedback.
- Copy always works; direct paste requires Accessibility permission, a live external target and original focused element; otherwise keep copied text with an actionable status.
- Work stays on feat/macos-content-library and is installed on this Mac; do not publish or merge.

## Tasks
- [x] Core: SnippetField/TextSnippet/SnippetLibrary/SnippetStore, validation, search, rendering, stable favorites and persistence regression tests (red/green).
- [x] UI: SnippetLibraryModel and SnippetLibraryView, create/edit/delete, group/filter/search/favorites/order, drag text and explicit clipboard capture, whole/field actions; test model using temporary stores.
- [x] Native integration: hotkey/menu/cube-adjacent entry, window positioning, clipboard and focus-safe paste; native policy tests.
- [x] Review, full relevant tests, build bundled app, preserve installed app backup, install and launch locally; verify real copy/paste flow where system permissions permit.

Verification: docs/verification/2026-10-28-macos-content-library.md. Permission-dependent cross-app paste and physical global shortcut remain user trial items, explicitly documented.
