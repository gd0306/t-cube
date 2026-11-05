# Task 1: macOS display input switching

Implemented a native, two-position status-menu control with UUID-scoped mappings, the exact-name/vendor/product 27C1U-D default (7/5), explicit calibration and preset, on-demand reads, and no timers or automatic writes. Unknown or ambiguous displays cannot be switched without a valid mapping and readable current source. Calibration saves atomically to a separate bounded, versioned store; corrupt files are left intact and block saves and switching. Input DDC uses a separately whitelisted 0x60 bridge API, the existing two-transmission exchange, and the same serial hardware queue as brightness. A successful transport followed by invalid or missing readback reports sent-unconfirmed; no retry or reversion is attempted. Queued operations cancel on close/topology change and stale completions are discarded.

Verification:
- Focused tests passed: .build/input-focused.log and .build/input-regression-rerun.log (codec/null frame, noncontinuous values, persistence/corrupt data, bridge whitelist, duplicate commits, unconfirmed outcome, close and topology/clone handling). Both full-suite failures reproduced below passed individually in the latter log.
- Native light/dark previews: .build/display-input-previews/input-menu-light.png and input-menu-dark.png, generated with TCUBE_INPUT_PREVIEWS=1; these use fixture data and do not access display hardware. The preview panel is inactive, so its controls appear dimmed.
- Clean serial full suite passed: `swift test --scratch-path .build/tests --no-parallel` (.build/input-serial-suite.log): 174 native and 133 core Swift tests, plus 7 XCTest cases. The subsequent accessibility help and preview-only changes passed the focused native menu tests (.build/input-preview-final.log). `swift build --scratch-path .build/app` passed (.build/input-build-final.log).
- Earlier default-parallel full suite failed twice: .build/input-full-tests.log and .build/input-full-tests-rerun.log. The first included frozen-frame rendering and brightness timing failures; the second included ThemePresentationLifecycleTests.failedSnapshotsKeepAVisibleUsableLiveSurface and DisplayBrightnessControllerTests.openingReadsHardwareAndClosingDoesNotPollOrWrite. Both latter cases passed in isolation. Baseline full suite had passed before implementation.
- Full suite excluding all new input tests also failed: .build/input-existing-suite.log (RenderingLifecycleTests.appearanceRefreshKeepsPreviousFrameUntilNewStaticFrameIsReady and the same brightness opening case). A short incremental build was inadvertently started and interrupted near the start of this comparison; it is therefore not a clean idle-machine control. These observations do not establish a root cause; serial execution passed.
- No physical input switching, local installation, or user data modification was performed.

Limitations for integration review: GUI interaction with the actual status menu and calibration alert, hardware read/write acceptance, and installed-app acceptance remain to be verified by the parent. The default-parallel failures remain unexplained, although the clean serial suite passed.

## Review fixes, round 1

A valid readback equal to the preflight value alone means not applied. A third input is now shown by its actual code and disables switching until mapped; corrupt-store guidance remains visible after a read failure. The normal ready-row subtitle shows Type-C or HDMI. Input VCP 0x60 now waits 50 ms before each transmission, matching the validated double-send probe; brightness 0x10 retains its 10 ms delay.

The production input hardware now accepts an injected exchange, queue, and pause for deterministic tests while defaulting to the shared brightness queue and native bridge. Tests cover mapped/unmapped preflight, same-source suppression, confirmed/unchanged/third-source/unreadable readback, cancellation while queued and between preflight and Set, shared-queue blocking, and controller stale state. The C bridge's real two-transmission loop is shared with a no-hardware harness exercising first-send acceptance followed by second-send failure/disconnect and first-send failures. No physical switching was performed.

- Focused hardware, controller, and menu tests: `.build/input-review-focused.log`, 12 passed.
- `swift test --scratch-path .build/tests --no-parallel`: `.build/input-review-serial.log`, 181 native Swift tests and 133 core Swift tests passed, plus 7 XCTest cases (conditional tests skipped as configured).
- `swift build --scratch-path .build/app`: `.build/input-review-build.log`, passed after the suite.
- `git diff --check`: passed.
