//
//  VSUI.mm
//  Nút nổi + panel hồng + banner tiến trình + toast.
//

#import "VSToolbox.h"
#import <math.h>

static const NSInteger kVSVSToolboxWindowTag = 0x56535442;

static NSString *VSRelativeTimeLabel(NSDate *date) {
    NSTimeInterval dt = -[date timeIntervalSinceNow];
    if (dt < 60) return @"vừa xong";
    if (dt < 3600) return [NSString stringWithFormat:@"%d phút trước", (int)(dt / 60)];
    if (dt < 86400) return [NSString stringWithFormat:@"%d giờ trước", (int)(dt / 3600)];
    return [NSString stringWithFormat:@"%d ngày trước", (int)(dt / 86400)];
}

// =====================================================================
// MARK: - View phụ trợ
// =====================================================================

@interface VSPassthroughView : UIView
@end

@implementation VSPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    return (v == self) ? nil : v;
}
@end

@interface VSFloatingWindow : UIWindow
@end

@implementation VSFloatingWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self) return nil;
    if (v == self.rootViewController.view) return nil;
    return v;
}
@end

@interface VSRootVC : UIViewController
@end

@implementation VSRootVC

- (void)loadView {
    VSPassthroughView *v = [[VSPassthroughView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    v.backgroundColor = [UIColor clearColor];
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = v;
}

- (UIViewController *)currentAppVC {
    UIWindow *w = nil;
    for (UIWindow *win in [UIApplication sharedApplication].windows) {
        if (win.tag != 0x56535442 && !win.hidden && win.rootViewController) {
            w = win;
            break;
        }
    }
    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) {
        vc = vc.presentedViewController;
    }
    return vc;
}

- (BOOL)shouldAutorotate {
    UIViewController *vc = [self currentAppVC];
    return vc ? [vc shouldAutorotate] : YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIViewController *vc = [self currentAppVC];
    return vc ? [vc supportedInterfaceOrientations] : UIInterfaceOrientationMaskAll;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    UIViewController *vc = [self currentAppVC];
    return vc ? [vc preferredInterfaceOrientationForPresentation] : UIInterfaceOrientationPortrait;
}

- (BOOL)prefersStatusBarHidden {
    UIViewController *vc = [self currentAppVC];
    return vc ? [vc prefersStatusBarHidden] : NO;
}

@end

// =====================================================================
// MARK: - Panel
// =====================================================================

@interface VSPanelView : UIView
- (void)reload;
- (void)resetToMenu;
- (void)animateIn;
- (void)animateOut:(void (^)(void))completion;
- (void)clearStack;
- (void)buildMenu;
- (void)buildLayerPicker;
- (void)openLayerPicker;
- (void)autoImportAll;
- (void)updateStartButton;
- (void)beginPickedSession;
- (void)closeTapped;
- (void)backgroundTapped:(UITapGestureRecognizer *)g;
- (UILabel *)sectionLabel:(NSString *)text;
- (UILabel *)hintLabel:(NSString *)text;
- (UIButton *)row:(NSString *)title
         subtitle:(NSString *)subtitle
             icon:(NSString *)icon
            color:(UIColor *)color
           action:(void (^)(void))action;
- (UIButton *)primaryRow:(NSString *)title icon:(NSString *)icon action:(void (^)(void))action;
- (UIView *)switchRow:(NSString *)title isOn:(BOOL)on action:(void (^)(BOOL))action;
- (UIView *)latestCodeCard:(VSCodeEntry *)entry;
- (UIView *)clipboardRow;
- (void)showQRForCode:(NSString *)code;
- (void)addProDiagSection;
@end

@implementation VSPanelView {
    UIView *_card;
    UILabel *_titleLabel;
    UIButton *_closeButton;
    UIScrollView *_scroll;
    UIStackView *_stack;
    NSUInteger _mode;                     // 0 = menu, 1 = chọn lớp ảnh, 2 = chọn lớp video
    NSMutableSet<NSNumber *> *_picked;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.38];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _card = [[UIView alloc] init];
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    _card.backgroundColor = VSBG();
    _card.layer.cornerRadius = 26;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.layer.masksToBounds = YES;
    _card.layer.borderWidth = 2;
    _card.layer.borderColor = [VSPink() colorWithAlphaComponent:0.35].CGColor;
    [self addSubview:_card];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.text = @"VSToolbox 🌸";
    _titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    _titleLabel.textColor = VSPinkDeep();
    [_card addSubview:_titleLabel];

    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    _closeButton.tintColor = [VSPinkDeep() colorWithAlphaComponent:0.65];
    [_closeButton addTarget:self action:@selector(closeTapped)
           forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_closeButton];

    _scroll = [[UIScrollView alloc] init];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.showsVerticalScrollIndicator = YES;
    _scroll.alwaysBounceVertical = YES;
    [_card addSubview:_scroll];

    _stack = [[UIStackView alloc] init];
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 10;
    _stack.alignment = UIStackViewAlignmentFill;
    [_scroll addSubview:_stack];

    [NSLayoutConstraint activateConstraints:@[
        [_card.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [_card.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [_card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_card.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.74],

        [_titleLabel.topAnchor constraintEqualToAnchor:_card.topAnchor constant:18],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:20],

        [_closeButton.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_closeButton.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-16],
        [_closeButton.widthAnchor constraintEqualToConstant:34],
        [_closeButton.heightAnchor constraintEqualToConstant:34],

        [_scroll.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:10],
        [_scroll.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:14],
        [_scroll.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14],
        [_scroll.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-14],

        [_stack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor],
        [_stack.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor],
        [_stack.widthAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.widthAnchor],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(backgroundTapped:)];
    tap.cancelsTouchesInView = NO;
    [self addGestureRecognizer:tap];

    return self;
}

- (void)resetToMenu {
    _mode = 0;
    _picked = nil;
    [self reload];
}

- (void)closeTapped {
    [[VSUI sharedUI] hidePanel];
}

- (void)backgroundTapped:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:self];
    if (!CGRectContainsPoint(_card.frame, p)) [[VSUI sharedUI] hidePanel];
}

