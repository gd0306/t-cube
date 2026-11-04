# macOS status-menu display brightness implementation

> Execution: hardware bridge and independent menu state/codec work proceed in parallel; integration and all GUI suites run serially. User authorized brightness control and explicitly deferred audio. No extra permission gate is needed for this scope.

## Requirements / design

Clicking the existing macOS status item exposes a “显示器亮度” section, one native slider and percentage per connected screen. The present machine has Built-in Retina Display (native read ≈0.474) and 27C1U-D (DDC VCP 0x10 read 37, maximum 100). Change actual hardware brightness; no shade/gamma substitute. Unsupported/read-failed screens show a disabled control and readable reason, never invented success. Scope is brightness only, primarily macOS/Apple Silicon. Existing menu items and cube behavior remain.

Read screen descriptors on the main actor, using CGDisplay UUID as identity. Read hardware in a private serial queue only when the status menu opens, on screen-topology changes while open, or after a user write. No background poll or startup brightness restoration. Rate-limit/coalesce drag writes: at most one active operation and one latest desired value per screen, with 100 ms debounce. Flush the latest desired value even if the menu closes. Drop stale refresh/write results after topology or user-edit generation changes. Validate screen identity again before any physical write; never match merely by product name or “first monitor”.

Native brightness uses dynamically resolved DisplayServices APIs, with unsupported status if absent. External Apple Silicon DDC uses dynamically resolved IOAVService I2C and an exact CoreDisplay IODisplayLocation/framebuffer registry match, adapted from MIT m1ddc/AppleSiliconDDC. Preserve attribution in source and bundled notices. These are compatibility-sensitive system interfaces, not an App Store API promise. Gracefully reject missing APIs, unavailable transports, malformed replies, unsupported VCP and zero/invalid maxima. Intel external DDC is outside this first Apple Silicon release; unsupported devices remain visible.

## File boundaries and contracts

1. `Sources/DisplayBrightnessBridge/include/DisplayBrightnessBridge.h`, `BrightnessBridge.c`: low-level native/IOAV access and exact display identity/registry match; no UI, policy or protocol math. API returns zero on success, nonzero on unsupported/failure:

```c
int32_t TCBrightnessReadNative(uint32_t displayID, const char *uuid, float *value);
int32_t TCBrightnessWriteNative(uint32_t displayID, const char *uuid, float value);
int32_t TCBrightnessDDCExchange(uint32_t displayID, const char *uuid,
    const uint8_t *request, uint32_t requestLength,
    uint8_t *reply, uint32_t replyLength);
```

Exchange only accepts a brightness Get VCP request (4 bytes, reply length 11) or Set VCP (6 bytes, no reply), code 0x10. Resolve the external service belonging to exactly the selected framebuffer; close every owned CF/IORegistry object. Two writes with a short bounded delay, then 50 ms read wait (longer bounded wait for MCDP bridge); no unbounded retry. UUID and online status are checked at point of use. Missing symbols never crash launch. Private symbols are dynamically loaded, not hard-linked.

2. `Sources/CubeCore/DisplayBrightness.swift`: Sendable target/reading/status/backend models and strict DDC brightness codec. Requests use checksum seeded 0x6e XOR 0x51. Replies require 11 bytes, header 0x6e/0x88/0x02, success result, code 0x10, type 0, checksum seeded 0x50, positive maximum and current <= maximum. Preserve 16-bit range and reject NaN/infinite/out-of-range input. Tests use literal independent packets:

```swift
#expect(DDCBrightnessCodec.readRequest == [0x82, 0x01, 0x10, 0xAC])
// Valid reply: 6E 88 02 00 10 00 00 64 00 25 E5 (37 / 100)
```

3. `Sources/TCube/DisplayBrightnessHardware.swift`: Sendable async hardware protocol, serial-queue production adapter, native-first reads then external DDC fallback, verification readback. No AppKit or user configuration writes. Inputs contain display ID/UUID/name/built-in flag. Real maximum from readback determines raw write scale.

4. `Sources/TCube/DisplayBrightnessController.swift`: main-actor menu state, refresh generation, topology invalidation, bounded/coalesced write drain and error/rollback display. Injectable async hardware for controlled race/failure tests. A late response must not overwrite a newer slider drag or target the next screen after reconnect.

5. `Sources/TCube/DisplayBrightnessMenu.swift`: native menu custom rows (name/percentage/slider/status), accessibility names, keyboard adjustment and system appearance. Track drag using native slider event handling without closing the menu; disabled states remain legible. Wire only the status menu in `TCubeApp.swift`: menuWillOpen/read, menuDidClose/end, screen change invalidation and termination cleanup.

6. `Package.swift`: add native bridge target only to TCube. `Resources/ThirdPartyNotices.txt` plus `scripts/build-app.sh`: ship MIT notices. No runtime external app/dependency required.

## Verification and completion sequence

- [x] Codec red/green: literal packets, corrupt checksum/header/code/status, zero/max bounds, 16-bit and non-finite inputs.
- [x] Controller red/green: menu-closed no work, open refresh, no overlapping refresh, coalesced rapid input, one in-flight + latest, final write survives menu close, stale read protection, failed write rollback, hotplug/UUID invalidation, unsupported states.
- [x] Menu tests: native sliders preserve per-screen identity, error/disabled rows, keyboard/accessibility, render preview. GUI suites serial.
- [x] Read-only live checks against both physical screens using production bridge. Opt-in small reversible write/read/restore using captured originals and unconditional restoration; do not use fixture user JSON.
- [x] Full serial Swift suite, release app build, DMG build/mount/signature checks, whitespace checks and independent code review.
- [x] Normal quit, previous app + recursive JSON backups before/after quit, install new macOS version and verify installed hash/build/startup. Distinguish user/manual desktop acceptance from automated results.
- [x] Commit/push/release under standing session authorization after checks; keep release versions aligned because both clients query the same GitHub latest tag. Package Windows 0.21.0 with its existing functionality; explicitly state brightness control is macOS-only. This avoids an endless newer-version reminder against an older Windows download.
