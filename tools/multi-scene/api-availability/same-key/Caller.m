#import "Caller.h"
@import DatadogRUM;

BOOL SameKeyInvoke(NSString *operation, NSString *owner, UIWindowScene *scene) {
    if (!NSThread.isMainThread) return NO;
    DDRUMViewTarget *target = [DDRUMViewTarget currentInScene:scene];
    if (!target) return NO;
    DDRUMMonitor *monitor = [DDRUMMonitor shared];
    NSDictionary *attrs = @{@"owner": owner};
    NSString *resource = [@"resource-" stringByAppendingString:owner];
    if ([operation isEqualToString:@"start"]) {
        [monitor startViewWithKey:@"shared-key" name:[@"view-" stringByAppendingString:owner] inScene:scene attributes:attrs];
    } else if ([operation isEqualToString:@"work"]) {
        [monitor addViewAttributeForKey:@"metadata" value:owner view:target];
        [monitor addActionWithType:DDRUMActionTypeCustom name:[@"action-" stringByAppendingString:owner] view:target attributes:attrs];
        [monitor addErrorWithMessage:[@"error-" stringByAppendingString:owner] stack:nil source:DDRUMErrorSourceCustom view:target attributes:attrs];
        [monitor startResourceWithResourceKey:resource url:[NSURL URLWithString:[@"https://fixture.invalid/" stringByAppendingString:owner]] view:target attributes:attrs];
    } else if ([operation isEqualToString:@"stop"]) {
        [monitor stopViewWithKey:@"shared-key" inScene:scene attributes:@{@"stopped": owner}];
    } else if ([operation isEqualToString:@"complete"]) {
        [monitor stopResourceWithResourceKey:resource statusCode:@200 kind:DDRUMResourceTypeNative size:@1 attributes:@{@"finished": owner}];
    } else if ([operation isEqualToString:@"reject"]) {
        [monitor addActionWithType:DDRUMActionTypeCustom name:@"rejected-B" view:target attributes:attrs];
        [monitor addErrorWithMessage:@"rejected-B" stack:nil source:DDRUMErrorSourceCustom view:target attributes:attrs];
        [monitor addViewAttributeForKey:@"metadata" value:@"rejected-B" view:target];
    } else if ([operation isEqualToString:@"peer"]) {
        [monitor addActionWithType:DDRUMActionTypeCustom name:@"peer-A" view:target attributes:attrs];
    } else { return NO; }
    return YES;
}
