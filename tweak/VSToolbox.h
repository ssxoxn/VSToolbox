//
//  VSToolbox.h
//  VSToolbox — trợ thủ nhập code / nhập ảnh cho Video Star
//
//  Chỉ dùng cho mục đích cá nhân: nhập liệu nhanh.
//  Không can thiệp IAP / license / watermark.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define VS_MAX_LAYERS   41     // quét lớp 0..40
#define VS_CODE_HISTORY 20     // lưu tối đa 20 code gần đây

// ---- Màu (hồng cute) ----
UIColor *VSPink(void);
UIColor *VSPinkDeep(void);
UIColor *VSPinkSoft(void);
UIColor *VSBG(void);
UIColor *VSText(void);

// ---- Log / UI helpers ----
void VSLog(NSString *fmt, ...);
void VSToast(NSString *text);

// ---- Gọi selector an toàn ----
BOOL VSResp(id obj, SEL sel);
id VSCall0(id obj, SEL sel);
id VSCall1(id obj, SEL sel, id a);
id VSCall2(id obj, SEL sel, id a, id b);
id VSCallULL(id obj, SEL sel, unsigned long long v);
void VSCallVoid(id obj, SEL sel);
void VSCallVoidULL(id obj, SEL sel, unsigned long long v);
void VSCallVoidULLBool(id obj, SEL sel, unsigned long long v, BOOL b);
BOOL VSCallBool(id obj, SEL sel);
BOOL VSCallBoolULL(id obj, SEL sel, unsigned long long v);
int VSCallInt(id obj, SEL sel);
int VSCallIntULL(id obj, SEL sel, unsigned long long v);

// ---- Lịch sử code ----
@interface VSCodeEntry : NSObject
@property (nonatomic, copy) NSString *code;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, strong) NSDate *date;
@end

@interface VSCodeStore : NSObject
+ (instancetype)sharedStore;
- (NSArray<VSCodeEntry *> *)entries;
- (void)addCode:(NSString *)code source:(NSString *)source;
- (void)removeAll;
@end

// ---- Layer ----
@interface VSLayerInfo : NSObject
@property (nonatomic, assign) NSUInteger number;
@property (nonatomic, assign) int type;
@property (nonatomic, assign) BOOL isNull;
@property (nonatomic, assign) BOOL isText;
@property (nonatomic, assign) BOOL is3D;
@property (nonatomic, assign) BOOL hasAsset;
@property (nonatomic, assign) BOOL hasExtra;   // overlay / gif / zap / particle / drawing
- (BOOL)isMediaCandidate;
- (NSString *)typeTitle;
@end

@interface VSContext : NSObject
+ (instancetype)sharedContext;
- (UIViewController *)topViewController;
- (UIViewController *)multiLayerViewController;
- (BOOL)isInMultiLayerEditor;
- (id)engine;
- (id)engineFor:(UIViewController *)vc;
- (NSArray<VSLayerInfo *> *)scanLayers;
- (NSArray<VSLayerInfo *> *)candidatesForVideo:(BOOL)video;
- (int)layerTypeFor:(unsigned long long)number;
- (void)selectLayer:(unsigned long long)number;
- (void)refreshEditor;
- (void)removeContentFromLayer:(unsigned long long)number;
@end

// ---- Phiên nhập hàng loạt (dùng picker gốc của app) ----
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
- (void)noteImage:(id)image layer:(unsigned long long)layerNum type:(int)layerType;
- (void)noteVideo:(id)asset layer:(unsigned long long)layerNum volume:(float)volume;
@end

// ---- UI ----
@interface VSUI : NSObject
+ (instancetype)sharedUI;
- (void)install;
- (void)showPanel;
- (void)hidePanel;
- (void)refreshPanel;
- (BOOL)panelVisible;
- (void)showBanner:(NSString *)text onSkip:(void (^)(void))skip onStop:(void (^)(void))stop;
- (void)setBannerText:(NSString *)text;
- (void)hideBanner;
- (void)showToastText:(NSString *)text;
@end

// ---- Tạo QR image từ code ----
UIImage *VSMakeQRImage(NSString *code);

// ---- Cài hook ----
void VSToolboxInstallHooks(void);
