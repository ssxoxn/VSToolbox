//
//  Tweak.mm
//  Điểm vào: chỉ cài hook + UI, không dùng Logos/%hook (app ký doanh nghiệp
//  không có CydiaSubstrate, nên mọi thứ chạy bằng method_setImplementation).
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
        VSToolboxInstallHooks();

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
