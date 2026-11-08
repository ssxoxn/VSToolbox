//
//  Tweak.mm
//  Điểm vào: cài UI sau khi app khởi tạo xong.
//  KHÔNG hook method nào của app: bắt code bằng cách đọc QRCodes.plist
//  → không xung đột với VSPlusUltra / VSFix1-4 / CydiaSubstrate.
//

#import "VSToolbox.h"

__attribute__((constructor))
static void VSToolboxInit(void) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:@"com.frontierdesign.videostar"]) {
            return;
        }

        VSLog(@"đang nạp vào %@ (VSToolbox)", bundleID);

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [[VSUI sharedUI] install];
            });
        }];
    }
}
