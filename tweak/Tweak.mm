//
//  Tweak.mm
//  Điểm vào: chỉ cài UI sau khi app khởi tạo xong, không dùng Logos/%hook,
//  không swizzle method app nào (để chạy song song với VSPlusUltra / VSFix / CydiaSubstrate).
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

        // Không gọi VSToolboxInstallHooks() — không swizzle method app,
        // tránh xung đột với dylib đã tiêm sẵn (VSPlusUltra, VSFix1-4, CydiaSubstrate).

        // Chỉ đăng ký observer, cài UI sau khi app hoàn tất khởi tạo
        // để giảm thiểu can thiệp vào quá trình kích hoạt Pro của VSPlusUltra.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [[VSUI sharedUI] install];
            });
        }];

        // Fallback nếu notification không phát sinh
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[VSUI sharedUI] install];
        });
    }
}
