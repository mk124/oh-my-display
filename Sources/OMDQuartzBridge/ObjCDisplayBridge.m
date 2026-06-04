#import "OMDQuartzBridge/OMDQuartzBridge.h"

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString * const OMDQuartzBridgeErrorDomain = @"OMDQuartzBridge";

static void OMDQuartzSetError(CFErrorRef *error, NSInteger code, NSString *message) {
    if (error == NULL) {
        return;
    }

    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: message ?: @"Unknown Quartz bridge failure"};
    NSError *nsError = [NSError errorWithDomain:OMDQuartzBridgeErrorDomain code:code userInfo:userInfo];
    *error = (CFErrorRef)CFBridgingRetain(nsError);
}

static BOOL OMDQuartzTry(CFErrorRef *error, void (^block)(void)) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        NSString *reason = exception.reason ?: exception.name ?: @"Objective-C exception";
        OMDQuartzSetError(error, OMDQuartzBridgeErrorException, reason);
        return NO;
    }
}

static Class OMDQuartzCADisplayClass(void) {
    return NSClassFromString(@"CADisplay");
}

static SEL OMDQuartzSel(NSString *name) {
    return NSSelectorFromString(name);
}

static BOOL OMDQuartzResponds(id object, NSString *selectorName) {
    return object != nil && [object respondsToSelector:OMDQuartzSel(selectorName)];
}

static id OMDQuartzSendObject(id object, NSString *selectorName) {
    return ((id (*)(id, SEL))objc_msgSend)(object, OMDQuartzSel(selectorName));
}

static NSInteger OMDQuartzSendInteger(id object, NSString *selectorName) {
    return ((NSInteger (*)(id, SEL))objc_msgSend)(object, OMDQuartzSel(selectorName));
}

static uint32_t OMDQuartzSendUInt32(id object, NSString *selectorName) {
    return ((uint32_t (*)(id, SEL))objc_msgSend)(object, OMDQuartzSel(selectorName));
}

static double OMDQuartzSendDouble(id object, NSString *selectorName) {
    return ((double (*)(id, SEL))objc_msgSend)(object, OMDQuartzSel(selectorName));
}

static BOOL OMDQuartzSendBool(id object, NSString *selectorName) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, OMDQuartzSel(selectorName));
}

static void OMDQuartzSendVoidObject(id object, NSString *selectorName, id argument) {
    ((void (*)(id, SEL, id))objc_msgSend)(object, OMDQuartzSel(selectorName), argument);
}

static NSArray *OMDQuartzDisplays(void) {
    Class displayClass = OMDQuartzCADisplayClass();
    if (displayClass == Nil || ![displayClass respondsToSelector:OMDQuartzSel(@"displays")]) {
        return nil;
    }

    id displays = ((id (*)(id, SEL))objc_msgSend)(displayClass, OMDQuartzSel(@"displays"));
    return [displays isKindOfClass:[NSArray class]] ? displays : nil;
}

static id OMDQuartzDisplayForID(CGDirectDisplayID displayID) {
    for (id display in OMDQuartzDisplays() ?: @[]) {
        if (OMDQuartzResponds(display, @"displayId") && OMDQuartzSendUInt32(display, @"displayId") == displayID) {
            return display;
        }
    }

    return nil;
}

static NSString *OMDQuartzEncodingString(NSNumber *ycbcr) {
    if (ycbcr == nil) {
        return @"unknown";
    }
    return ycbcr.boolValue ? @"ycbcr" : @"rgb";
}

static NSString *OMDQuartzSanitizedKey(id value, NSString *fallback) {
    NSString *text = [[value description] lowercaseString] ?: fallback;
    if (text.length == 0) {
        text = fallback;
    }

    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"].invertedSet;
    NSArray *parts = [text componentsSeparatedByCharactersInSet:allowed];
    NSString *joined = [parts componentsJoinedByString:@""];
    return joined.length > 0 ? joined : fallback;
}

static NSString *OMDQuartzHDRString(id hdrMode) {
    NSString *key = OMDQuartzSanitizedKey(hdrMode, @"unknown");
    if ([key isEqualToString:@"0"] || [key containsString:@"sdr"]) {
        return @"sdr";
    }
    if ([key isEqualToString:@"unknown"]) {
        return @"unknown";
    }
    if ([key containsString:@"hdr"]) {
        return key;
    }
    return [@"hdr" stringByAppendingString:key];
}

