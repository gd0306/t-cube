/*
 * IORegistry transport discovery and IOAV I2C communication adapted from:
 * m1ddc, Copyright (c) 2021 waydabber, https://github.com/waydabber/m1ddc
 * AppleSiliconDDC, Copyright (c) 2021 Istvan T.,
 * https://github.com/waydabber/AppleSiliconDDC
 * Both are MIT licensed; see the bundled ThirdPartyNotices.txt for the license.
 * Adaptations use exact framebuffer identity, bounded operations, and dynamic
 * private API loading. No fuzzy display matching or default service is used.
 */

#include "DisplayBrightnessBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>

typedef CFUUIDRef (*CreateDisplayUUID)(uint32_t);
typedef int32_t (*GetNativeBrightness)(uint32_t, float *);
typedef int32_t (*SetNativeBrightness)(uint32_t, float);
#if defined(__arm64__)
typedef CFDictionaryRef (*CreateDisplayInfo)(uint32_t);
typedef CFTypeRef (*CreateAVService)(CFAllocatorRef, io_service_t);
typedef IOReturn (*AVReadI2C)(CFTypeRef, uint32_t, uint32_t, void *, uint32_t);
typedef IOReturn (*AVWriteI2C)(CFTypeRef, uint32_t, uint32_t, void *, uint32_t);
#endif

static struct {
    CreateDisplayUUID createUUID;
    GetNativeBrightness getBrightness;
    SetNativeBrightness setBrightness;
#if defined(__arm64__)
    CreateDisplayInfo createDisplayInfo;
    CreateAVService createAVService;
    AVReadI2C readI2C;
    AVWriteI2C writeI2C;
#endif
} api;
static pthread_once_t apiOnce = PTHREAD_ONCE_INIT;

static void loadAPIs(void) {
    // Keep successfully opened images resident for the lifetime of the function
    // pointers. dlopen failure leaves a null symbol and is safely unsupported.
    void *colorSync = dlopen(
        "/System/Library/Frameworks/ColorSync.framework/ColorSync", RTLD_LAZY | RTLD_LOCAL);
    if (colorSync != NULL) {
        api.createUUID = (CreateDisplayUUID)dlsym(colorSync, "CGDisplayCreateUUIDFromDisplayID");
    }
    void *displayServices = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY | RTLD_LOCAL);
    if (displayServices != NULL) {
        api.getBrightness = (GetNativeBrightness)dlsym(displayServices, "DisplayServicesGetBrightness");
        api.setBrightness = (SetNativeBrightness)dlsym(displayServices, "DisplayServicesSetBrightness");
    }
#if defined(__arm64__)
    void *coreDisplay = dlopen(
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY | RTLD_LOCAL);
    if (coreDisplay != NULL) {
        api.createDisplayInfo = (CreateDisplayInfo)dlsym(coreDisplay, "CoreDisplay_DisplayCreateInfoDictionary");
    }
    void *ioKit = dlopen(
        "/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (ioKit != NULL) {
        api.createAVService = (CreateAVService)dlsym(ioKit, "IOAVServiceCreateWithService");
        api.readI2C = (AVReadI2C)dlsym(ioKit, "IOAVServiceReadI2C");
        api.writeI2C = (AVWriteI2C)dlsym(ioKit, "IOAVServiceWriteI2C");
    }
#endif
}

static bool displayMatches(uint32_t displayID, const char *uuid) {
    if (displayID == kCGNullDirectDisplay || uuid == NULL || uuid[0] == '\0' ||
        api.createUUID == NULL || !CGDisplayIsOnline(displayID)) {
        return false;
    }
    CFStringRef text = CFStringCreateWithCString(kCFAllocatorDefault, uuid, kCFStringEncodingUTF8);
    if (text == NULL) {
        return false;
    }
    CFUUIDRef expected = CFUUIDCreateFromString(kCFAllocatorDefault, text);
    CFRelease(text);
    if (expected == NULL) {
        return false;
    }
    CFUUIDRef current = api.createUUID(displayID);
    bool matches = current != NULL && CFEqual(expected, current) && CGDisplayIsOnline(displayID);
    if (current != NULL) {
        CFRelease(current);
    }
    CFRelease(expected);
    return matches;
}

static int32_t nativeStatus(int32_t result) {
    if (result == 0) {
        return TCBrightnessSuccess;
    }
    // DisplayServices returns 1000 for displays without native brightness.
    if (result == 1000 || result == (int32_t)kIOReturnUnsupported) {
        return TCBrightnessUnsupported;
    }
    return TCBrightnessOperationFailed;
}

