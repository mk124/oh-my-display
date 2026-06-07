#import "OMDMonitorPanelBridge/OMDMonitorPanelBridge.h"

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString * const OMDMonitorPanelBridgeErrorDomain = @"OMDMonitorPanelBridge";

static void OMDMonitorPanelSetError(CFErrorRef *error, NSInteger code, NSString *message) {
    if (error == NULL) {
        return;
    }

    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: message ?: @"Unknown MonitorPanel bridge failure"};
    NSError *nsError = [NSError errorWithDomain:OMDMonitorPanelBridgeErrorDomain code:code userInfo:userInfo];
    *error = (CFErrorRef)CFBridgingRetain(nsError);
}

static BOOL OMDMonitorPanelTry(CFErrorRef *error, void (^block)(void)) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        NSString *reason = exception.reason ?: exception.name ?: @"Objective-C exception";
        OMDMonitorPanelSetError(error, OMDMonitorPanelBridgeErrorException, reason);
        return NO;
    }
}

static SEL OMDMonitorPanelSel(NSString *name) {
    return NSSelectorFromString(name);
}

static BOOL OMDMonitorPanelResponds(id object, NSString *selectorName) {
    return object != nil && [object respondsToSelector:OMDMonitorPanelSel(selectorName)];
}

// MonitorPanel is a private framework that is not linked at build time; load it once on first use.
// The @try keeps a framework-initialization exception from escaping dispatch_once (undefined behavior);
// on failure mgrClass stays Nil and the bridge reports unavailable.
static Class OMDMonitorPanelDisplayMgrClass(void) {
    static Class mgrClass = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/MonitorPanel.framework"] load];
            mgrClass = NSClassFromString(@"MPDisplayMgr");
        } @catch (NSException *exception) {
            mgrClass = Nil;
        }
    });
    return mgrClass;
}

// A fresh MPDisplayMgr per call: its displays list changes with hotplug.
static id OMDMonitorPanelDisplayForID(CGDirectDisplayID displayID) {
    Class mgrClass = OMDMonitorPanelDisplayMgrClass();
    if (mgrClass == Nil) {
        return nil;
    }

    id mgr = [[mgrClass alloc] init];
    if (!OMDMonitorPanelResponds(mgr, @"displays")) {
        return nil;
    }

    id displays = ((id (*)(id, SEL))objc_msgSend)(mgr, OMDMonitorPanelSel(@"displays"));
    if (![displays isKindOfClass:[NSArray class]]) {
        return nil;
    }

    for (id display in displays) {
        // MPDisplay.displayID returns int (type encoding "i"), not NSInteger — match the ABI shape.
        if (OMDMonitorPanelResponds(display, @"displayID")
            && ((int (*)(id, SEL))objc_msgSend)(display, OMDMonitorPanelSel(@"displayID")) == (int)displayID) {
            return display;
        }
    }

    return nil;
}

bool OMDMonitorPanelBridgeIsAvailable(void) {
    Class mgrClass = OMDMonitorPanelDisplayMgrClass();
    Class displayClass = NSClassFromString(@"MPDisplay");
    if (mgrClass == Nil || displayClass == Nil
        || ![mgrClass instancesRespondToSelector:OMDMonitorPanelSel(@"displays")]
        || ![displayClass instancesRespondToSelector:OMDMonitorPanelSel(@"displayID")]
        || ![displayClass instancesRespondToSelector:OMDMonitorPanelSel(@"preferHDRModes")]
        || ![displayClass instancesRespondToSelector:OMDMonitorPanelSel(@"setPreferHDRModes:")]) {
        return false;
    }

    __block BOOL instantiates = NO;
    OMDMonitorPanelTry(NULL, ^{ instantiates = [[mgrClass alloc] init] != nil; });
    return instantiates;
}

bool OMDMonitorPanelCopyPreferHDRModes(CGDirectDisplayID displayID, bool *preferHDRModes, CFErrorRef _Nullable *error) {
    __block BOOL didRead = NO;
    BOOL ok = OMDMonitorPanelTry(error, ^{
        id display = OMDMonitorPanelDisplayForID(displayID);
        if (display == nil) {
            OMDMonitorPanelSetError(error, OMDMonitorPanelBridgeErrorDisplayNotFound, @"MPDisplay not found for CGDirectDisplayID");
            return;
        }
        if (!OMDMonitorPanelResponds(display, @"preferHDRModes")) {
            OMDMonitorPanelSetError(error, OMDMonitorPanelBridgeErrorSelectorUnavailable, @"MPDisplay preferHDRModes selector unavailable");
            return;
        }
        *preferHDRModes = ((BOOL (*)(id, SEL))objc_msgSend)(display, OMDMonitorPanelSel(@"preferHDRModes"));
        didRead = YES;
    });

    return ok && didRead;
}

bool OMDMonitorPanelSetPreferHDRModes(CGDirectDisplayID displayID, bool enabled, CFErrorRef _Nullable *error) {
    __block BOOL didSet = NO;
    BOOL ok = OMDMonitorPanelTry(error, ^{
        id display = OMDMonitorPanelDisplayForID(displayID);
        if (display == nil) {
            OMDMonitorPanelSetError(error, OMDMonitorPanelBridgeErrorDisplayNotFound, @"MPDisplay not found for CGDirectDisplayID");
            return;
        }
        if (!OMDMonitorPanelResponds(display, @"setPreferHDRModes:")) {
            OMDMonitorPanelSetError(error, OMDMonitorPanelBridgeErrorSelectorUnavailable, @"MPDisplay setPreferHDRModes: selector unavailable");
            return;
        }
        ((void (*)(id, SEL, BOOL))objc_msgSend)(display, OMDMonitorPanelSel(@"setPreferHDRModes:"), enabled);
        didSet = YES;
    });

    return ok && didSet;
}
