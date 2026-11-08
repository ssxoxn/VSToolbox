//
//  Tweak.mm
//  Điểm vào: chỉ cài UI sau khi app khởi tạo xong.
//  KHÔNG hook method nào của app (Plan B-off): bắt code bằng cách đọc
//  QRCodes.plist của app khi mở panel → không xung đột với
//  VSPlusUltra / VSFix1-4 / CydiaSubstrate, bảo toàn Pro.
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

        // Cài UI đúng 1 lần (dispatch_once bên trong), sau khi app xong khởi tạo.
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
