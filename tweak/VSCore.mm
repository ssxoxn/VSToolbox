//
//  VSCore.mm
//  Phần lõi: màu, helper, chẩn đoán Pro, lịch sử code, quét lớp,
//  phiên nhập hàng loạt (polling).
//  KHÔNG hook method nào của app (Plan C): bắt code bằng cách đọc
//  QRCodes.plist → không xung đột VSPlusUltra / VSFix1-4 / CydiaSubstrate.
//

#import "VSToolbox.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdlib.h>
#import <string.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <CoreImage/CoreImage.h>
#import <CoreImage/CIFilterBuiltins.h>

// =====================================================================
// MARK: - Màu
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
// MARK: - Chẩn đoán Pro (CHỈ ĐỌC — không hook, không sửa gì)
// =====================================================================

static NSString *VSDiagImageName(const char *fname) {
    NSString *path = [NSString stringWithUTF8String:fname ?: ""];
    NSString *base = [path lastPathComponent];
    if (!base.length) base = path;
    // "Video Star" = main executable → hook KHÔNG có; "...dylib" = hook đã cài
    return base ?: path;
}

NSArray<NSDictionary *> *VSProStatus(void) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *members = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        members = @{
            @"StoreModel" : @[@"ownedProducts",
                              @"numberOfTheseProductsOwned:",
                              @"boughtProduct:",
                              @"subscriptionActive",
                              @"autoRenewON",
                              @"purchasedCount"],
            @"QRCodeManager" : @[@"validQRCheck:",
                                 @"saveCodeToPlist:desc:",
                                 @"startQRImport",
                                 @"setQRCodeUsed:",
                                 @"selectedCode:withImageData:"],
            @"RootViewController" : @[@"viewDidAppear:",
                                      @"vsPLus:"],
            @"UILabel" : @[@"setText:"],
        };
    });

    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (NSString *clsName in members) {
        Class cls = objc_getClass(clsName.UTF8String);
        if (!cls) {
            [rows addObject:@{@"member": [clsName stringByAppendingString:@" (class?!)"],
                              @"owner": @"", @"ok": @NO, @"missing": @YES}];
            continue;
        }
        for (NSString *selName in members[clsName]) {
            SEL sel = NSSelectorFromString(selName);
            IMP imp = class_getMethodImplementation(cls, sel);
            NSDictionary *row;
            if (!imp) {
                row = @{@"member": [NSString stringWithFormat:@"%@.%@",
                                    clsName, selName],
                        @"owner": @"", @"ok": @NO, @"missing": @YES};
            } else {
                Dl_info info;
                NSString *owner = @"";
                if (dladdr((void *)imp, &info) && info.dli_fname) {
                    owner = VSDiagImageName(info.dli_fname);
                }
                BOOL ok = [owner containsString:@"Ultra"] ||
                          [owner containsString:@"dylib"];
                row = @{@"member": [NSString stringWithFormat:@"%@.%@",
                                    clsName, selName],
                        @"owner": owner, @"ok": @(ok), @"missing": @NO};
            }
            [rows addObject:row];
        }
    }
    return rows;
}

NSArray<NSString *> *VSLoadedDylibs(NSInteger *outTotal) {
    uint32_t n = _dyld_image_count();
    NSMutableArray<NSString *> *custom = [NSMutableArray array];
    for (uint32_t i = 0; i < n; i++) {
        const char *name = _dyld_get_image_name(i);
        NSString *path = [NSString stringWithUTF8String:name ?: ""] ?: @"";
        NSString *base = path.lastPathComponent;
        BOOL system = [path hasPrefix:@"/System/Library/"] ||
                      [path hasPrefix:@"/usr/lib/"] ||
                      [path hasPrefix:@"/private/preboot/"];
        if (system || base.length == 0) continue;
        [custom addObject:base];
    }
    if (outTotal) *outTotal = (NSInteger)n;
    return custom;
}

// =====================================================================
// MARK: - Lịch sử code (tự động bắt từ app + nhập thủ công)
// =====================================================================

static NSString *const kVSCodesKey = @"VSToolbox.codes.v1";

@implementation VSCodeEntry
@end

