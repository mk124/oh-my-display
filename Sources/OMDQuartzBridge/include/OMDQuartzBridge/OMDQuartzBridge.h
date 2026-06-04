#ifndef OMDQuartzBridge_h
#define OMDQuartzBridge_h

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

CF_ASSUME_NONNULL_BEGIN

typedef CF_ENUM(CFIndex, OMDQuartzBridgeErrorCode) {
    OMDQuartzBridgeErrorException = 100,
    OMDQuartzBridgeErrorDisplayNotFound = 101,
    OMDQuartzBridgeErrorSelectorUnavailable = 102,
    OMDQuartzBridgeErrorCurrentModeUnavailable = 103,
    OMDQuartzBridgeErrorModeIndexUnavailable = 105
};

bool OMDQuartzBridgeIsAvailable(void);
CFArrayRef _Nullable OMDQuartzCopyDisplayModeDictionaries(CGDirectDisplayID displayID, CFErrorRef _Nullable * _Nullable error);
CFDictionaryRef _Nullable OMDQuartzCopyCurrentDisplayModeDictionary(CGDirectDisplayID displayID, CFErrorRef _Nullable * _Nullable error);
bool OMDQuartzSetCurrentDisplayModeAtIndex(CGDirectDisplayID displayID, CFIndex modeIndex, bool * _Nullable attemptedMutation, CFErrorRef _Nullable * _Nullable error);

CF_ASSUME_NONNULL_END

#endif