static NSString *OMDQuartzRangeString(NSString *colorModeKey) {
    if ([colorModeKey containsString:@"fullrange"]) {
        return @"full";
    }
    if ([colorModeKey containsString:@"limitedrange"]) {
        return @"limited";
    }
    return @"unknown";
}

static NSString *OMDQuartzChromaString(NSString *colorModeKey) {
    if ([colorModeKey containsString:@"444"]) {
        return @"444";
    }
    if ([colorModeKey containsString:@"422"]) {
        return @"422";
    }
    if ([colorModeKey containsString:@"420"]) {
        return @"420";
    }
    return @"unknown";
}

static NSDictionary *OMDQuartzModeDictionary(id mode) {
    NSInteger width = OMDQuartzResponds(mode, @"width") ? OMDQuartzSendInteger(mode, @"width") : 0;
    NSInteger height = OMDQuartzResponds(mode, @"height") ? OMDQuartzSendInteger(mode, @"height") : 0;
    double refresh = OMDQuartzResponds(mode, @"refreshRate") ? OMDQuartzSendDouble(mode, @"refreshRate") : 0;
    NSInteger bitDepth = OMDQuartzResponds(mode, @"bitDepth") ? OMDQuartzSendInteger(mode, @"bitDepth") : 0;
    id colorMode = OMDQuartzResponds(mode, @"colorMode") ? OMDQuartzSendObject(mode, @"colorMode") : nil;
    NSNumber *ycbcr = OMDQuartzResponds(mode, @"colorModeIsYCbCr") ? @(OMDQuartzSendBool(mode, @"colorModeIsYCbCr")) : nil;
    id hdrMode = OMDQuartzResponds(mode, @"hdrMode") ? OMDQuartzSendObject(mode, @"hdrMode") : nil;
    BOOL virtualMode = OMDQuartzResponds(mode, @"isVirtual") ? OMDQuartzSendBool(mode, @"isVirtual") : NO;
    BOOL vrr = OMDQuartzResponds(mode, @"isVRR") ? OMDQuartzSendBool(mode, @"isVRR") : NO;
    BOOL highBandwidth = OMDQuartzResponds(mode, @"isHighBandwidth") ? OMDQuartzSendBool(mode, @"isHighBandwidth") : NO;
    NSString *colorModeKey = OMDQuartzSanitizedKey(colorMode, @"unknown");
    NSString *hdrModeKey = OMDQuartzHDRString(hdrMode);

    NSDictionary *dictionary = @{
        @"width": @(width),
        @"height": @(height),
        @"refreshHz": @(refresh),
        @"bitDepth": @(bitDepth),
        @"encoding": OMDQuartzEncodingString(ycbcr),
        @"range": OMDQuartzRangeString(colorModeKey),
        @"chroma": OMDQuartzChromaString(colorModeKey),
        @"hdrMode": hdrModeKey,
        @"isVirtual": @(virtualMode),
        @"isVRR": @(vrr),
        @"isHighBandwidth": @(highBandwidth)
    };

    return dictionary;
}