@interface VSCodeStore ()
- (NSArray<NSDictionary *> *)rawEntries;
- (void)addCodeQuietly:(NSString *)code source:(NSString *)source;
- (void)importFromAppPlists;
- (void)collectCodesFrom:(id)obj into:(NSMutableArray<NSString *> *)out depth:(int)depth;
- (void)collectCodesFromString:(NSString *)s into:(NSMutableArray<NSString *> *)out;
@end

@implementation VSCodeStore

+ (instancetype)sharedStore {
    static VSCodeStore *store = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [[VSCodeStore alloc] init]; });
    return store;
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

    VSLog(@"code mới: %@ (%@)", trimmed, source ?: @"?");
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

- (void)checkClipboard {
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    NSString *text = [pb string];
    if (!text || text.length == 0) return;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 6 || trimmed.length > 512) return;
    for (VSCodeEntry *e in [self entries]) {
        if ([e.code isEqualToString:trimmed]) return;
    }
    [self addCode:trimmed source:@"Clipboard"];
}

// ---------- Đọc code trực tiếp từ QRCodes.plist của app ----------

// App lưu code qua QRCodeManager.saveCodeToPlist:desc: vào QRCodes.plist.
// Đọc file (thụ động) thay vì hook method → không xung đột với VSPlusUltra/VSFix.
- (void)importFromAppPlists {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *home = NSHomeDirectory();
    [paths addObject:[home stringByAppendingPathComponent:@"Library/QRCodes.plist"]];
    [paths addObject:[home stringByAppendingPathComponent:@"Library/Caches/QRCodes.plist"]];
    [paths addObject:[home stringByAppendingPathComponent:@"Documents/QRCodes.plist"]];
    [paths addObject:[home stringByAppendingPathComponent:@"QRCodes.plist"]];

    NSMutableArray<NSString *> *found = [NSMutableArray array];
    for (NSString *path in paths) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        id plist = [NSPropertyListSerialization propertyListWithData:data
                                                             options:0
                                                              format:nil
                                                               error:nil];
        if (plist) {
            [self collectCodesFrom:plist into:found depth:0];
            VSLog(@"QRCodes.plist: %@ → %lu code", path, (unsigned long)found.count);
        }
    }

    NSUInteger added = 0;
    for (NSString *code in found) {
        BOOL exists = NO;
        for (VSCodeEntry *e in [self entries]) {
            if ([e.code isEqualToString:code]) { exists = YES; break; }
        }
        if (!exists) {
            [self addCodeQuietly:code source:@"QRCodes.plist"];
            added++;
        }
    }
    if (added > 0) {
        VSLog(@"lấy thêm %lu code từ plist (%@)", (unsigned long)added, found.firstObject);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[VSUI sharedUI] refreshPanel];
        });
    }
}

// Tương tự addCode nhưng không log/toast và không refresh — dùng khi quét nhiều code.
- (void)addCodeQuietly:(NSString *)code source:(NSString *)source {
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
}

- (void)collectCodesFromString:(NSString *)s into:(NSMutableArray<NSString *> *)out {
    if (![s isKindOfClass:[NSString class]]) return;
    NSString *t = [s stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length < 6 || t.length > 512) return;
    if (![out containsObject:t]) [out addObject:t];
}

- (void)collectCodesFrom:(id)obj into:(NSMutableArray<NSString *> *)out depth:(int)depth {
    if (depth > 4 || !obj) return;
    if ([obj isKindOfClass:[NSString class]]) {
        [self collectCodesFromString:obj into:out];
        return;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)obj;
        for (id key in d) {
            id v = d[key];
            if ([v isKindOfClass:[NSString class]]) {
                // bỏ qua field mô tả (desc) — chỉ lấy code thật
                if ([key isKindOfClass:[NSString class]] &&
                    ([key isEqualToString:@"desc"] ||
                     [key caseInsensitiveCompare:@"description"] == NSOrderedSame)) continue;
                [self collectCodesFromString:v into:out];
            } else {
                [self collectCodesFrom:v into:out depth:depth + 1];
            }
        }
        return;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id v in (NSArray *)obj) [self collectCodesFrom:v into:out depth:depth + 1];
    }
}

@end