- (void)animateIn {
    self.alpha = 0.0;
    _card.transform = CGAffineTransformMakeScale(0.94, 0.94);
    [UIView animateWithDuration:0.22 animations:^{
        self.alpha = 1.0;
        self->_card.transform = CGAffineTransformIdentity;
    }];
}

- (void)animateOut:(void (^)(void))completion {
    [UIView animateWithDuration:0.16 animations:^{
        self.alpha = 0.0;
        self->_card.transform = CGAffineTransformMakeScale(0.96, 0.96);
    } completion:^(BOOL finished) {
        self.alpha = 1.0;
        self->_card.transform = CGAffineTransformIdentity;
        if (completion) completion();
    }];
}

// ---------- dựng nội dung ----------

- (void)clearStack {
    for (UIView *v in [_stack.arrangedSubviews copy]) {
        [_stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
}

- (void)reload {
    [self clearStack];
    if (_mode == 0) [self buildMenu];
    else            [self buildLayerPicker];
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    NSMutableAttributedString *s =
        [[NSMutableAttributedString alloc] initWithString:[text uppercaseString]
                                               attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold],
            NSForegroundColorAttributeName: [VSPinkDeep() colorWithAlphaComponent:0.8],
            NSKernAttributeName: @(0.8),
        }];
    l.attributedText = s;
    return l;
}

- (UILabel *)hintLabel:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.numberOfLines = 0;
    l.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
    l.textColor = [VSText() colorWithAlphaComponent:0.62];
    return l;
}

- (UIButton *)row:(NSString *)title
         subtitle:(NSString *)subtitle
             icon:(NSString *)icon
            color:(UIColor *)color
           action:(void (^)(void))action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *cfg = [UIButtonConfiguration filledButtonConfiguration];
    cfg.title = title;
    if (subtitle.length) cfg.subtitle = subtitle;
    if (icon.length) cfg.image = [UIImage systemImageNamed:icon];
    cfg.imagePadding = 10;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(11, 14, 11, 14);
    cfg.baseForegroundColor = color ?: VSPinkDeep();
    cfg.baseBackgroundColor = [UIColor whiteColor];
    cfg.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    cfg.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;

    UIColor *titleColor = color ?: VSPinkDeep();
    cfg.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary *out = [incoming mutableCopy] ?: [NSMutableDictionary dictionary];
        out[NSFontAttributeName] = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        out[NSForegroundColorAttributeName] = titleColor;
        return out;
    };
    cfg.subtitleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
        NSMutableDictionary *out = [incoming mutableCopy] ?: [NSMutableDictionary dictionary];
        out[NSFontAttributeName] = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
        out[NSForegroundColorAttributeName] = [VSText() colorWithAlphaComponent:0.55];
        return out;
    };

    b.configuration = cfg;
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    if (action) {
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) { action(); }]
          forControlEvents:UIControlEventTouchUpInside];
    }
    return b;
}

- (UIButton *)primaryRow:(NSString *)title icon:(NSString *)icon action:(void (^)(void))action {
    UIButton *b = [self row:title subtitle:nil icon:icon color:[UIColor whiteColor] action:action];
    UIButtonConfiguration *cfg = b.configuration;
    cfg.baseBackgroundColor = VSPink();
    cfg.baseForegroundColor = [UIColor whiteColor];
    b.configuration = cfg;
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    return b;
}

- (UIView *)switchRow:(NSString *)title isOn:(BOOL)on action:(void (^)(BOOL))action {
    UIView *box = [[UIView alloc] init];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.backgroundColor = [UIColor whiteColor];
    box.layer.cornerRadius = 12;
    [box.heightAnchor constraintEqualToConstant:48].active = YES;

    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = title;
    lbl.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium];
    lbl.textColor = VSText();
    [box addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    sw.onTintColor = VSPink();
    sw.on = on;
    [box addSubview:sw];

    [NSLayoutConstraint activateConstraints:@[
        [lbl.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:14],
        [lbl.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [lbl.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-8],
        [sw.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-10],
        [sw.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
    ]];

    __weak UISwitch *weakSw = sw;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) {
        if (action) action(weakSw.isOn);
    }] forControlEvents:UIControlEventValueChanged];
    return box;
}

// ---------- chẩn đoán Pro (đọc IMP + _dyld — không hook gì) ----------

