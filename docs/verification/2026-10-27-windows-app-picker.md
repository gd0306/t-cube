# Windows installed application picker — 0.14.0

“添加应用” opens a searchable installed-app list with names and asynchronously loaded icons. Selection adds to the captured face/slot. Refresh, Escape/cancel, reopening and manual executable browsing are supported. The dialog survives unrelated settings updates.

## Discovery and launch behavior

The fixed, local PowerShell script reads Windows AppsFolder, current/shared Start Menu shortcuts and 32/64-bit App Paths registrations. It requires no administrator access and does not scan the entire disk. Only executable-backed shortcuts and registered application identifiers are accepted; folder/document/uninstaller entries are excluded. Unregistered portable programs remain available through file browsing.

Desktop shortcuts retain their original path, arguments, working directory and other Shell Link properties. Filesystem canonical identities resolve Windows 8.3 aliases for deduplication without rewriting launch paths. Shortcuts are preferred over equivalent bare executable registrations; distinct launch contexts remain separate. Registered virtual/system applications receive an app-owned native shortcut under `%APPDATA%/T-Cube/applications`. Existing configuration schema and file targets remain compatible; back up the whole data folder when migrating.

Discovery and IDs are owned by the main process. IPC permits catalog operations only from the settings main frame, validates request bounds, and looks up opaque catalog IDs before saving. Selection revalidates local targets. The renderer cannot submit arbitrary launch arguments or commands.

## Verification

- Catalog tests began RED with the module absent, then passed. Review identified lost working directories when reducing no-argument shortcuts to executables. A regression demonstrated that failure, and discovery now preserves original shortcuts.
- Native diagnostics subsequently exposed short/long path aliases for the same fixture (`RUNNER~1` versus `runneradmin`). The short-path unit regression failed before the identity fix and passed afterward. Temporary diagnostics were removed; timeout logs omit image data.
- Local Node 22: 65 passed, one Windows-only test skipped; typecheck, build and whitespace checks passed.
- [Windows run 40509030785](https://github.com/gd0306/t-cube/actions/runs/40509030785), commit `1300c0c`: both Windows runner jobs passed all 66 tests, source installation and installed-runtime smoke.
- Smoke creates a uniquely named temporary executable registration and a no-argument Start Menu shortcut with a specific working directory. It checks catalog discovery, icons, search, refresh, cancel/reopen, exactly one alias result, correct destination slot, original shortcut path and working-directory readback. It also saves/readbacks a native virtual-application shortcut. All fixture registrations/files are removed in `finally`; external applications are not launched.
- Inspected the real Windows full-list and filtered-picker captures. The README screenshot comes from this run. Review approved the working-directory and alias fixes, conditional on these now-passing Windows checks.

CI runs on Windows Server images; physical Windows 10/11 acceptance and each third-party application's own runtime behavior remain separate checks. The catalog reflects Windows registrations rather than promising discovery of every unregistered executable.