// =====================================================================
// MARK: - Layer info
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
// MARK: - VSContext
// =====================================================================

@interface VSContext ()
- (UIWindow *)appWindow;
- (BOOL)isMultiLayerVC:(UIViewController *)vc;
- (UIViewController *)searchMultiLayerIn:(UIViewController *)vc depth:(int)depth;
- (void)openPhotoPicker;
- (void)openVideoPicker;
- (void)dismissPresentedPicker;
- (BOOL)layerHasContent:(unsigned long long)number;
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
        if (w.tag == 0x56535442) continue;                  // cửa sổ của tweak
        if (w.hidden || w.alpha < 0.01) continue;
        if (!w.rootViewController) continue;

        if (!bestAny || w.windowLevel >= bestAny.windowLevel) bestAny = w;
        if (w.windowLevel == UIWindowLevelNormal && !best) best = w;
    }
    return best ?: bestAny;
}

- (UIViewController *)topViewController {
    UIViewController *vc = [self appWindow].rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
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

- (NSArray<VSLayerInfo *> *)candidatesForVideo:(BOOL)video {
    (void)video;
    NSMutableArray<VSLayerInfo *> *out = [NSMutableArray array];
    for (VSLayerInfo *info in [self scanLayers]) {
        if ([info isMediaCandidate]) [out addObject:info];
    }
    return out;
}

- (NSArray<VSLayerInfo *> *)mediaCandidates {
    return [self candidatesForVideo:NO];
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
        VSLog(@"chọn lớp %llu", number);
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

- (void)openPhotoPicker {
    UIViewController *vc = [self multiLayerViewController];
    if (!vc) return;
    VSCallVoid(vc, @selector(showPhotoPicker));
}

- (void)openVideoPicker {
    UIViewController *vc = [self multiLayerViewController];
    if (!vc) return;
    if ([vc respondsToSelector:@selector(presentImportVideo)]) {
        VSCallVoid(vc, @selector(presentImportVideo));
    } else {
        VSCallVoid(vc, @selector(importVideo));
    }
}

// Đóng picker mà app đang present (dùng khi người dùng bấm Bỏ qua / Dừng).
- (void)dismissPresentedPicker {
    UIViewController *vc = [self multiLayerViewController];
    if (!vc) return;
    UIViewController *presented = vc.presentedViewController;
    if (!presented) presented = vc.navigationController.presentedViewController;
    if (!presented) return;
    VSLog(@"đóng picker đang mở");
    [presented dismissViewControllerAnimated:YES completion:nil];
}

// Kiểm tra layer đã có nội dung (origAssetInfo != nil) hay chưa.
// Dùng cho polling sau khi gọi picker của app.
- (BOOL)layerHasContent:(unsigned long long)number {
    id engine = [self engine];
    if (!engine) return NO;
    id layer = VSCallULL(engine, @selector(layerAtLayerNum:), number);
    if (!layer || [layer isKindOfClass:[NSNull class]]) return NO;
    return VSCall0(layer, @selector(origAssetInfo)) != nil;
}

- (void)applyImage:(UIImage *)image toLayers:(NSArray<NSNumber *> *)layers {
    if (!image || !layers) return;
    id engine = [self engine];
    if (!engine) return;
    SEL sel = @selector(setupImage:layerNum:layerType:clearMask:);
    if (![engine respondsToSelector:sel]) return;
    for (NSNumber *num in layers) {
        unsigned long long layer = [num unsignedLongLongValue];
        int layerType = [self layerTypeFor:layer];
        ((void (*)(id, SEL, id, unsigned long long, int, BOOL))objc_msgSend)
            (engine, sel, image, layer, layerType, NO);
    }
    [self refreshEditor];
}

@end

// =====================================================================
// MARK: - VSImagePicker (chọn ảnh từ thư viện bằng picker hệ thống)
// =====================================================================

@implementation VSImagePicker {
    UIViewController *_presentingVC;
    void (^_completion)(UIImage *);
}

+ (instancetype)sharedPicker {
    static VSImagePicker *picker = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ picker = [[VSImagePicker alloc] init]; });
    return picker;
}