- (void)addProDiagSection {
    [_stack addArrangedSubview:[self sectionLabel:@"Chẩn đoán Pro 🔍"]];

    NSArray<NSDictionary *> *rows = VSProStatus();
    BOOL allOK = YES;
    NSString *bad = @"";
    for (NSDictionary *row in rows) {
        if ([row[@"missing"] boolValue] || ![row[@"ok"] boolValue]) {
            if (bad.length) bad = [bad stringByAppendingString:@", "];
            bad = [bad stringByAppendingString:row[@"member"]];
            allOK = NO;
        }
    }

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = VSPinkSoft();
    card.layer.cornerRadius = 14;
    card.layer.borderWidth = 1.5;
    card.layer.borderColor = [VSPink() colorWithAlphaComponent:0.4].CGColor;

    UIStackView *v = [[UIStackView alloc] init];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.axis = UILayoutConstraintAxisVertical;
    v.spacing = 2;
    [card addSubview:v];

    // Tổng kết
    UILabel *head = [[UILabel alloc] init];
    head.translatesAutoresizingMaskIntoConstraints = NO;
    head.numberOfLines = 0;
    if (allOK) {
        head.text = @"✅ Pro OK — hook thuộc VSPlusUltra.dylib";
        head.textColor = [UIColor systemGreenColor];
    } else {
        head.text = [@"⚠ Pro hỏng — hook KHÔNG được cài bởi VSPlusUltra:\n"
                      stringByAppendingString:bad];
        head.textColor = VSPinkDeep();
    }
    head.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [v addArrangedSubview:head];

    // Từng hook
    for (NSDictionary *row in rows) {
        BOOL missing = [row[@"missing"] boolValue];
        BOOL ok = [row[@"ok"] boolValue];
        NSString *mark = missing ? @"?" : (ok ? @"✓" : @"✗");
        NSString *detail = missing ? @"(thiếu IMP)" : row[@"owner"];
        UILabel *line = [[UILabel alloc] init];
        line.translatesAutoresizingMaskIntoConstraints = NO;
        line.text = [NSString stringWithFormat:@"%@ %@ — %@", mark,
                     row[@"member"], detail];
        line.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        line.textColor = missing || !ok ? VSPinkDeep() : [VSText() colorWithAlphaComponent:0.8];
        line.numberOfLines = 0;
        [v addArrangedSubview:line];
    }

    // Danh sách dylib đang nạp (bấm mở chi tiết)
    NSInteger totalImages = 0;
    NSArray<NSString *> *dylibs = VSLoadedDylibs(&totalImages);
    UIButton *dylibRow = [UIButton buttonWithType:UIButtonTypeSystem];
    dylibRow.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
    cfg.title = [NSString stringWithFormat:@"%lu dylib app đang nạp (bấm xem danh sách)",
                 (unsigned long)dylibs.count];
    cfg.image = [UIImage systemImageNamed:@"shippingbox.fill"];
    cfg.imagePadding = 6;
    cfg.baseForegroundColor = VSPinkDeep();
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(8, 0, 8, 0);
    dylibRow.configuration = cfg;
    [dylibRow addAction:[UIAction actionWithHandler:^(UIAction *a) {
        NSString *msg = dylibs.count
            ? [dylibs componentsJoinedByString:@"\n"]
            : @"(chỉ có framework hệ thống)";
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:
                [NSString stringWithFormat:@"%lu / %ld ảnh được nạp",
                 (unsigned long)dylibs.count, (long)totalImages]
            message:msg
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction
            actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *vc = [[VSContext sharedContext] topViewController];
        if (vc) [vc presentViewController:alert animated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    [v addArrangedSubview:dylibRow];

    [NSLayoutConstraint activateConstraints:@[
        [v.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
        [v.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [v.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-14],
        [v.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
    ]];

    [_stack addArrangedSubview:card];
}

// ---------- menu chính ----------

- (void)buildMenu {
    VSContext *ctx = [VSContext sharedContext];
    BOOL inEditor = [ctx isInMultiLayerEditor];
    NSArray<VSLayerInfo *> *cands = inEditor ? [ctx candidatesForVideo:NO] : @[];

    [self addProDiagSection];

    [_stack addArrangedSubview:[self hintLabel:
        inEditor
        ? [NSString stringWithFormat:@"Đang ở trình chỉnh lớp • %lu lớp có thể nhập", (unsigned long)cands.count]
        : @"Mở trình chỉnh lớp (Multi Layer) để dùng tính năng nhập ảnh/video."]];

    [_stack addArrangedSubview:[self sectionLabel:@"Tự động nhập ảnh"]];

    __weak typeof(self) weakSelf = self;
    [_stack addArrangedSubview:[self row:@"Ảnh — Tự động nhập tất cả lớp"
                               subtitle:@"Chọn 1 ảnh duy nhất → tự gán vào toàn bộ các lớp ảnh"
                                   icon:@"photo.on.rectangle.angled"
                                  color:nil
                                 action:^{ [weakSelf autoImportAll]; }]];

    [_stack addArrangedSubview:[self row:@"Chọn lớp để nhập ảnh"
                               subtitle:@"Tự chọn lớp cần nhập → gán 1 ảnh vào các lớp đã chọn"
                                   icon:@"checklist"
                                  color:nil
                                 action:^{ [weakSelf openLayerPicker]; }]];

    [_stack addArrangedSubview:[self sectionLabel:@"Code gần đây"]];

    NSArray<VSCodeEntry *> *codes = [[VSCodeStore sharedStore] entries];
    // Không còn hook: tự quét QRCodes.plist của app mỗi lần mở panel code section
    [[VSCodeStore sharedStore] importFromAppPlists];
    codes = [[VSCodeStore sharedStore] entries];
    if (codes.count == 0) {
        [_stack addArrangedSubview:[self hintLabel:
            @"Chưa có code nào. Nhập code trong app xong mở lại panel — toolbox tự đọc từ bộ nhớ app."]];
    } else {
        // Card nổi bật cho code gần nhất
        VSCodeEntry *latest = codes[0];
        [_stack addArrangedSubview:[self latestCodeCard:latest]];

        // Paste từ clipboard
        [_stack addArrangedSubview:[self clipboardRow]];

        // QR row
        NSString *latestCode = latest.code;
        [_stack addArrangedSubview:[self row:@"Tạo QR code"
                                   subtitle:@"Tạo QR từ code gần nhất để quét sang thiết bị khác"
                                       icon:@"qrcode"
                                      color:nil
                                     action:^{ [weakSelf showQRForCode:latestCode]; }]];

        // Lịch sử đầy đủ nếu có nhiều hơn 1
        if (codes.count > 1) {
            [_stack addArrangedSubview:[self sectionLabel:@"Lịch sử code"]];
            for (NSUInteger i = 1; i < codes.count; i++) {
                VSCodeEntry *e = codes[i];
                NSString *code = e.code;
                UIButton *codeRow = [self row:[NSString stringWithFormat:@"Code %lu • %@",
                                               (unsigned long)(i + 1), VSRelativeTimeLabel(e.date)]
                                     subtitle:@"Nhấn để xem QR"
                                         icon:@"qrcode"
                                        color:VSText()
                                       action:^{ [weakSelf showQRForCode:code]; }];
                [_stack addArrangedSubview:codeRow];
            }
        }

        [_stack addArrangedSubview:[self row:@"Xoá lịch sử code"
                                   subtitle:nil
                                       icon:@"trash"
                                      color:[VSPinkDeep() colorWithAlphaComponent:0.65]
                                     action:^{
            [[VSCodeStore sharedStore] removeAll];
            VSToast(@"Đã xoá lịch sử code");
        }]];
    }

    [_stack addArrangedSubview:[self sectionLabel:@"Tuỳ chọn"]];

    NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
    BOOL preferReplace = ([def objectForKey:@"VSToolbox.preferReplace"] != nil)
                       ? [def boolForKey:@"VSToolbox.preferReplace"]
                       : YES;
    [_stack addArrangedSubview:[self switchRow:@"Ưu tiên thay nội dung lớp đang chọn"
                                         isOn:preferReplace
                                       action:^(BOOL on) {
        [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"VSToolbox.preferReplace"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        VSToast(on ? @"Sẽ thay nội dung lớp đang chọn"
                   : @"Sẽ dùng nút thêm ảnh mặc định của app");
    }]];

    UILabel *footer = [self hintLabel:@"VSToolbox 1.0 • chỉ dùng cho mục đích cá nhân 🌸"];
    footer.textAlignment = NSTextAlignmentCenter;
    footer.font = [UIFont systemFontOfSize:11.5];
    footer.alpha = 0.7;
    [_stack addArrangedSubview:footer];
}

// ---------- chọn lớp & nhập ảnh tự động ----------

- (void)openLayerPicker {
    if (![[VSContext sharedContext] isInMultiLayerEditor]) {
        VSToast(@"Hãy mở trình chỉnh lớp (Multi Layer) trước");
        return;
    }
    _mode = 1;
    _picked = nil;
    [self reload];
}

- (void)autoImportAll {
    VSContext *ctx = [VSContext sharedContext];
    if (![ctx isInMultiLayerEditor]) {
        VSToast(@"Hãy mở trình chỉnh lớp (Multi Layer) trước");
        return;
    }
    NSArray<VSLayerInfo *> *cands = [ctx mediaCandidates];
    if (cands.count == 0) {
        VSToast(@"Không tìm thấy lớp ảnh/video phù hợp trong preset này");
        return;
    }
    NSMutableArray<NSNumber *> *targets = [NSMutableArray array];
    for (VSLayerInfo *i in cands) {
        [targets addObject:@(i.number)];
    }

    UIViewController *top = [ctx topViewController];
    if (!top) {
        VSToast(@"Không tìm thấy màn hình hiển thị");
        return;
    }

    [[VSUI sharedUI] hidePanel];

    [[VSImagePicker sharedPicker] pickImageFrom:top completion:^(UIImage *image) {
        [[VSContext sharedContext] applyImage:image toLayers:targets];
    }];
}

- (void)buildLayerPicker {
    VSContext *ctx = [VSContext sharedContext];
    NSArray<VSLayerInfo *> *cands = [ctx mediaCandidates];

    NSMutableSet<NSNumber *> *valid = [NSMutableSet set];
    for (VSLayerInfo *i in cands) [valid addObject:@(i.number)];
    if (!_picked) {
        _picked = [valid mutableCopy];
    } else {
        [_picked intersectSet:valid];
    }

    [_stack addArrangedSubview:[self row:@"Quay lại"
                               subtitle:nil
                                   icon:@"chevron.left"
                                  color:VSPinkDeep()
                                 action:^{
        _mode = 0;
        [self reload];
    }]];

    [_stack addArrangedSubview:[self hintLabel:
        @"Chọn các lớp cần nhập. Bạn chỉ cần chọn 1 ảnh duy nhất, ảnh sẽ tự động được gán vào tất cả các lớp đã bật."]];

    if (cands.count == 0) {
        [_stack addArrangedSubview:[self hintLabel:@"Không có lớp phù hợp trong preset này."]];
        return;
    }

    for (VSLayerInfo *info in cands) {
        NSString *title = [NSString stringWithFormat:@"Lớp %lu • %@ (loại %d)",
                           (unsigned long)info.number, [info typeTitle], info.type];
        NSNumber *num = @(info.number);
        BOOL on = [_picked containsObject:num];
        [_stack addArrangedSubview:[self switchRow:title isOn:on action:^(BOOL isOn) {
            if (isOn) [self->_picked addObject:num];
            else      [self->_picked removeObject:num];
            [self updateStartButton];
        }]];
    }

    UIButton *start = [self primaryRow:@"Bắt đầu" icon:@"play.fill" action:^{
        [self beginPickedSession];
    }];
    start.tag = 0x5354;   // dùng để cập nhật tiêu đề
    [_stack addArrangedSubview:start];

    [self updateStartButton];
}

- (void)updateStartButton {
    for (UIView *v in _stack.arrangedSubviews) {
        if (v.tag != 0x5354 || ![v isKindOfClass:[UIButton class]]) continue;
        UIButton *b = (UIButton *)v;
        NSUInteger n = _picked.count;
        NSString *title = [NSString stringWithFormat:@"Chọn ảnh & gán vào %lu lớp", (unsigned long)n];
        UIButtonConfiguration *cfg = b.configuration;
        cfg.title = title;
        b.configuration = cfg;
    }
}

- (void)beginPickedSession {
    if (_picked.count == 0) {
        VSToast(@"Chưa chọn lớp nào");
        return;
    }
    NSArray<NSNumber *> *sorted = [_picked.allObjects sortedArrayUsingComparator:
        ^NSComparisonResult(id a, id b) {
            return [(NSNumber *)a compare:(NSNumber *)b];
        }];

    VSContext *ctx = [VSContext sharedContext];
    UIViewController *top = [ctx topViewController];
    if (!top) return;

    [[VSUI sharedUI] hidePanel];

    [[VSImagePicker sharedPicker] pickImageFrom:top completion:^(UIImage *image) {
        [[VSContext sharedContext] applyImage:image toLayers:sorted];
    }];
}

// ---------- Card nổi bật code gần nhất (hiển thị QR thay mã chữ) ----------

- (UIView *)latestCodeCard:(VSCodeEntry *)entry {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = VSPinkSoft();
    card.layer.cornerRadius = 14;
    card.layer.borderWidth = 1.5;
    card.layer.borderColor = [VSPink() colorWithAlphaComponent:0.4].CGColor;

    UILabel *badgeLabel = [[UILabel alloc] init];
    badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    badgeLabel.text = @"CODE GẦN NHẤT";
    badgeLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    badgeLabel.textColor = VSPinkDeep();
    [card addSubview:badgeLabel];

    UILabel *infoLabel = [[UILabel alloc] init];
    infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    infoLabel.text = [NSString stringWithFormat:@">%@",
                      VSRelativeTimeLabel(entry.date)];
    infoLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    infoLabel.textColor = [VSText() colorWithAlphaComponent:0.5];
    [card addSubview:infoLabel];

    // Hình QR của code — hiển thị trực tiếp trong panel
    UIImageView *qrView = [[UIImageView alloc] init];
    qrView.translatesAutoresizingMaskIntoConstraints = NO;
    qrView.image = VSMakeQRImage(entry.code);
    qrView.contentMode = UIViewContentModeScaleAspectFit;
    qrView.layer.cornerRadius = 8;
    qrView.layer.masksToBounds = YES;
    [card addSubview:qrView];

    NSString *code = entry.code;

    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    saveBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *saveCfg = [UIButtonConfiguration filledButtonConfiguration];
    saveCfg.title = @"Lưu QR";
    saveCfg.image = [UIImage systemImageNamed:@"square.and.arrow.down.fill"];
    saveCfg.imagePadding = 5;
    saveCfg.baseBackgroundColor = VSPink();
    saveCfg.baseForegroundColor = [UIColor whiteColor];
    saveCfg.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    saveCfg.contentInsets = NSDirectionalEdgeInsetsMake(7, 11, 7, 11);
    saveBtn.configuration = saveCfg;
    [saveBtn addAction:[UIAction actionWithHandler:^(UIAction *a) {
        UIImage *img = VSMakeQRImage(code);
        if (!img) { VSToast(@"Không tạo được QR"); return; }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
        VSToast(@"Đã lưu QR vào Photos ✓");
    }] forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:saveBtn];

    [NSLayoutConstraint activateConstraints:@[
        [badgeLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [badgeLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [infoLabel.centerYAnchor constraintEqualToAnchor:badgeLabel.centerYAnchor],
        [infoLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],

        [qrView.topAnchor constraintEqualToAnchor:badgeLabel.bottomAnchor constant:10],
        [qrView.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [qrView.widthAnchor constraintEqualToConstant:170],
        [qrView.heightAnchor constraintEqualToConstant:170],

        [saveBtn.topAnchor constraintEqualToAnchor:qrView.bottomAnchor constant:10],
        [saveBtn.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [saveBtn.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],
    ]];

    return card;
}

// ---------- Row dán từ clipboard ----------

- (UIView *)clipboardRow {
    NSString *clip = [UIPasteboard generalPasteboard].string ?: @"";
    clip = [clip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL hasCode = clip.length >= 6;

    NSString *subtitle = hasCode
        ? [NSString stringWithFormat:@"%@…", [clip substringToIndex:MIN(clip.length, (NSUInteger)20)]]
        : @"Clipboard trống hoặc không phải code";

    void (^act)(void) = hasCode ? ^{
        NSString *c = [[UIPasteboard generalPasteboard].string
                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (c.length >= 6) {
            [[VSCodeStore sharedStore] addCode:c source:@"Clipboard"];
            VSToast(@"Đã lưu code từ clipboard ✓");
        } else {
            VSToast(@"Không tìm thấy code trong clipboard");
        }
    } : (void (^)(void))nil;

    UIView *btn = [self row:@"Dán code từ clipboard"
                   subtitle:subtitle
                       icon:@"doc.on.clipboard"
                      color:hasCode ? nil : [VSText() colorWithAlphaComponent:0.4]
                     action:act];
    return btn;
}

// ---------- Hiển thị QR ----------

- (void)showQRForCode:(NSString *)code {
    UIImage *img = VSMakeQRImage(code);
    if (!img) {
        VSToast(@"Không thể tạo QR cho code này");
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"QR Code 🔳"
                         message:@"\n\n\n\n\n\n\n\n\n\n"
                  preferredStyle:UIAlertControllerStyleAlert];

    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.frame = CGRectMake(10, 50, 230, 230);
    [alert.view addSubview:iv];

    [alert addAction:[UIAlertAction actionWithTitle:@"Lưu vào Photos"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
        VSToast(@"Đã lưu QR vào Photos");
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIViewController *vc = [[VSContext sharedContext] topViewController];
    if (vc) [vc presentViewController:alert animated:YES completion:nil];
}


@end

// =====================================================================
// MARK: - Banner tiến trình
// =====================================================================

@interface VSBannerView : UIView
@property (nonatomic, copy) void (^onSkip)(void);
@property (nonatomic, copy) void (^onStop)(void);
- (void)setText:(NSString *)text;
@end

@implementation VSBannerView {
    UILabel *_label;
    UIButton *_skip;
    UIButton *_stop;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = [VSPink() colorWithAlphaComponent:0.97];
    self.layer.cornerRadius = 16;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.shadowColor = [VSPinkDeep() colorWithAlphaComponent:0.35].CGColor;
    self.layer.shadowOpacity = 1;
    self.layer.shadowRadius = 8;
    self.layer.shadowOffset = CGSizeMake(0, 3);

    _label = [[UILabel alloc] init];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    _label.textColor = [UIColor whiteColor];
    _label.numberOfLines = 1;
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_label];

    _skip = [UIButton buttonWithType:UIButtonTypeSystem];
    _skip.translatesAutoresizingMaskIntoConstraints = NO;
    [_skip setTitle:@"Bỏ qua" forState:UIControlStateNormal];
    [_skip setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _skip.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _skip.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.22];
    _skip.layer.cornerRadius = 10;
    _skip.contentEdgeInsets = UIEdgeInsetsMake(5, 10, 5, 10);
    [_skip addTarget:self action:@selector(skipTapped) forControlEvents:UIControlEventTouchUpInside];

    _stop = [UIButton buttonWithType:UIButtonTypeSystem];
    _stop.translatesAutoresizingMaskIntoConstraints = NO;
    [_stop setTitle:@"Dừng" forState:UIControlStateNormal];
    [_stop setTitleColor:VSPinkDeep() forState:UIControlStateNormal];
    _stop.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _stop.backgroundColor = [UIColor whiteColor];
    _stop.layer.cornerRadius = 10;
    _stop.contentEdgeInsets = UIEdgeInsetsMake(5, 10, 5, 10);
    [_stop addTarget:self action:@selector(stopTapped) forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:_skip];
    [self addSubview:_stop];

    [NSLayoutConstraint activateConstraints:@[
        [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_label.trailingAnchor constraintLessThanOrEqualToAnchor:_skip.leadingAnchor constant:-8],

        [_skip.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_skip.heightAnchor constraintEqualToConstant:28],

        [_stop.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_stop.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_stop.heightAnchor constraintEqualToConstant:28],
        [_stop.leadingAnchor constraintEqualToAnchor:_skip.trailingAnchor constant:6],
    ]];
    return self;
}

- (void)setText:(NSString *)text {
    _label.text = text;
}

- (void)skipTapped {
    void (^b)(void) = self.onSkip;
    if (b) b();
}

- (void)stopTapped {
    void (^b)(void) = self.onStop;
    if (b) b();
}

@end

// =====================================================================
// MARK: - VSUI
// =====================================================================

@interface VSUI ()
- (void)install;
- (void)buildWindowWithScene:(UIWindowScene *)scene;
- (void)teardownWindow;
- (void)buildFAB;
- (void)placeFABFromDefaults;
- (CGPoint)clampCenter:(CGPoint)c forView:(UIView *)v inBounds:(CGRect)bounds;
- (void)fabTapped;
- (void)fabPanned:(UIPanGestureRecognizer *)g;
- (BOOL)panelVisible;
- (void)showPanel;
- (void)hidePanel;
- (void)refreshPanel;
- (void)showBanner:(NSString *)text onSkip:(void (^)(void))skip onStop:(void (^)(void))stop;
- (void)setBannerText:(NSString *)text;
- (void)hideBanner;
- (void)showToastText:(NSString *)text;
- (void)appDidBecomeActive;
- (UIWindowScene *)activeScene;
@end

@implementation VSUI {
    VSFloatingWindow *_window;
    VSRootVC *_root;
    UIView *_fab;
    VSPanelView *_panel;
    VSBannerView *_banner;
    UIView *_toastView;
    NSUInteger _toastGen;
    NSUInteger _panelGen;
    NSUInteger _installAttempts;
}

+ (instancetype)sharedUI {
    static VSUI *ui = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ui = [[VSUI alloc] init];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) { [ui install]; }];
        [nc addObserverForName:UISceneDidActivateNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) { [ui install]; }];
    });
    return ui;
}

- (void)appDidBecomeActive {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self install];
    });
}

- (UIWindowScene *)activeScene {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        if (s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
    }
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        if (s.activationState == UISceneActivationStateForegroundInactive) return (UIWindowScene *)s;
    }
    return nil;
}

- (void)install {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self install]; });
        return;
    }

    if (_window) {
        _window.hidden = NO;
        return;
    }

    UIWindowScene *scene = [self activeScene];
    if (!scene) {
        if (_installAttempts++ < 40) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self install]; });
        }
        return;
    }

    _installAttempts = 0;
    [self buildWindowWithScene:scene];
    VSLog(@"UI đã cài thành công");
}

