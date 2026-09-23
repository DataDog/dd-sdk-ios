#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
NSUInteger APIUnreadSceneReads(void);
NSDictionary *APIInvokeMain(UIWindowScene *scene);
void APIInvokeBackground(UIWindowScene *scene, void (^completion)(NSDictionary *receipt));
NS_ASSUME_NONNULL_END
