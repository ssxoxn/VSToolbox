//
//  VSCore.mm
//  Phần lõi: màu sắc, helper gọi method, quản lý code, quét lớp và gán ảnh.
//  Thiết kế độc lập: không hook chồng chéo lên QRCodeManager / MultiLayerWiz
//  để đảm bảo không gây lỗi nạp code hay xung đột với VSPlusUltra.dylib.
//

#import "VSToolbox.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreImage/CoreImage.h>
#import <stdlib.h>
#import <string.h>

// =====================================================================
// MARK: - Màu sắc
// =====================================================================

UIColor *VSPink(void) {
    static UIColor *c = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [UIColor colorWithRed:1.00 green:0.42 blue:0.62 alpha:1.0];   // #FF6B9E
    });
    return c;
}

UIColor *VSPinkDeep(void) {
    static UIColor *c = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [UIColor colorWithRed:0.91 green:0.22 blue:0.47 alpha:1.0];   // #E83878
    });
    return c;
}

UIColor *VSPinkSoft(void) {
    static UIColor *c = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [UIColor colorWithRed:1.00 green:0.91 blue:0.95 alpha:1.0];   // #FFE8F2
    });
    return c;
}

UIColor *VSBG(void) {
    static UIColor *c = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [UIColor colorWithRed:1.00 green:0.97 blue:0.98 alpha:1.0];   // #FFF7FA
    });
    return c;
}

UIColor *VSText(void) {
    static UIColor *c = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [UIColor colorWithRed:0.29 green:0.17 blue:0.22 alpha:1.0];   // #4A2C38
    });
    return c;
}

// =====================================================================
// MARK: - Log
// =====================================================================

void VSLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[VSToolbox] %@", msg);
}

// =====================================================================
// MARK: - Gọi selector an toàn
// =====================================================================

BOOL VSResp(id obj, SEL sel) {
    return obj && sel && [obj respondsToSelector:sel];
}

id VSCall0(id obj, SEL sel) {
    if (!VSResp(obj, sel)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

id VSCall1(id obj, SEL sel, id a) {
    if (!VSResp(obj, sel)) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, a);
}

id VSCall2(id obj, SEL sel, id a, id b) {
    if (!VSResp(obj, sel)) return nil;
    return ((id (*)(id, SEL, id, id))objc_msgSend)(obj, sel, a, b);
}

id VSCallULL(id obj, SEL sel, unsigned long long v) {
    if (!VSResp(obj, sel)) return nil;
    return ((id (*)(id, SEL, unsigned long long))objc_msgSend)(obj, sel, v);
}

void VSCallVoid(id obj, SEL sel) {
    if (!VSResp(obj, sel)) return;
    ((void (*)(id, SEL))objc_msgSend)(obj, sel);
}

void VSCallVoidULL(id obj, SEL sel, unsigned long long v) {
    if (!VSResp(obj, sel)) return;
    ((void (*)(id, SEL, unsigned long long))objc_msgSend)(obj, sel, v);
}

void VSCallVoidULLBool(id obj, SEL sel, unsigned long long v, BOOL b) {
    if (!VSResp(obj, sel)) return;
    ((void (*)(id, SEL, unsigned long long, BOOL))objc_msgSend)(obj, sel, v, b);
}

BOOL VSCallBool(id obj, SEL sel) {
    if (!VSResp(obj, sel)) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
}

BOOL VSCallBoolULL(id obj, SEL sel, unsigned long long v) {
    if (!VSResp(obj, sel)) return NO;
    return ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(obj, sel, v);
}

int VSCallInt(id obj, SEL sel) {
    if (!VSResp(obj, sel)) return 0;
    return ((int (*)(id, SEL))objc_msgSend)(obj, sel);
}

int VSCallIntULL(id obj, SEL sel, unsigned long long v) {
    if (!VSResp(obj, sel)) return 0;
    return ((int (*)(id, SEL, unsigned long long))objc_msgSend)(obj, sel, v);
}

// =====================================================================
// MARK: - Lịch sử code & Tự động nhận diện Clipboard
// =====================================================================

static NSString *const kVSCodesKey = @"VSToolbox.codes.v2";

@implementation VSCodeEntry
@end

@implementation VSCodeStore

+ (instancetype)sharedStore {
    static VSCodeStore *store = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[VSCodeStore alloc] init];
    });
    return store;
}