- (void)buildWindowWithScene:(UIWindowScene *)scene {
    if (_window) return;
    if (scene) {
        _window = [[VSFloatingWindow alloc] initWithWindowScene:scene];
        _window.frame = scene.coordinateSpace.bounds;
    } else {
        _window = [[VSFloatingWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    _window.tag = kVSVSToolboxWindowTag;
    _window.windowLevel = UIWindowLevelNormal;
    _window.backgroundColor = [UIColor clearColor];
    _window.rootViewController = [[VSRootVC alloc] init];
    _window.hidden = NO;
    _root = (VSRootVC *)_window.rootViewController;

    [self buildFAB];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self placeFABFromDefaults];
    });
}

- (void)teardownWindow {
    _panel = nil;
    _banner = nil;
    _toastView = nil;
    _fab = nil;
    _root = nil;
    _window.hidden = YES;
    _window.rootViewController = nil;
    _window = nil;
}

// ---------- nút nổi ----------

- (void)buildFAB {
    if (_fab || !_root) return;

    CGFloat size = 54;
    _fab = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    _fab.backgroundColor = [UIColor whiteColor];
    _fab.layer.cornerRadius = size / 2.0;
    _fab.layer.cornerCurve = kCACornerCurveContinuous;
    _fab.layer.borderWidth = 2;
    _fab.layer.borderColor = [VSPink() colorWithAlphaComponent:0.55].CGColor;
    _fab.layer.shadowColor = [VSPinkDeep() colorWithAlphaComponent:0.4].CGColor;
    _fab.layer.shadowOpacity = 1;
    _fab.layer.shadowRadius = 9;
    _fab.layer.shadowOffset = CGSizeMake(0, 3);
    _fab.alpha = 0.94;

    UILabel *emoji = [[UILabel alloc] initWithFrame:_fab.bounds];
    emoji.text = @"🌸";
    emoji.font = [UIFont systemFontOfSize:26];
    emoji.textAlignment = NSTextAlignmentCenter;
    emoji.userInteractionEnabled = NO;
    emoji.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_fab addSubview:emoji];

    [_fab addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                      action:@selector(fabTapped)]];
    [_fab addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                      action:@selector(fabPanned:)]];

    [_root.view addSubview:_fab];
    [self placeFABFromDefaults];
}

