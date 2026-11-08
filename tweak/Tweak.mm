//
//  Tweak.mm
//  Điểm vào: cài hook code an toàn + UI sau khi app khởi tạo xong,
//  không dùng Logos/%hook, không swizzle method quan trọng của app
//  (để chạy song song với VSPlusUltra / VSFix / CydiaSubstrate và bảo toàn Pro).
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

        // Chỉ đăng ký observer, cài hook + UI sau khi app hoàn tất khởi tạo
        // để giảm thiểu can thiệp vào quá trình kích hoạt Pro của VSPlusUltra.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                VSToolboxInstallHooks();      // cài hook code an toàn
                [[VSUI sharedUI] install];    // cài UI 🌸
            });
        }];

        // Fallback nếu notification không phát sinh
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            VSToolboxInstallHooks();
            [[VSUI sharedUI] install];
        });
    }
}