- (void)pickImageFrom:(UIViewController *)vc completion:(void (^)(UIImage *image))completion {
    if (!vc) return;
    _presentingVC = vc;
    _completion = [completion copy];

    UIImagePickerController *p = [[UIImagePickerController alloc] init];
    p.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    p.mediaTypes = @[ @"public.image" ];
    p.allowsEditing = NO;
    p.delegate = self;
    [vc presentViewController:p animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:nil];

    void (^c)(UIImage *) = _completion;
    _completion = nil;
    _presentingVC = nil;
    if (image && c) c(image);
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
    _completion = nil;
    _presentingVC = nil;
}

@end

// =====================================================================
// MARK: - Tạo QR image từ code (CIQRCodeGenerator, không dùng method app)
// =====================================================================

UIImage *VSMakeQRImage(NSString *code) {
    if (![code isKindOfClass:[NSString class]] || code.length == 0) return nil;

    NSData *data = [code dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;

    CIFilter<CIQRCodeGenerator> *filter =
        (CIFilter<CIQRCodeGenerator> *)[CIFilter filterWithName:@"CIQRCodeGenerator"];
    if (!filter) return nil;
    [filter setValue:data forKey:@"inputMessage"];
    [filter setValue:@"H" forKey:@"inputCorrectionLevel"];

    CIImage *outImage = filter.outputImage;
    if (!outImage) return nil;

    static CIContext *ctx = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ctx = [CIContext contextWithOptions:nil];
    });

    CGImageRef cg = [ctx createCGImage:outImage fromRect:outImage.extent];
    if (!cg) return nil;

    UIImage *ui = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return ui;
}

// =====================================================================
// MARK: - Phiên nhập hàng loạt (polling, không swizzle)
// =====================================================================

@interface VSBulkSession : NSObject
+ (instancetype)sharedSession;
@property (nonatomic, readonly) BOOL active;
@property (nonatomic, readonly) BOOL videoMode;
@property (nonatomic, readonly) NSUInteger doneCount;
@property (nonatomic, readonly) NSUInteger targetCount;
@property (nonatomic, readonly) unsigned long long currentLayer;
- (void)startWithTargets:(NSArray<NSNumber *> *)targets video:(BOOL)video;
- (void)stop;
- (void)skip;
@end

@implementation VSBulkSession {
    NSArray<NSNumber *> *_targets;
    NSUInteger _index;
    NSUInteger _done;
    NSUInteger _generation;
    BOOL _active;
    BOOL _video;
    BOOL _awaiting;
    NSUInteger _pollAttempts;
}

+ (instancetype)sharedSession {
    static VSBulkSession *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[VSBulkSession alloc] init]; });
    return s;
}

- (BOOL)active            { return _active; }
- (BOOL)videoMode         { return _video; }
- (NSUInteger)doneCount   { return _done; }
- (NSUInteger)targetCount { return _targets.count; }

- (unsigned long long)currentLayer {
    if (_index >= _targets.count) return 0;
    return (unsigned long long)_targets[_index].unsignedLongLongValue;
}

- (void)startWithTargets:(NSArray<NSNumber *> *)targets video:(BOOL)video {
    if (targets.count == 0) {
        VSToast(@"Không có lớp nào phù hợp");
        return;
    }
    [self stop];
    _targets = [targets copy];
    _index = 0;
    _done = 0;
    _video = video;
    _active = YES;
    _awaiting = NO;
    _pollAttempts = 0;
    _generation++;
    VSLog(@"bắt đầu nhập %@ cho %lu lớp", video ? @"video" : @"ảnh", (unsigned long)targets.count);
    [self updateBanner];
    [self openPickerForCurrent];
}

- (void)stop {
    _active = NO;
    _awaiting = NO;
    _pollAttempts = 0;
    _generation++;
    _targets = nil;
    _index = 0;
    [[VSContext sharedContext] dismissPresentedPicker];
    [[VSUI sharedUI] hideBanner];
}

- (void)stopWithMessage:(NSString *)message {
    [self stop];
    if (message.length) VSToast(message);
}

- (void)skip {
    if (!_active || !_targets) return;
    _awaiting = NO;
    _pollAttempts = 0;
    _index++;
    [[VSContext sharedContext] dismissPresentedPicker];
    if (_index >= _targets.count) {
        [self finish];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self->_active) return;
        [self openPickerForCurrent];
    });
}