- (void)placeFABFromDefaults {
    if (!_fab || !_root) return;
    CGRect bounds = _root.view.bounds;
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"VSToolbox.fabCenter"];
    CGPoint center = CGPointMake(bounds.size.width - 44, bounds.size.height * 0.62);
    if (saved.length) {
        CGPoint p = CGPointFromString(saved);
        if (p.x > 10 && p.y > 10) center = p;
    }
    _fab.center = [self clampCenter:center forView:_fab inBounds:bounds];
}

- (CGPoint)clampCenter:(CGPoint)c forView:(UIView *)v inBounds:(CGRect)bounds {
    CGFloat margin = 8;
    CGFloat halfW = v.bounds.size.width / 2.0;
    CGFloat halfH = v.bounds.size.height / 2.0;
    CGFloat minX = margin + halfW;
    CGFloat maxX = MAX(minX, bounds.size.width - margin - halfW);
    CGFloat minY = margin + halfH + 44;
    CGFloat maxY = MAX(minY, bounds.size.height - margin - halfH - 30);
    c.x = MIN(MAX(c.x, minX), maxX);
    c.y = MIN(MAX(c.y, minY), maxY);
    return c;
}

- (void)fabTapped {
    if ([self panelVisible]) [self hidePanel];
    else [self showPanel];
}

