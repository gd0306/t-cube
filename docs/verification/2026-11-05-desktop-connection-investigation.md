# Desktop connection investigation and native UI follow-up

Recorded: 2026-11-05, Asia/Shanghai. Application under test: installed T-Cube **0.21.1, build 40**, source commit `7ac1dde`.

## Finding

The earlier `Sky Computer Use native pipe startup failed` error originated in the **Codex Computer Use transport**, before a UI request reached T-Cube. The native connection subsequently worked without changing T-Cube source, reinstalling the app, resetting macOS privacy permissions, or replacing the native helper.

This is a recovered connection, not a claim that a permanently reproducible underlying defect was fixed in T-Cube.

### Evidence and error boundary

- The installed computer-use client's `targets/mac/native-pipe.js` emits this exact message after requesting that the native service be available and then failing to connect/ping its native pipe within a five-second connection window. The underlying exception is attached as a cause, but that cause was not included in the earlier tool response. Connection errors, handshake problems and protocol incompatibility cannot be distinguished from the displayed wrapper alone.
- The previous failed calls took approximately five seconds and returned no native app inventory. They failed before reading the app's controls, not during a T-Cube action.
- The local Codex desktop startup log records `bundled_plugin_status_unknown`, `No such file or directory (os error 2)`, and `reason=status_check_failed` for `unified-computer-use` and `computer-use` at `2026-11-04T10:19:34–35Z`. Automatic `plugin_install_succeeded` entries follow both warnings. These establish startup/plugin reconciliation issues, but their timestamps alone do **not** prove the cause of the later pipe failures.
- The installed unified plugin is `26.1029.61003`; the native helper is `26.1027.1001730`, bundle identifier `com.openai.sky.CUAService`. Its configured application path exists. The managed helper process was running, and no matching local native-helper crash report was found.
- During the follow-up, `cua.getState()` returned native applications successfully and `cua.getApp('/Applications/T-Cube.app')` returned the real app controls. Screenshots, clicks, text-field updates, scrolling and keyboard navigation all worked.

The confirmed fault boundary is therefore the computer-use client/native-service connection or handshake. The exact original low-level trigger remains unproven because its nested error was not retained. No evidence supports changing T-Cube rendering, brightness control, application settings, or privacy permissions as a remedy for that transport wrapper.

### Separate observations

- Browser inventory still reported `The browser access host is unavailable`. Native app controls worked in the same run, so the browser report does not mean the entire desktop connection is unavailable.
- One coordinate click returned `windowNotFoundAtPosition` after the content panel lost active-window state. Refreshing the accessibility tree and using the current element index succeeded. This is distinct from the previous native-pipe startup failure.
- Accessing `SystemUIServer` through the tool timed out. The follow-up did not claim to have clicked the third-party status-bar brightness section through that route. The existing owned-native menu/action/brightness tests remain the verification evidence for that section.

## Real installed-window acceptance

The following checks were performed in the installed application through computer use, rather than by calling a model directly:

| Check | Observed result |
|---|---|
| Installed version | Startup/update page displayed 0.21.1 |
| Appearance edit | Selecting another material changed the page status to unapplied and enabled Apply/Reset |
| Appearance reset | Reset restored glass and returned both buttons to disabled/saved state; Apply was not used |
| Custom light/color disclosure | Expanded to expose style, color wells and glow; cycle-managed controls were correctly disabled |
| Theme cycling | Expanded to expose the toggle, all nine theme choices, current theme and 10/20-second interval |
| Interaction disclosure | Hover, delay, idle rotation and face-opening controls remained reachable after scrolling |
| Immediate desktop settings | The page explicitly indicated immediate saving; power saving was switched off and then restored to on |
| Clipboard selection | Selecting a row enabled the relevant output actions and displayed its preview |
| Keyboard selection | Down arrow moved selection and updated the preview |
| Focused/unfocused selection | The real dark-mode window showed readable native blue selection, then readable gray selection when focus moved to search |
| Search | A temporary unmatched query produced the no-results state and disabled output actions; the query was cleared afterward |
| Recording details | The disclosure exposed session-only storage, capacity, privacy limitations and output bounds |
| Image category | Showed the empty state and the recent-ten-images capacity text without inventing fixture data in the real history |
| Escape | Closed the content panel and returned to settings |

Search and category were restored, the original startup/update settings page was restored, and the settings window was closed after verification. Clipboard recording was left in its existing state. No user history was cleared, copied, saved as a snippet, or replaced by fixtures.

## Permission and coverage limits

The installed T-Cube content panel reported that **direct pasting requires T-Cube's own Accessibility permission**. That permission is separate from the computer-use helper's ability to inspect/control an app. No new permission was granted and direct pasting into another app was not tested in this follow-up. Copy/paste callbacks and error/fallback behavior remain covered by the existing automated tests; selecting a row and seeing an enabled button is not evidence of a successful cross-app paste.

Accessibility names, roles, selected states and control availability were inspected. An audible VoiceOver traversal, a live system-appearance switch, and a physical brightness adjustment were not performed. Light-mode and image-selection coverage remains in the earlier native fixture exports. These limits are retained explicitly rather than counted as manual passes.

## Installation, data and source verification

- Built and installed executable SHA-256 still match:

  ```text
  cd74ab872a34b5ba719769273f796a2dd763bcf8185d95b0ff737024cf4148de
  ```

- Installed signature verification and the installed-process path check succeeded.
- The source was not changed during this investigation. The earlier serial test run remains **296 passed, 10 conditionally skipped** for this implementation.
- A comparison against the installation acceptance backup found three of four user JSON files identical. `configuration.json` had already been updated at **2026-11-04 21:42:30 local time**, before these desktop checks, with launcher/group changes. That newer configuration was preserved; the old installation backup was not restored over it. The appearance draft test was reset without applying it.
- Raw desktop logs, native service configuration and user clipboard screenshots were not copied into the repository. Only this sanitized investigation record is published.

## If the connection fails again

Capture the exact transport error and time, retry the native app inventory, and distinguish it from browser-only failures or an individual target-window error. Follow [official Computer Use setup guidance](https://learn.chatgpt.com/docs/computer-use) for plugin availability, app access and macOS Screen Recording/Accessibility permissions. A permission prompt needs review; resetting privacy databases, weakening access controls or changing T-Cube source is not a justified first response to a pipe-connect wrapper.

If it reproduces after reconnecting the computer-use session, retain the nested transport cause and a sanitized desktop diagnostic for the computer-use runtime maintainers. The existing public message alone is insufficient for a more specific causal claim.