- (void)checkClipboard {
    @try {
        UIPasteboard *pb = [UIPasteboard generalPasteboard];
        if (!pb.hasStrings) return;
        NSString *clip = pb.string;
        if (![clip isKindOfClass:[NSString class]]) return;
        NSString *trimmed = [clip stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length < 6 || trimmed.length > 512) return;

        NSArray<VSCodeEntry *> *current = [self entries];
        if (current.count > 0 && [current[0].code isEqualToString:trimmed]) {
            return; // Đã là code mới nhất
        }
        [self addCode:trimmed source:@"Clipboard"];
    } @catch (NSException *e) {
        VSLog(@"Clipboard check error: %@", e.reason);
    }
}

- (NSArray<NSDictionary *> *)rawEntries {
    id raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kVSCodesKey];
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (id item in (NSArray *)raw) {
        if ([item isKindOfClass:[NSDictionary class]]) [out addObject:item];
    }
    return out;
}

- (NSArray<VSCodeEntry *> *)entries {
    NSMutableArray<VSCodeEntry *> *out = [NSMutableArray array];
    for (NSDictionary *d in [self rawEntries]) {
        NSString *code = d[@"code"];
        if (![code isKindOfClass:[NSString class]] || code.length == 0) continue;
        VSCodeEntry *e = [[VSCodeEntry alloc] init];
        e.code = code;
        id src = d[@"source"];
        e.source = [src isKindOfClass:[NSString class]] ? src : @"";
        id ts = d[@"date"];
        e.date = [ts isKindOfClass:[NSNumber class]]
               ? [NSDate dateWithTimeIntervalSince1970:[ts doubleValue]]
               : [NSDate date];
        [out addObject:e];
    }
    return out;
}

- (void)addCode:(NSString *)code source:(NSString *)source {
    if (![code isKindOfClass:[NSString class]]) return;
    NSString *trimmed = [code stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 6 || trimmed.length > 512) return;

    NSMutableArray *list = [NSMutableArray array];
    [list addObject:@{
        @"code": trimmed,
        @"source": ([source isKindOfClass:[NSString class]] ? source : @""),
        @"date": @([[NSDate date] timeIntervalSince1970]),
    }];
    for (NSDictionary *old in [self rawEntries]) {
        NSString *oldCode = old[@"code"];
        if (![oldCode isKindOfClass:[NSString class]]) continue;
        if ([oldCode isEqualToString:trimmed]) continue;
        [list addObject:old];
        if (list.count >= VS_CODE_HISTORY) break;
    }
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:kVSCodesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    VSLog(@"Đã lưu code mới: %@ (%@)", trimmed, source ?: @"?");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[VSUI sharedUI] refreshPanel];
    });
}

- (void)removeAll {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kVSCodesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[VSUI sharedUI] refreshPanel];
    });
}

@end

// =====================================================================
// MARK: - Thông tin lớp (Layer Info)
// =====================================================================

@implementation VSLayerInfo

- (BOOL)isMediaCandidate {
    if (self.isNull) return NO;
    if (self.isText) return NO;
    if (self.is3D) return NO;
    if (self.hasExtra) return NO;
    return YES;
}

- (NSString *)typeTitle {
    if (self.isNull)   return @"Lớp trống";
    if (self.isText)   return @"Văn bản";
    if (self.is3D)     return @"3D";
    if (self.hasExtra) return @"Hiệu ứng";
    if (self.hasAsset) return @"Đã có nội dung";
    return @"Ảnh / Video (trống)";
}

@end

// =====================================================================
// MARK: - Trình chọn ảnh (VSImagePicker)
// =====================================================================

@implementation VSImagePicker {
    void (^_completion)(UIImage *);
}

+ (instancetype)sharedPicker {
    static VSImagePicker *p = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [[VSImagePicker alloc] init]; });
    return p;
}

