#ifndef OMDMonitorPanelBridge_h
#define OMDMonitorPanelBridge_h

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

CF_ASSUME_NONNULL_BEGIN

typedef CF_ENUM(CFIndex, OMDMonitorPanelBridgeErrorCode) {
    OMDMonitorPanelBridgeErrorException = 200,
    OMDMonitorPanelBridgeErrorDisplayNotFound = 201,
    OMDMonitorPanelBridgeErrorSelectorUnavailable = 202
};

bool OMDMonitorPanelBridgeIsAvailable(void);
bool OMDMonitorPanelCopyPreferHDRModes(CGDirectDisplayID displayID, bool *preferHDRModes, CFErrorRef _Nullable * _Nullable error);
bool OMDMonitorPanelSetPreferHDRModes(CGDirectDisplayID displayID, bool enabled, CFErrorRef _Nullable * _Nullable error);

CF_ASSUME_NONNULL_END

#endif
