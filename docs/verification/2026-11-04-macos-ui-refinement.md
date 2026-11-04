# macOS 0.21.1 interface refinement verification

Implemented the approved Impeccable audit in order, within the existing native interface. No preview feature, new renderer, timer, polling task, package dependency, configuration schema, or clipboard retention change was added.

## Delivered behavior

1. **Save scope**: Appearance retains staged changes, validation, apply and reset. Its footer names this page explicitly. Edge collapse, fullscreen hiding, quick placement and idle power saving now appear together under **桌面与性能**, with a visible immediately-saved notice.
2. **Appearance hierarchy**: Material, all nine themes and size remain readily available. Custom colors/light, theme cycling, interaction/animation and operating instructions are expandable. Every original setting, interval, preset and validation remains accessible.
3. **Clipboard hierarchy**: The header exposes recording/paused state and session-only lifetime. Recording details contain privacy limitations and capacity information; category limits remain visible. Paste is the primary output action; cleanup options remain in an expandable group. Text and images retain their existing bounds, including the most recent ten images.
4. **Status menu**: Layout contains placement and sizes; content actions and maintenance actions are separated. The content shortcut uses native menu key/modifier fields. Gesture instructions occupy a help submenu. Brightness remains directly accessible at the top and uses the original on-demand controller.
5. **Typography and selection**: Shared desktop text roles replace fixed 10pt paths and auxiliary labels. Full paths are available through help text. Clipboard records use native inset lists with hierarchical primary/secondary text, removing hard-coded white selection text.

The collapsed glass handle and cube rendering/material implementation were not modified.

## Automated checks

```sh
env TCUBE_INTERFACE_PREVIEWS=1 TCUBE_CLIPBOARD_PREVIEWS=1 TCUBE_BRIGHTNESS_PREVIEWS=1 \
  swift test --scratch-path /Users/gd/Git/t-cube/.build/ui-refinement-tests --no-parallel
bash scripts/build-app.sh
git diff --check
codesign --verify --deep --strict /Applications/T-Cube.app
```

- Final serial run: **289 Swift Testing cases + 7 XCTest cases passed; 10 conditional cases skipped; no failures**. Skips include physical brightness adjustments and unrelated opt-in scene/diagnostic exporters. This pass did not change actual display brightness.
- Two new menu tests exercise real native action dispatch, native shortcut modifiers, placement routing and size checkmark refresh inside the nested layout menu.
- Settings exporter renders actual current views with temporary configuration and isolated UserDefaults. It also verifies the fixture configuration is semantically unchanged after rendering. Clipboard exporter uses an isolated named pasteboard and now covers both appearances.
- Release bundle build and deep/strict installed signature verification passed.
- Independent code review found no remaining blocking issues after the selection correction below.

Logs are preserved under the main checkout's ignored `.build/impeccable-review/`: `refinement-final-tests.log`, `refinement-build.log` and `menu-green.log`.

## Visual verification

Inspected the generated appearance/desktop settings and selected text/image history in light and dark appearances. Native SwiftUI tab-bar/window chrome is not fully represented by view-cache exports; these are owned-view fixtures, not screenshots of a manually operated installed app.

The first sidebar-list experiment made selected text unreadable in the owned light capture. Explicit primary text alone did not fix it. Switching the history to the system's **inset list** style resolved the selection background and foreground together. Temporary custom selection backgrounds and inset overrides were removed. The final four history captures show readable selected text and metadata without a custom selection layer. This preserves native keyboard/multiple-selection behavior.

- [Appearance, light](../images/settings-appearance-light.png) / [dark](../images/settings-appearance-dark.png)
- [Desktop and performance, light](../images/settings-desktop-light.png) / [dark](../images/settings-desktop-dark.png)
- [Text history, light](../images/clipboard-text-tools.png) / [dark](../images/clipboard-text-tools-dark.png)
- [Image history, light](../images/clipboard-image-tools.png) / [dark](../images/clipboard-image-tools-dark.png)

The implementation uses system hierarchical colors rather than a custom foreground-only selection override; see [Apple's UI color roles](https://developer.apple.com/documentation/appkit/ui-element-colors).

## Installed version acceptance

- Installed **0.21.1, build 40** into `/Applications/T-Cube.app`.
- Preserved the previous 0.21.0/build 39 application and four existing JSON files, both before and after normal termination, under `build/install-backups/0.21.1/20261104-213809/`.
- The previous installed process, PID 20452, accepted normal termination through `NSRunningApplication.terminate()` and exited before replacement. No forced signal termination was used.
- Built and installed executable SHA-256 both equal:

  ```text
  cd74ab872a34b5ba719769273f796a2dd763bcf8185d95b0ff737024cf4148de
  ```

- Launched the installed bundle and verified exactly one live accessory application at `/Applications/T-Cube.app/Contents/MacOS/TCube`, PID **53229**.
- All four user JSON files matched their post-quit SHA-256 backups after installation and launch. Fixtures did not replace or alter user data.

Desktop automation was unavailable during the initial acceptance (`Sky Computer Use native pipe startup failed`). A subsequent native desktop connection succeeded and the installed 0.21.1 interface was exercised through the supported computer-use tool: appearance staging/reset, expandable controls, immediate power-saving changes followed by restoration, clipboard selection and arrow-key navigation, search/no-results behavior, focused/unfocused selection readability, image-category empty state, and Escape dismissal. See the [connection investigation and follow-up acceptance](2026-11-05-desktop-connection-investigation.md) for evidence and remaining limits.

This distinguishes the automated native tests and visual fixtures from the follow-up real-window interaction checks. Accessibility roles and labels were inspected, but an audible VoiceOver walk-through was not performed. No quantified CPU or memory improvement is claimed; source review confirms no added recurring rendering/polling work.