- (void)fabPanned:(UIPanGestureRecognizer *)g {
    if (!_root) return;
    CGPoint t = [g translationInView:_root.view];
    [g setTranslation:CGPointZero inView:_root.view];
    if (!_fab) return;

    CGPoint c = CGPointMake(_fab.center.x + t.x, _fab.center.y + t.y);
    _fab.center = [self clampCenter:c forView:_fab inBounds:_root.view.bounds];

    if (g.state == UIGestureRecognizerStateEnded ||
        g.state == UIGestureRecognizerStateCancelled) {
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGPoint(_fab.center)
                                                  forKey:@"VSToolbox.fabCenter"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

// ---------- panel ----------

- (BOOL)panelVisible {
    return _panel != nil && !_panel.hidden;
}

- (void)showPanel {
    if (!_root) { [self install]; return; }
    [[VSCodeStore sharedStore] checkClipboard];

    if (!_panel) {
        _panel = [[VSPanelView alloc] initWithFrame:_root.view.bounds];
        _panel.hidden = YES;
        [_root.view addSubview:_panel];
    }
    _panel.frame = _root.view.bounds;
    [_panel resetToMenu];
    _panel.hidden = NO;
    _panelGen++;
    [_root.view bringSubviewToFront:_panel];
    [_panel animateIn];
    if (_banner) [_root.view bringSubviewToFront:_banner];
}

- (void)hidePanel {
    if (!_panel || _panel.hidden) return;
    __weak typeof(self) weakSelf = self;
    NSUInteger gen = ++_panelGen;
    [_panel animateOut:^{
        VSUI *strongSelf = weakSelf;
        if (!strongSelf || gen != strongSelf->_panelGen) return;
        strongSelf->_panel.hidden = YES;
    }];
}

- (void)refreshPanel {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshPanel]; });
        return;
    }
    if ([self panelVisible]) [_panel reload];
}