static NSArray<NSDictionary *> *OMDQuartzModeDictionariesForDisplay(id display) {
    if (!OMDQuartzResponds(display, @"availableModes")) {
        return @[];
    }

    NSArray *modes = OMDQuartzSendObject(display, @"availableModes");
    if (![modes isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:modes.count];

    for (id mode in modes) {
        [result addObject:OMDQuartzModeDictionary(mode)];
    }

    return result;
}

bool OMDQuartzBridgeIsAvailable(void) {
    Class displayClass = OMDQuartzCADisplayClass();
    return displayClass != Nil
        && [displayClass respondsToSelector:OMDQuartzSel(@"displays")]
        && [displayClass instancesRespondToSelector:OMDQuartzSel(@"availableModes")]
        && [displayClass instancesRespondToSelector:OMDQuartzSel(@"currentMode")]
        && [displayClass instancesRespondToSelector:OMDQuartzSel(@"setCurrentMode:")];
}

CFArrayRef OMDQuartzCopyDisplayModeDictionaries(CGDirectDisplayID displayID, CFErrorRef *error) {
    __block NSArray *result = nil;
    BOOL ok = OMDQuartzTry(error, ^{
        id display = OMDQuartzDisplayForID(displayID);
        if (display == nil) {
            OMDQuartzSetError(error, OMDQuartzBridgeErrorDisplayNotFound, @"CADisplay not found for CGDirectDisplayID");
            return;
        }
        result = OMDQuartzModeDictionariesForDisplay(display);
    });

    if (!ok || result == nil) {
        return nil;
    }
    return CFBridgingRetain(result);
}

CFDictionaryRef OMDQuartzCopyCurrentDisplayModeDictionary(CGDirectDisplayID displayID, CFErrorRef *error) {
    __block NSDictionary *result = nil;
    BOOL ok = OMDQuartzTry(error, ^{
        id display = OMDQuartzDisplayForID(displayID);
        if (display == nil) {
            OMDQuartzSetError(error, OMDQuartzBridgeErrorDisplayNotFound, @"CADisplay not found for CGDirectDisplayID");
            return;
        }
        if (!OMDQuartzResponds(display, @"currentMode")) {
            OMDQuartzSetError(error, OMDQuartzBridgeErrorSelectorUnavailable, @"CADisplay currentMode selector unavailable");
            return;
        }
        id currentMode = OMDQuartzSendObject(display, @"currentMode");
        if (currentMode == nil) {
            OMDQuartzSetError(error, OMDQuartzBridgeErrorCurrentModeUnavailable, @"CADisplay currentMode returned nil");
            return;
        }

        NSArray<NSDictionary *> *modes = OMDQuartzModeDictionariesForDisplay(display);
        NSUInteger modeIndex = NSNotFound;
        NSArray *availableModes = OMDQuartzSendObject(display, @"availableModes");
        if ([availableModes isKindOfClass:[NSArray class]]) {
            NSUInteger found = [availableModes indexOfObject:currentMode];
            if (found != NSNotFound && found < modes.count) {
                modeIndex = found;
            }
        }
        if (modeIndex != NSNotFound && modeIndex < modes.count) {
            NSMutableDictionary *dictionary = [modes[modeIndex] mutableCopy];
            dictionary[@"modeIndex"] = @(modeIndex);
            result = dictionary;
        } else {
            result = OMDQuartzModeDictionary(currentMode);
        }
    });

    if (!ok || result == nil) {
        return nil;
    }
    return CFBridgingRetain(result);
}

bool OMDQuartzSetCurrentDisplayModeAtIndex(CGDirectDisplayID displayID, CFIndex modeIndex, bool *attemptedMutation, CFErrorRef *error) {
    __block BOOL didSet = NO;
    BOOL ok = OMDQuartzTry(error, ^{
        if (attemptedMutation != NULL) {
            *attemptedMutation = false;
        }
        id display = OMDQuartzDisplayForID(displayID);
        if (display == nil) {
            OMDQuartzSetError(error, OMDQuartzBridgeErrorDisplayNotFound, @"CADisplay not found for CGDirectDisplayID");
            return;
        }
        if (!OMDQuartzResponds(display, @"availableModes") || !OMDQuartzResponds(display, @"setCurrentMode:")) {
            OMDQuartzSetError(error, OMDQuartzBridgeErrorSelectorUnavailable, @"CADisplay mode selectors unavailable");
            return;
        }

        NSArray *availableModes = OMDQuartzSendObject(display, @"availableModes");
        if (modeIndex < 0 || (NSUInteger)modeIndex >= availableModes.count) {
            OMDQuartzSetError(error, OMDQuartzBridgeErrorModeIndexUnavailable, @"Display mode index is not available for the current display");
            return;
        }

        id selectedMode = availableModes[(NSUInteger)modeIndex];
        if (attemptedMutation != NULL) {
            *attemptedMutation = true;
        }
        OMDQuartzSendVoidObject(display, @"setCurrentMode:", selectedMode);
        didSet = YES;
    });

    return ok && didSet;
}
