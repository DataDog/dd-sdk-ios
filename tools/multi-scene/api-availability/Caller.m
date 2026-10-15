#import "Caller.h"
@import DatadogRUM;

// A rejected call must return before treating its scene argument as UIKit.
@interface APIUnreadScene : NSObject
@property(class, atomic) NSUInteger reads;
@end
static NSUInteger sceneReads = 0;
@implementation APIUnreadScene
+ (NSUInteger)reads { @synchronized(self) { return sceneReads; } }
+ (void)setReads:(NSUInteger)value { @synchronized(self) { sceneReads = value; } }
- (id)session { APIUnreadScene.reads += 1; return nil; }
@end

NSUInteger APIUnreadSceneReads(void) { return APIUnreadScene.reads; }

static NSArray<NSString *> *invoke(DDRUMMonitor *monitor, UIWindowScene *scene, DDRUMViewTarget *target, NSString *prefix) {
    NSMutableArray *calls = [NSMutableArray new];
    NSDictionary *attrs = @{@"lane": prefix, @"from": @"objc"};
    NSDictionary *(^tagged)(NSString *) = ^NSDictionary *(NSString *form) { NSMutableDictionary *v = [attrs mutableCopy]; v[@"form"] = form; return v; };
    NSString *key = [prefix stringByAppendingString:@"-manual"];
    [monitor startViewWithKey:key name:key inScene:scene attributes:attrs]; [calls addObject:@"startView"];
    [monitor addFeatureFlagEvaluationWithName:prefix value:@YES view:target]; [calls addObject:@"flag"];
    [monitor addTimingWithName:prefix view:target]; [calls addObject:@"timing"];
    [monitor addViewLoadingTimeWithOverwrite:YES view:target]; [calls addObject:@"loading"];
    [monitor addViewAttributeForKey:prefix value:prefix view:target]; [calls addObject:@"attribute"];
    [monitor addViewAttributes:@{[prefix stringByAppendingString:@"-batch"]: prefix} view:target]; [calls addObject:@"attributes"];
    [monitor removeViewAttributeForKey:@"keep-single" view:target]; [calls addObject:@"removeAttribute"];
    [monitor removeViewAttributesForKeys:@[@"keep-batch"] view:target]; [calls addObject:@"removeAttributes"];
    [monitor addErrorWithMessage:prefix stack:@"stack" source:DDRUMErrorSourceCustom view:target attributes:tagged(@"message")]; [calls addObject:@"message"];
    [monitor addErrorWithError:[NSError errorWithDomain:prefix code:1 userInfo:nil] source:DDRUMErrorSourceCustom view:target attributes:tagged(@"error")]; [calls addObject:@"error"];
    NSURL *url = [NSURL URLWithString:[@"https://fixture.invalid/" stringByAppendingString:prefix]];
    [monitor startResourceWithResourceKey:[prefix stringByAppendingString:@"-request"] request:[NSURLRequest requestWithURL:url] view:target attributes:tagged(@"request")]; [calls addObject:@"request"];
    [monitor startResourceWithResourceKey:[prefix stringByAppendingString:@"-url"] url:url view:target attributes:tagged(@"url")]; [calls addObject:@"url"];
    [monitor startResourceWithResourceKey:[prefix stringByAppendingString:@"-method"] httpMethod:DDRUMMethodPut urlString:url.absoluteString view:target attributes:tagged(@"method")]; [calls addObject:@"method"];
    [monitor addActionWithType:DDRUMActionTypeCustom name:prefix view:target attributes:attrs]; [calls addObject:@"action"];
    [monitor startActionWithType:DDRUMActionTypeCustom name:[prefix stringByAppendingString:@"-continuous"] view:target attributes:attrs]; [calls addObject:@"startAction"];
    [monitor stopActionWithType:DDRUMActionTypeCustom name:[prefix stringByAppendingString:@"-ended"] view:target attributes:attrs]; [calls addObject:@"stopAction"];
    [monitor startOperationWithName:prefix operationKey:prefix view:target attributes:attrs options:nil]; [calls addObject:@"startOperation"];
    [monitor succeedOperationWithName:prefix operationKey:prefix view:target attributes:attrs]; [calls addObject:@"succeedOperation"];
    [monitor failOperationWithName:prefix operationKey:[prefix stringByAppendingString:@"-failed"] reason:DDRUMFeatureOperationFailureReasonError view:target attributes:attrs]; [calls addObject:@"failOperation"];
    [monitor stopViewWithKey:key inScene:scene attributes:@{@"lane": prefix, @"stop": @2}]; [calls addObject:@"stopView"];
    return calls;
}

NSDictionary *APIInvokeMain(UIWindowScene *scene) {
    DDRUMViewTarget *target = [DDRUMViewTarget currentInScene:scene];
    if (!target || !NSThread.isMainThread) return @{@"valid": @NO};
    return @{@"valid": @YES, @"calls": invoke([DDRUMMonitor shared], scene, target, @"objc-main")};
}

void APIInvokeBackground(UIWindowScene *scene, void (^completion)(NSDictionary *)) {
    DDRUMViewTarget *validTarget = [DDRUMViewTarget currentInScene:scene];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL nilFactory = [DDRUMViewTarget currentInScene:scene] == nil;
        __weak APIUnreadScene *weakScene;
        NSArray *calls;
        BOOL rejectedUnreadScene;
        @autoreleasepool {
            APIUnreadScene *unreadScene = [APIUnreadScene new];
            weakScene = unreadScene;
            rejectedUnreadScene = [DDRUMViewTarget currentInScene:(UIWindowScene *)unreadScene] == nil;
            calls = invoke([DDRUMMonitor shared], (UIWindowScene *)unreadScene, validTarget, @"off-main");
        }
        BOOL released = weakScene == nil;
        NSDictionary *receipt = @{@"onMain": @(NSThread.isMainThread), @"nilFactory": @(nilFactory),
                                  @"rejectedUnreadScene": @(rejectedUnreadScene), @"sceneReads": @(APIUnreadScene.reads),
                                  @"releasedScene": @(released), @"calls": calls};
        dispatch_async(dispatch_get_main_queue(), ^{ completion(receipt); });
    });
}