- (void)pickImageFrom:(UIViewController *)vc completion:(void (^)(UIImage *image))completion {
    _completion = [completion copy];
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFullScreen;
    [vc presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    void (^cb)(UIImage *) = _completion;
    _completion = nil;
    [picker dismissViewControllerAnimated:YES completion:^{
        if (cb && img) {
            cb(img);
        }
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    _completion = nil;
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end

// =====================================================================
// MARK: - Ngữ cảnh MultiLayer (VSContext)
// =====================================================================

@interface VSContext ()
- (UIWindow *)appWindow;
- (BOOL)isMultiLayerVC:(UIViewController *)vc;
- (UIViewController *)searchMultiLayerIn:(UIViewController *)vc depth:(int)depth;
@end

@implementation VSContext

+ (instancetype)sharedContext {
    static VSContext *ctx = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ctx = [[VSContext alloc] init]; });
    return ctx;
}

- (UIWindow *)appWindow {
    UIWindow *best = nil;
    UIWindow *bestAny = nil;
    NSArray *windows = [UIApplication sharedApplication].windows;
    for (UIWindow *w in windows) {
        if (![w isKindOfClass:[UIWindow class]]) continue;
        if (w.tag == 0x56535442) continue;                  // Bỏ qua cửa sổ floating của tweak
        if (w.hidden || w.alpha < 0.01) continue;
        if (!w.rootViewController) continue;

        if (!bestAny || w.windowLevel >= bestAny.windowLevel) bestAny = w;
        if (w.windowLevel == UIWindowLevelNormal && !best) best = w;
    }
    return best ?: bestAny;
}

- (UIViewController *)topViewController {
    UIViewController *vc = [self appWindow].rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) {
        vc = vc.presentedViewController;
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        vc = [(UINavigationController *)vc visibleViewController];
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        vc = [(UITabBarController *)vc selectedViewController];
    }
    return vc;
}

- (BOOL)isMultiLayerVC:(UIViewController *)vc {
    if (!vc) return NO;
    NSString *name = NSStringFromClass([vc class]);
    if (![name hasPrefix:@"MultiLayerWiz"]) return NO;
    return [vc respondsToSelector:@selector(getMultiLayerEngine)];
}

- (UIViewController *)searchMultiLayerIn:(UIViewController *)vc depth:(int)depth {
    if (!vc || depth > 20) return nil;
    if ([self isMultiLayerVC:vc]) return vc;

    UIViewController *found = [self searchMultiLayerIn:vc.presentedViewController depth:depth + 1];
    if (found) return found;

    if ([vc isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)vc;
        for (UIViewController *c in nav.viewControllers) {
            if ([self isMultiLayerVC:c]) return c;
        }
        return [self searchMultiLayerIn:nav.visibleViewController depth:depth + 1];
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        return [self searchMultiLayerIn:[(UITabBarController *)vc selectedViewController] depth:depth + 1];
    }
    return nil;
}

- (UIViewController *)multiLayerViewController {
    return [self searchMultiLayerIn:[self appWindow].rootViewController depth:0];
}

- (BOOL)isInMultiLayerEditor {
    return [self multiLayerViewController] != nil;
}

- (id)engineFor:(UIViewController *)vc {
    if (!vc) return nil;
    if (![vc respondsToSelector:@selector(getMultiLayerEngine)]) return nil;
    return VSCall0(vc, @selector(getMultiLayerEngine));
}

- (id)engine {
    return [self engineFor:[self multiLayerViewController]];
}

- (NSArray<VSLayerInfo *> *)scanLayers {
    NSMutableArray<VSLayerInfo *> *out = [NSMutableArray array];
    UIViewController *vc = [self multiLayerViewController];
    id engine = [self engineFor:vc];
    if (!engine) return out;

    SEL layerAt = @selector(layerAtLayerNum:);
    SEL typeFor = @selector(layerTypeForLayer:);
    if (![engine respondsToSelector:layerAt]) return out;

    for (NSUInteger n = 0; n < VS_MAX_LAYERS; n++) {
        id layer = VSCallULL(engine, layerAt, (unsigned long long)n);
        if (!layer || [layer isKindOfClass:[NSNull class]]) continue;

        VSLayerInfo *info = [[VSLayerInfo alloc] init];
        info.number = n;
        info.type = [engine respondsToSelector:typeFor]
                   ? VSCallIntULL(engine, typeFor, (unsigned long long)n)
                   : 0;
        info.isNull   = VSCallBool(layer, @selector(isNullLayer));
        info.is3D     = VSCallBool(layer, @selector(is3DLayer));
        info.isText   = VSCall0(layer, @selector(textDictionary)) != nil;
        info.hasAsset = VSCall0(layer, @selector(origAssetInfo)) != nil;

        BOOL extra = NO;
        extra = extra || VSCallBoolULL(engine, @selector(overlayObjectExistsOnLayerNum:), n);
        extra = extra || VSCallBoolULL(engine, @selector(gifExistsOnLayerNum:), n);
        extra = extra || VSCallBoolULL(engine, @selector(zapsObjectExistsOnLayerNum:), n);
        extra = extra || VSCallBoolULL(engine, @selector(particlesExistOnLayerNum:), n);
        extra = extra || VSCallBoolULL(engine, @selector(drawingExistsOnLayerNum:), n);
        info.hasExtra = extra;

        [out addObject:info];
    }
    return out;
}

- (NSArray<VSLayerInfo *> *)mediaCandidates {
    NSMutableArray<VSLayerInfo *> *out = [NSMutableArray array];
    for (VSLayerInfo *info in [self scanLayers]) {
        if ([info isMediaCandidate]) [out addObject:info];
    }
    return out;
}

- (NSArray<VSLayerInfo *> *)candidatesForVideo:(BOOL)video {
    (void)video;
    return [self mediaCandidates];
}

- (int)layerTypeFor:(unsigned long long)number {
    id engine = [self engine];
    if (!engine) return 0;
    SEL sel = @selector(layerTypeForLayer:);
    if (![engine respondsToSelector:sel]) return 0;
    return VSCallIntULL(engine, sel, number);
}

- (void)selectLayer:(unsigned long long)number {
    UIViewController *vc = [self multiLayerViewController];
    if (!vc) return;
    SEL sel = @selector(selectLayerNum:flash:);
    if ([vc respondsToSelector:sel]) {
        VSCallVoidULLBool(vc, sel, number, YES);
        VSLog(@"Chọn lớp %llu", number);
    }
}

- (void)refreshEditor {
    UIViewController *vc = [self multiLayerViewController];
    if (!vc) return;
    VSCallVoid(vc, @selector(engineResync));
    VSCallVoid(vc, @selector(updateLayerEffectButtons));
    VSCallVoid(vc, @selector(refreshDisplay));
}

- (void)removeContentFromLayer:(unsigned long long)number {
    UIViewController *vc = [self multiLayerViewController];
    if (!vc) return;
    SEL sel = @selector(removeContentOnLayerNum:redraw:);
    if ([vc respondsToSelector:sel]) VSCallVoidULLBool(vc, sel, number, YES);
}

// Gán 1 ảnh trực tiếp vào danh sách các lớp đã chọn
- (void)applyImage:(UIImage *)image toLayers:(NSArray<NSNumber *> *)layers {
    if (!image || layers.count == 0) return;
    id engine = [self engine];
    if (!engine) {
        VSToast(@"Hãy mở trình chỉnh lớp (Multi Layer) trước");
        return;
    }

    SEL sel = @selector(setupImage:layerNum:layerType:clearMask:);
    if (![engine respondsToSelector:sel]) {
        VSToast(@"Bản app này không hỗ trợ gán ảnh tự động");
        return;
    }

    NSUInteger count = 0;
    for (NSNumber *num in layers) {
        unsigned long long n = [num unsignedLongLongValue];
        int type = [self layerTypeFor:n];
        @try {
            ((id (*)(id, SEL, id, unsigned long long, int, BOOL))objc_msgSend)
                (engine, sel, image, n, type, NO);
            count++;
        } @catch (NSException *e) {
            VSLog(@"Lỗi gán ảnh lớp %llu: %@", n, e.reason);
        }
    }

    [self refreshEditor];
    VSToast([NSString stringWithFormat:@"Đã nhập ảnh vào %lu lớp! 🌸", (unsigned long)count]);
}

@end

// =====================================================================
// MARK: - Tạo QR image từ code (Native CIQRCodeGenerator)
// =====================================================================

UIImage *VSMakeQRImage(NSString *code) {
    if (![code isKindOfClass:[NSString class]] || code.length == 0) return nil;

    @try {
        NSData *data = [code dataUsingEncoding:NSISOLatin1StringEncoding];
        if (!data) data = [code dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) return nil;

        CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
        [filter setValue:data forKey:@"inputMessage"];
        [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
        CIImage *ci = filter.outputImage;
        if (!ci) return nil;

        CGAffineTransform transform = CGAffineTransformMakeScale(10.0, 10.0);
        CIImage *scaled = [ci imageByApplyingTransform:transform];
        return [UIImage imageWithCIImage:scaled];
    } @catch (NSException *e) {
        VSLog(@"Lỗi tạo QR: %@", e.reason);
        return nil;
    }
}

// =====================================================================
// MARK: - Cài hook an toàn
// =====================================================================

void VSToolboxInstallHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Khởi động lắng nghe Clipboard
        [VSCodeStore sharedStore];
        VSLog(@"VSToolbox đã khởi tạo (chế độ an toàn, không can thiệp luồng nạp code).");
    });
}