int32_t TCBrightnessReadNative(uint32_t displayID, const char *uuid, float *value) {
    if (value == NULL || uuid == NULL) {
        return TCBrightnessInvalidArgument;
    }
    pthread_once(&apiOnce, loadAPIs);
    if (api.createUUID == NULL || api.getBrightness == NULL) {
        return TCBrightnessUnsupported;
    }
    if (!displayMatches(displayID, uuid)) {
        return TCBrightnessDisplayUnavailable;
    }
    float reading = 0;
    int32_t status = nativeStatus(api.getBrightness(displayID, &reading));
    if (status != TCBrightnessSuccess) {
        return status;
    }
    if (!isfinite(reading) || reading < 0 || reading > 1) {
        return TCBrightnessOperationFailed;
    }
    if (!displayMatches(displayID, uuid)) {
        return TCBrightnessDisplayUnavailable;
    }
    *value = reading;
    return TCBrightnessSuccess;
}

int32_t TCBrightnessWriteNative(uint32_t displayID, const char *uuid, float value) {
    if (uuid == NULL || !isfinite(value) || value < 0 || value > 1) {
        return TCBrightnessInvalidArgument;
    }
    pthread_once(&apiOnce, loadAPIs);
    if (api.createUUID == NULL || api.setBrightness == NULL) {
        return TCBrightnessUnsupported;
    }
    if (!displayMatches(displayID, uuid)) {
        return TCBrightnessDisplayUnavailable;
    }
    return nativeStatus(api.setBrightness(displayID, value));
}

static bool isFeatureRequest(const uint8_t *request, uint32_t requestLength,
    const uint8_t *reply, uint32_t replyLength, uint8_t feature) {
    if (request == NULL) {
        return false;
    }
    bool get = requestLength == 4 && replyLength == 11 && reply != NULL &&
        request[0] == 0x82 && request[1] == 0x01;
    bool set = requestLength == 6 && replyLength == 0 &&
        request[0] == 0x84 && request[1] == 0x03;
    if ((!get && !set) || request[2] != feature) {
        return false;
    }
    uint8_t checksum = 0x6e ^ 0x51;
    for (uint32_t index = 0; index < requestLength; ++index) {
        checksum ^= request[index];
    }
    return checksum == 0;
}

typedef int32_t (*Transmission)(void *context, unsigned cycle);
static int32_t sendTwice(Transmission send, void *context, bool acceptedInputSet) {
    for (unsigned cycle = 0; cycle < 2; ++cycle) {
        int32_t status = send(context, cycle);
        if (status != TCBrightnessSuccess) {
            return acceptedInputSet && cycle > 0 ? TCBrightnessSuccess : status;
        }
    }
    return TCBrightnessSuccess;
}
typedef struct { int32_t results[2]; } TestTransmission;
static int32_t testTransmission(void *context, unsigned cycle) {
    return ((TestTransmission *)context)->results[cycle];
}
int32_t TCInputTestTransmissionResults(int32_t first, int32_t second) {
    TestTransmission test = {{first, second}};
    return sendTwice(testTransmission, &test, true);
}

#if defined(__arm64__)
typedef struct {
    CFTypeRef service;
    uint32_t chipAddress;
} DDCTransport;

static bool propertyEquals(io_registry_entry_t entry, CFStringRef key, CFStringRef expected) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(entry, key, kCFAllocatorDefault, 0);
    bool matches = value != NULL && CFGetTypeID(value) == CFStringGetTypeID() && CFEqual(value, expected);
    if (value != NULL) {
        CFRelease(value);
    }
    return matches;
}

static bool isMCDP29XX(io_service_t proxy) {
    io_registry_entry_t parent = IO_OBJECT_NULL;
    if (IORegistryEntryGetParentEntry(proxy, kIOServicePlane, &parent) != KERN_SUCCESS) {
        return false;
    }
    bool matches = propertyEquals(parent, CFSTR("EPICProviderClass"), CFSTR("AppleDCPMCDP29XX"));
    IOObjectRelease(parent);
    return matches;
}

