# Windows 0.15.1 settings menus and cube color

Release source: `d772a09f1bfda386edc794fd8c3c5dc954547f6b`.

## Reproduction and fix

The settings page unconditionally rebuilt its content after every pointer release. Opening a native select menu therefore removed the select that owned the menu before the user could choose another option. The previous installed smoke used `selectOption`, which bypassed this pointer interaction.

An isolated Electron regression reproduced the failure before the fix: after clicking the material select, its original DOM node was disconnected. A focused-select unit regression also failed before implementation.

Settings now remember whether a redraw is pending, flush only requested redraws after a pointer interaction, and defer replacement while a native select retains focus. Focusout flushes the latest pending configuration. PreferenceQueue continues saving independently of rendering. The same protection applies to material, optical style and cycling interval controls.

Windows glass tint, slime color density and chroma strength were slightly increased. Theme palette values and saved configuration remain compatible. The native macOS client is unchanged by this Windows patch.

## Verification

- Local Node 22: type checking and build passed; 86 tests passed with one Windows-only test skipped.
- The focused-select regression passed after the fix.
- [Windows source installation checks](https://github.com/gd0306/t-cube/actions/runs/40555545021): both Windows 2022 and Windows 2025 runners passed. Their installed smoke clicked each menu, selected another option with ArrowDown/Enter, checked that the original select survived, and verified the stored configuration and visible selected value.
- [Actual NSIS installation check](https://github.com/gd0306/t-cube/actions/runs/40556207172): built and silently installed Windows 0.15.1, then passed the same menu checks and full native input/application discovery/slime/theme/placement/expansion suite.
- Inspected light and dark desktop screenshots. Capture now waits for the backdrop paint before recording the native surface.
- Code review found no blockers. `git diff --check` passed.

Windows GUI tests ran on GitHub-hosted Windows machines. Temporary configuration, application-discovery fixtures and system animation settings are isolated/restored by the smoke suite.

Release: https://github.com/gd0306/t-cube/releases/tag/v0.15.1

Artifact: `T-Cube-0.15.1-windows-x64-setup.exe`, Windows 10 22H2 / Windows 11 x64. The installer includes its runtime, preserves existing configuration, and is not Authenticode signed. Exit the old version before updating.

SHA-256: `03dfab039ad85ba32eda6cab5ceb09daa7108cc452d454cfa6e0a491d00a01bf`. The release includes `SHA256SUMS.txt`.
