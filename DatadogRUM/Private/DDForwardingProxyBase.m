/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "DDForwardingProxyBase.h"

#if TARGET_OS_IOS || TARGET_OS_VISION
#import <UIKit/UIKit.h>
#endif

@implementation __dd_private_DDForwardingProxyBase

- (nullable id)forwardingTargetOrNil {
    return nil;
}

#pragma mark - ObjC forwarding chain

- (id)forwardingTargetForSelector:(SEL)aSelector {
    // Happy path: if the target is alive and responds, hand the call straight to it.
    // The ObjC runtime re-dispatches the selector directly to the returned object,
    // skipping the NSInvocation machinery entirely.
    id target = [self forwardingTargetOrNil];
    if (target != nil && [target respondsToSelector:aSelector]) {
        return target;
    }
    // Otherwise: returning nil tells the runtime to continue down the forwarding chain,
    // which means it will call our methodSignatureForSelector: + forwardInvocation: below
    // (where we can safely drop the call instead of crashing).
    return nil;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    // 1. Selectors that we (or NSObject) implement directly.
    NSMethodSignature *signature = [super methodSignatureForSelector:aSelector];
    if (signature != nil) {
        return signature;
    }

    // 2. Ask the live target if any.
    id target = [self forwardingTargetOrNil];
    if (target != nil) {
        signature = [target methodSignatureForSelector:aSelector];
        if (signature != nil) {
            return signature;
        }
    }

    // 3. The target is gone or doesn't know the selector. Try to recover the signature
    // from known UIKit delegate protocols so the NSInvocation has accurate return/arg shapes.
    // The invocation will still be dropped in forwardInvocation:; this just keeps the
    // runtime from raising "unrecognized selector".
#if TARGET_OS_IOS || TARGET_OS_VISION
    // Protocols UIKit dispatches via UIScrollView.delegate (and its subclass slots).
    // Includes informal protocols (e.g. UICollectionViewDelegateFlowLayout) that UIKit
    // probes via respondsToSelector: on the same delegate slot, not separate properties.
    Protocol * const knownProtocols[] = {
        @protocol(UIScrollViewDelegate),
        @protocol(UITableViewDelegate),
        @protocol(UICollectionViewDelegate),
        @protocol(UICollectionViewDelegateFlowLayout),
        @protocol(UITextViewDelegate),
    };
    const size_t count = sizeof(knownProtocols) / sizeof(knownProtocols[0]);
    for (size_t i = 0; i < count; i++) {
        struct objc_method_description description = protocol_getMethodDescription(
            knownProtocols[i], aSelector, NO /* isRequired */, YES /* isInstance */);
        if (description.types != NULL) {
            return [NSMethodSignature signatureWithObjCTypes:description.types];
        }
    }
#endif

    // 4. Final fallback: minimal void(self, _cmd) signature. Selectors with explicit
    // arguments must have their signatures recovered above; assuming any argument layout
    // here would risk misdescribing the ABI of unknown selectors. If a customer surfaces a
    // selector that hits this fallback, add its protocol to `knownProtocols` above.
    return [NSMethodSignature signatureWithObjCTypes:"v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    id target = [self forwardingTargetOrNil];
    if (target != nil && [target respondsToSelector:anInvocation.selector]) {
        [anInvocation invokeWithTarget:target];
        return;
    }
    // Target is gone or does not respond. Drop the invocation, but zero the return-value
    // buffer first so non-void callers (e.g. UITableViewDelegate's CGFloat-returning
    // sizing methods, UIScrollViewDelegate's UIView*-returning `viewForZooming`) get a
    // defined zero/nil default instead of reading undefined bytes from the return register.
    // For UIKit delegate methods, zeroed defaults map to "use system default" semantics
    // (e.g. CGFloat 0 = hidden row/header, nil UIView = no zoom target, BOOL NO = don't
    // perform action).
    NSUInteger returnLength = anInvocation.methodSignature.methodReturnLength;
    if (returnLength > 0) {
        void *zeroedReturn = calloc(1, returnLength);
        [anInvocation setReturnValue:zeroedReturn];
        free(zeroedReturn);
    }
}

@end