- (void)finish {
    NSUInteger done = _done;
    [self stop];
    VSToast([NSString stringWithFormat:@"Xong! Đã nhập %lu lớp", (unsigned long)done]);
}

- (void)updateBanner {
    NSString *kind = _video ? @"Nhập video" : @"Nhập ảnh";
    NSString *text = [NSString stringWithFormat:@"%@ • lớp %llu (%lu/%lu)",
                      kind, [self currentLayer], (unsigned long)(_index + 1),
                      (unsigned long)_targets.count];
    __weak typeof(self) weakSelf = self;
    [[VSUI sharedUI] showBanner:text
                         onSkip:^{ [weakSelf skip]; }
                         onStop:^{ [weakSelf stop]; }];
}

- (void)openPickerForCurrent {
    if (!_active) return;
    if (_index >= _targets.count) { [self finish]; return; }

    UIViewController *vc = [[VSContext sharedContext] multiLayerViewController];
    if (!vc) {
        [self stopWithMessage:@"Hãy mở trình chỉnh lớp (Multi Layer) trước"];
        return;
    }

    NSUInteger gen = _generation;
    unsigned long long layer = [self currentLayer];
    [[VSContext sharedContext] selectLayer:layer];
    [self updateBanner];

    _pollAttempts = 0;
    _awaiting = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self->_active || gen != self->_generation) return;
        [self invokePickerOn:vc generation:gen];
        [self startPolling:gen];
    });
}

- (void)invokePickerOn:(UIViewController *)vc generation:(NSUInteger)gen {
    if (_video) {
        if ([vc respondsToSelector:@selector(presentImportVideo)]) {
            VSCallVoid(vc, @selector(presentImportVideo));
        } else if ([vc respondsToSelector:@selector(importVideo)]) {
            VSCallVoid(vc, @selector(importVideo));
        } else {
            [self stopWithMessage:@"Bản app này không hỗ trợ chọn video"];
        }
        return;
    }

    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
    BOOL preferReplace = ([def objectForKey:@"VSToolbox.preferReplace"] != nil)
                       ? [def boolForKey:@"VSToolbox.preferReplace"]
                       : YES;

    if (preferReplace && [vc respondsToSelector:@selector(pickNewContent)]) {
        VSCallVoid(vc, @selector(pickNewContent));
        return;
    }

    if ([vc respondsToSelector:@selector(showPhotoPicker)]) {
        VSCallVoid(vc, @selector(showPhotoPicker));
    } else {
        [self stopWithMessage:@"Bản app này không hỗ trợ chọn ảnh"];
    }
}

// Polling mỗi 0.5 giây: kiểm tra layer mục tiêu đã có nội dung chưa.
// Nếu có → app đã gán xong media → chuyển lớp tiếp.
// Nếu quá 15 giây (30 lần) vẫn không có → coi như người dùng hủy picker → bỏ qua.
- (void)startPolling:(NSUInteger)gen {
    if (!self->_active || !self->_awaiting) return;

    _pollAttempts++;
    unsigned long long layer = [self currentLayer];
    BOOL hasContent = [[VSContext sharedContext] layerHasContent:layer];

    if (hasContent) {
        [self layerReady:gen];
        return;
    }

    if (_pollAttempts >= 30) { // 30 * 0.5s = 15s
        VSLog(@"poll timeout cho lớp %llu", layer);
        [self skipLayer:gen];
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self startPolling:gen];
    });
}

- (void)layerReady:(NSUInteger)gen {
    if (!self->_active || gen != self->_generation) return;
    _awaiting = NO;

    _done++;
    _index++;

    if (_index >= _targets.count) {
        [self finish];
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!self->_active || gen != self->_generation) return;
            [self openPickerForCurrent];
        });
    }
}

- (void)skipLayer:(NSUInteger)gen {
    if (!self->_active || gen != self->_generation) return;
    _awaiting = NO;
    _pollAttempts = 0;
    _index++;

    if (_index >= _targets.count) {
        [self finish];
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!self->_active) return;
            [self openPickerForCurrent];
        });
    }
}

@end

