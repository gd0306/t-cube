# Display input switching implementation plan

> **For agentic workers:** use subagent-driven-development; execute each independently tested task and obtain task and whole-branch reviews.

**Goal:** Switch this maintainer's 27C1U-D between Type-C and HDMI on macOS and Windows from the status/tray UI.
**Architecture:** Profile-scoped VCP0x60 adapters, asynchronous controllers and existing native/theme UI. Separate safe display-inputs.json mappings; no launcher schema or dependency changes.
**Tech Stack:** Swift6, AppKit, C IOAV bridge; Electron45, TypeScript7, Koffi/Dxva2 worker.
**Spec:** docs/superpowers/specs/2026-11-05-display-input-design.md

## Global Constraints

macOS15+, Windows10/11, existing two-transmission Mac transport, generic user-calibrated monitor mapping with known27C1U-D USB-C7/HDMI5 default. Exact identities per operation, no idle polling, no write retries, no arbitrary VCP IPC, no launcher JSON schema change. Left Type-C, right HDMI, commit on release; honest sent-unconfirmed after switching. All spec conditions apply.

### Task 1: Native macOS input control

Files: create Sources/CubeCore/DisplayInput.swift, Sources/TCube/DisplayInputHardware.swift, DisplayInputController.swift, DisplayInputMenu.swift; modify DisplayBrightnessBridge C/header, shared hardware serialization and TCubeApp lifecycle; focused CubeCore/TCube tests.

- [ ] Write tests before implementation. `#expect(DDCInputCodec.parseReply([0x6E,0x80,0xBE,0,0x60,0,0,14,0,7,0xDD]) == nil)` must reject observed stale null reply. Add expected request bytes for5/7; no current<=maximum rule for noncontinuous inputs. Test controller with injected hardware: `beginTracking`, `setSource(.hdmi, for: uuid)`, duplicate and disabled commits yield one hardware write, close/topology stale completions ignored, accepted-but-unreadable never reported as confirmed. Test bridge whitelist preserving brightness-only API and separate0x60 API.
- [ ] Run focused tests and observe missing-feature failure.
- [ ] Implement scoped codec/profile/outcome, serial off-main hardware using same queue as brightness, dedicated input C entry restricted to0x60, validated two sends. Native control owns no timers, adds on-demand refresh, no unchanged-source write. Match known preset by name+vendor/product, otherwise allow explicit calibration per exact UUID. Add atomic validated display-inputs.json store preserving corrupt files. Native row provides a setup action with Type-C/HDMI decimal code fields and current code guidance, no writes during calibration. Add tests for persistence, invalid/identical codes, unknown mapped source and corrupt-file preservation. Bridge accepted-write/disconnect semantics must avoid reporting a known accepted write as definitely failed.
- [ ] Run focused tests, full Swift suite and build. Commit only Mac files and task report. No local install or physical writes by worker.

### Task 2: Windows input controller and tray panel

Files: create windows/src/native/display-input*.ts, src/main/display-input*.ts, src/shared/display-input.ts, src/preload/display-input.ts, renderer/display-input.{ts,html,css}, focused tests; modify desktop.ts and scripts/build.mjs.

- [ ] Write failing tests for supported profile/identity parsing, commit and outcome behavior, worker cleanup, cancellation/duplicates and panel IPC authorization before payload/native calls. Include observed source5/max14 and7/max14, unsupported GWD0140/current16/max3. Native FFI dependencies are injected where necessary; test real handle lifecycle algorithms, not mock assertions alone.
- [ ] Run focused tests, observe expected failure.
- [ ] Implement Koffi enumeration/Get/SetVCP0x60 in lazy worker. Enumerate full interface keys afresh; finally destroy all handles. Bounded EDID reads may identify the known model; otherwise require explicit calibration per monitor interface, with a selectable27C1U-D preset. Add atomic validated display-inputs.json store preserving corrupt files. Panel has setup action, current-code guidance and Type-C/HDMI decimal fields0...65535, distinct values required. Never write during calibration; test generic mappings and corrupt-file preservation. Reject ambiguous/cloned targets. Fresh active-source preflight before Set. Outcome includes sent-unconfirmed if readback lost, no automatic writes/retries.
- [ ] Add tray menu entry and small accessible theme-aware panel, narrow sandbox preload/IPC exact webContents+mainframe auth, allow leftType-C/rightHDMI range change only oncommit. Add worker/panel entries to build. Lazy window destroyed onclose, service disposed atquit, no new launcher window privileges.
- [ ] Run focused tests, typecheck, all Windows tests and build; commit only Windows changes and report. No physical writes or pushing by worker.

### Task 3: Integration, acceptance and documentation

Files: Resources/Info.plist, windows/package*.json, both root READMEs, windows/README.md, docs/verification/2026-11-05-display-input.md.

- [ ] Review Task1 and Task2 diffs for spec compliance and code quality; fix important findings then scoped re-review. Full branch final review before merge.
- [ ] Verify Mac native row and Windows panel at real dimensions, light/dark, loading/unknown/failure, keyboard and disabled states. Reuse native preview tests or own app harness; no fixtures overwrite user configuration. Run `swift test --scratch-path .build/tests`, `swift build --scratch-path .build/app`; Windows `npm run typecheck`, `npm test`, `npm run build`; `git diff --check`.
- [ ] Bump Mac0.22.0/build42 and Windows0.22.0. Update existing README feature/config sections in both languages and platform guide with exact support and switching-back limit. Record hardware probe versus automated/installed tests distinctly.
- [ ] Build release app and DMG; normal quit, preserve previous app and all user JSON in ignored build/install-backups timestamp directory; install /Applications/T-Cube.app and compare installed/built SHA256. Launch and verify owned native UI. Keep JSON changes only if user/app normal operations make them.
- [ ] Integrate focused commits and preexisting README-style AGENTS update without losing maintainer changes. Push per standing authorization, monitor Windows CI and package workflow; release only tested available artifacts and honest platform acceptance notes.
