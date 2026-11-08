//
//  Tweak.mm
//  Điểm vào: chẩn đoán Pro + cài UI sau khi app khởi tạo xong.
//  KHÔNG hook method nào của app: bắt code bằng cách đọc QRCodes.plist khi mở panel
//  → không xung đột với VSPlusUltra / VSFix1-4 / CydiaSubstrate.
//

#import "VSToolbox.h"
#import <dlfcn.h>
#import <objc/message.h>

// =========================================================================
// Chẩn đoán: các hook 'Pro' của VSPlusUltra (StoreModel/QRCodeManager) có
// được cài hay không? Không swizzle gì — chỉ đọc địa chỉ IMP và xem nó thuộc
// image nào (main executable = hook KHÔNG cài; VSPlusUltra.dylib = hook cài rồi).
// =========================================================================

static void VSDiagIMP(Class cls, SEL sel) {
    if (!cls || !sel) return;
    IMP imp = class_getMethodImplementation(cls, sel);
    if (!imp) { VSLog(@"[Diag] %@ không có IMP: %@", cls, sel); return; }
    Dl_info info;
    if (dladdr((void *)imp, &info) && info.dli_fname) {
        const char *fname = strrchr(info.dli_fname, '/');
        fname = fname ? fname + 1 : info.dli_fname;
        VSLog(@"[Diag] %s → IMP trong %s", sel_getName(sel), fname);
    }
}

static void VSCheckProStatus(void) {
    Class store = objc_getClass("StoreModel");
    Class qr = objc_getClass("QRCodeManager");
    Class root = objc_getClass("RootViewController");
    Class label = objc_getClass("UILabel");
    VSLog(@"[Diag] class StoreModel:%@ QRCodeManager:%@ RootVC:%@",
          store ? @"OK" : @"THIẾU",
          qr ? @"OK" : @"THIẾU",
          root ? @"OK" : @"THIẾU");
    if (!store) return;

    VSDiagIMP(store, @selector(ownedProducts));
    VSDiagIMP(store, @selector(numberOfTheseProductsOwned:));
    VSDiagIMP(store, @selector(boughtProduct:));
    VSDiagIMP(store, @selector(subscriptionActive));
    VSDiagIMP(qr, @selector(validQRCheck:));
    VSDiagIMP(qr, @selector(saveCodeToPlist:desc:));
    VSDiagIMP(qr, @selector(startQRImport));
    VSDiagIMP(root, @selector(viewDidAppear:));
    VSDiagIMP(label, @selector(setText:));
}

__attribute__((constructor))
static void VSToolboxInit(void) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:@"com.frontierdesign.videostar"]) {
            return;
        }

        VSLog(@"đang nạp vào %@ (VSToolbox)", bundleID);

        // Cài UI đúng 1 lần sau khi app xong khởi tạo, đồng thờichẩn đoán Pro.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                VSCheckProStatus();   // đọc IMP — không đổi gì
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [[VSUI sharedUI] install];
            });
        }];
    }
}