static DDCTransport copyTransport(uint32_t displayID) {
    DDCTransport transport = {NULL, 0x37};
    CFDictionaryRef info = api.createDisplayInfo(displayID);
    if (info == NULL) {
        return transport;
    }
    CFTypeRef location = CFDictionaryGetValue(info, CFSTR("IODisplayLocation"));
    io_registry_entry_t selected = IO_OBJECT_NULL;
    if (location != NULL && CFGetTypeID(location) == CFStringGetTypeID()) {
        selected = IORegistryEntryCopyFromPath(kIOMainPortDefault, (CFStringRef)location);
    }
    CFRelease(info);
    if (selected == IO_OBJECT_NULL) {
        return transport;
    }
    uint64_t selectedID = 0;
    bool validFramebuffer = IOObjectConformsTo(selected, "IOMobileFramebuffer") &&
        IORegistryEntryGetRegistryEntryID(selected, &selectedID) == KERN_SUCCESS;
    IOObjectRelease(selected);
    if (!validFramebuffer) {
        return transport;
    }
    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    if (root == IO_OBJECT_NULL) {
        return transport;
    }
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t result = IORegistryEntryCreateIterator(
        root, kIOServicePlane, kIORegistryIterateRecursively, &iterator);
    IOObjectRelease(root);
    if (result != KERN_SUCCESS) {
        if (iterator != IO_OBJECT_NULL) {
            IOObjectRelease(iterator);
        }
        return transport;
    }
    // On Apple Silicon the proxy is in a separate DCP subtree rather than a
    // child of the framebuffer. As in m1ddc/AppleSiliconDDC, its association is
    // the preceding framebuffer in the recursive IOService traversal. Restrict
    // the whole segment to the exact registry ID, and reject ambiguous proxies.
    bool inSelectedFramebuffer = false;
    io_service_t candidate = IO_OBJECT_NULL;
    unsigned candidateCount = 0;
    io_registry_entry_t entry;
    while ((entry = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        if (IOObjectConformsTo(entry, "IOMobileFramebuffer")) {
            uint64_t registryID = 0;
            inSelectedFramebuffer =
                IORegistryEntryGetRegistryEntryID(entry, &registryID) == KERN_SUCCESS &&
                registryID == selectedID;
        } else if (inSelectedFramebuffer && IOObjectConformsTo(entry, "DCPAVServiceProxy") &&
            propertyEquals(entry, CFSTR("Location"), CFSTR("External"))) {
            candidateCount++;
            if (candidate == IO_OBJECT_NULL) {
                candidate = entry;
                IOObjectRetain(candidate);
            }
        }
        IOObjectRelease(entry);
    }
    bool validIteration = IOIteratorIsValid(iterator);
    IOObjectRelease(iterator);
    if (candidate != IO_OBJECT_NULL) {
        if (candidateCount == 1 && validIteration) {
            transport.service = api.createAVService(kCFAllocatorDefault, candidate);
            transport.chipAddress = isMCDP29XX(candidate) ? 0xb7 : 0x37;
        }
        IOObjectRelease(candidate);
    }
    return transport;
}
#endif

#if defined(__arm64__)
typedef struct {
    DDCTransport transport;
    uint32_t displayID;
    const char *uuid;
    uint8_t *packet;
    uint32_t length;
    uint8_t feature;
} TransmissionContext;
static int32_t sendTransmission(void *value, unsigned cycle) {
    (void)cycle;
    TransmissionContext *context = value;
    usleep(context->feature == 0x60 ? 50000 : 10000);
    if (!displayMatches(context->displayID, context->uuid)) return TCBrightnessDisplayUnavailable;
    return api.writeI2C(context->transport.service, context->transport.chipAddress, 0x51, context->packet, context->length) == kIOReturnSuccess
        ? TCBrightnessSuccess : TCBrightnessOperationFailed;
}
#endif

static int32_t exchange(uint32_t displayID, const char *uuid,
    const uint8_t *request, uint32_t requestLength,
    uint8_t *reply, uint32_t replyLength, uint8_t feature) {
    if (uuid == NULL || !isFeatureRequest(request, requestLength, reply, replyLength, feature)) {
        return TCBrightnessInvalidArgument;
    }
    pthread_once(&apiOnce, loadAPIs);
    if (api.createUUID == NULL) {
        return TCBrightnessUnsupported;
    }
    if (!displayMatches(displayID, uuid)) {
        return TCBrightnessDisplayUnavailable;
    }
#if defined(__arm64__)
    if (CGDisplayIsBuiltin(displayID) || api.createDisplayInfo == NULL ||
        api.createAVService == NULL || api.writeI2C == NULL ||
        (replyLength != 0 && api.readI2C == NULL)) {
        return TCBrightnessUnsupported;
    }
    DDCTransport transport = copyTransport(displayID);
    if (transport.service == NULL) {
        return TCBrightnessUnsupported;
    }
    uint8_t packet[6];
    memcpy(packet, request, requestLength);
    TransmissionContext context = {transport, displayID, uuid, packet, requestLength, feature};
    int32_t status = sendTwice(sendTransmission, &context, feature == 0x60 && replyLength == 0);
    if (status == TCBrightnessSuccess && replyLength != 0) {
        usleep(transport.chipAddress == 0xb7 ? 100000 : 50000);
        if (!displayMatches(displayID, uuid)) {
            status = TCBrightnessDisplayUnavailable;
        } else {
            uint8_t response[11] = {0};
            if (api.readI2C(transport.service, transport.chipAddress, 0x51, response, sizeof(response)) != kIOReturnSuccess) {
                status = TCBrightnessOperationFailed;
            } else if (!displayMatches(displayID, uuid)) {
                status = TCBrightnessDisplayUnavailable;
            } else {
                memcpy(reply, response, sizeof(response));
            }
        }
    }
    CFRelease(transport.service);
    return status;
#else
    return TCBrightnessUnsupported;
#endif
}

int32_t TCBrightnessDDCExchange(uint32_t id, const char *uuid, const uint8_t *request, uint32_t length, uint8_t *reply, uint32_t replyLength) {
    return exchange(id, uuid, request, length, reply, replyLength, 0x10);
}
int32_t TCInputDDCExchange(uint32_t id, const char *uuid, const uint8_t *request, uint32_t length, uint8_t *reply, uint32_t replyLength) {
    return exchange(id, uuid, request, length, reply, replyLength, 0x60);
}
