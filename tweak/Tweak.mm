//
//  Tweak.mm
//  Điểm vào: chỉ cài UI, không dùng Logos/%hook và không swizzle method nào của app
//  (để chạy song song với VSPlusUltra / VSFix / CydiaSubstrate đã có sẵn trong IPA).
//

#import "VSToolbox.h"

__attribute__((constructor))
static void VSToolboxInit(void) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:@"com.frontierdesign.videostar"]) {
            return;
        }

        VSLog(@"đang nạp vào %@", bundleID);

        // Không còn gọi VSToolboxInstallHooks() — không swizzle method app,
        // tránh xung đột với dylib đã tiêm sẵn (VSPlusUltra, VSFix1-4, CydiaSubstrate).

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            [[VSUI sharedUI] install];
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[VSUI sharedUI] install];
        });
    }
}