// ---------- banner ----------

- (void)showBanner:(NSString *)text onSkip:(void (^)(void))skip onStop:(void (^)(void))stop {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showBanner:text onSkip:skip onStop:stop];
        });
        return;
    }
    if (!_root) {
        [self install];
        return;
    }

    if (!_banner) {
        _banner = [[VSBannerView alloc] initWithFrame:CGRectZero];
        _banner.translatesAutoresizingMaskIntoConstraints = NO;
        [_root.view addSubview:_banner];
        UILayoutGuide *safe = _root.view.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_banner.leadingAnchor constraintEqualToAnchor:_root.view.leadingAnchor constant:12],
            [_banner.trailingAnchor constraintEqualToAnchor:_root.view.trailingAnchor constant:-12],
            [_banner.topAnchor constraintEqualToAnchor:safe.topAnchor constant:4],
            [_banner.heightAnchor constraintEqualToConstant:50],
        ]];
    }
    _banner.onSkip = skip;
    _banner.onStop = stop;
    [_banner setText:text];
    _banner.hidden = NO;
    [_root.view bringSubviewToFront:_banner];
}

- (void)setBannerText:(NSString *)text {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self setBannerText:text]; });
        return;
    }
    [_banner setText:text];
}

- (void)hideBanner {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self hideBanner]; });
        return;
    }
    if (_banner) _banner.hidden = YES;
}

