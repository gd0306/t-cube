#ifndef TCUBE_DISPLAY_BRIGHTNESS_BRIDGE_H
#define TCUBE_DISPLAY_BRIGHTNESS_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    TCBrightnessSuccess = 0,
    TCBrightnessUnsupported = 1,
    TCBrightnessInvalidArgument = 2,
    TCBrightnessDisplayUnavailable = 3,
    TCBrightnessOperationFailed = 4
};

// The UUID must identify the currently online display ID. Outputs change only
// after success. Native values are finite and normalized to the range 0...1.
int32_t TCBrightnessReadNative(uint32_t displayID, const char *uuid, float *value);
int32_t TCBrightnessWriteNative(uint32_t displayID, const char *uuid, float value);

// Apple Silicon only. Accepts brightness VCP 0x10 Get (4 request/11 reply
// bytes) or Set (6 request/0 reply bytes). The caller validates reply semantics.
// Calls block briefly and must run on the application's hardware serial queue.
int32_t TCBrightnessDDCExchange(uint32_t displayID, const char *uuid,
    const uint8_t *request, uint32_t requestLength,
    uint8_t *reply, uint32_t replyLength);

int32_t TCInputDDCExchange(uint32_t displayID, const char *uuid,
    const uint8_t *request, uint32_t requestLength, uint8_t *reply, uint32_t replyLength);

// Exercises the shared two-transmission result handling without hardware.
int32_t TCInputTestTransmissionResults(int32_t first, int32_t second);

#ifdef __cplusplus
}
#endif

#endif