// ---------- toast ----------

- (void)showToastText:(NSString *)text {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showToastText:text]; });
        return;
    }
    if (!_root) {
        VSLog(@"toast: %@", text);
        return;
    }

    NSUInteger gen = ++_toastGen;
    [_toastView removeFromSuperview];
    _toastView = nil;

    UIFont *font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    CGFloat maxWidth = _root.view.bounds.size.width - 72;

    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = [UIColor whiteColor];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;

    CGRect r = [text boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
                                  options:NSStringDrawingUsesLineFragmentOrigin
                               attributes:@{NSFontAttributeName: font}
                                  context:nil];
    CGSize textSize = CGSizeMake(ceil(r.size.width), ceil(r.size.height));

    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0,
                                                          textSize.width + 28,
                                                          textSize.height + 18)];
    box.backgroundColor = [VSPinkDeep() colorWithAlphaComponent:0.95];
    box.layer.cornerRadius = 16;
    box.layer.cornerCurve = kCACornerCurveContinuous;

    label.frame = CGRectMake(14, 9, textSize.width, textSize.height);
    [box addSubview:label];

    CGFloat y = _root.view.bounds.size.height - box.bounds.size.height - 96;
    box.center = CGPointMake(_root.view.bounds.size.width / 2.0, y + box.bounds.size.height / 2.0);
    box.alpha = 0.0;
    [_root.view addSubview:box];
    _toastView = box;

    [UIView animateWithDuration:0.18 animations:^{
        box.alpha = 1.0;
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.9 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (gen != self->_toastGen) return;
        [UIView animateWithDuration:0.25 animations:^{
            self->_toastView.alpha = 0.0;
        } completion:^(BOOL finished) {
            if (gen != self->_toastGen) return;
            [self->_toastView removeFromSuperview];
            self->_toastView = nil;
        }];
    });
}

@end

// =====================================================================
// MARK: - Hàm toast toàn cục
// =====================================================================

void VSToast(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) return;
    [[VSUI sharedUI] showToastText:text];
}
