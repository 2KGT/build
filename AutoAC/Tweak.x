#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// BuildInfo.h do build_engine.py tạo tự động (chứa version của lần build này).
// Không có file này thì tweak vẫn build bình thường, chỉ không hiện số version.
#if __has_include("BuildInfo.h")
#import "BuildInfo.h"
#endif
#ifndef TWEAK_BUILD_VERSION
#define TWEAK_BUILD_VERSION @""
#endif

#define kPrefs [NSUserDefaults standardUserDefaults]
static NSString *const kAutoClearCacheKey = @"kAutoClearCache";

#pragma mark - Interfaces (khai báo tối thiểu, không phụ thuộc YouTubeHeader)

@interface YTCommerceEventGroupHandler : NSObject
@end

#pragma mark - Tiện ích

// Lấy cửa sổ đang hiển thị, không dùng keyWindow (đã deprecated từ iOS 13)
static UIWindow *AutoACKeyWindow(void) {
    UIWindow *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) return w;
            if (!fallback) fallback = w;
        }
    }
    return fallback;
}

// "v1.1.1" hoặc "" nếu build không có thông tin version
static NSString *AutoACVersionTag(void) {
    NSString *v = TWEAK_BUILD_VERSION;
    return v.length > 0 ? [@"v" stringByAppendingString:v] : @"";
}

#pragma mark - Dọn cache

// Tổng dung lượng thật trên đĩa của một thư mục (byte)
static unsigned long long AutoACDirectorySize(NSString *path) {
    if (path.length == 0) return 0;
    NSArray *keys = @[NSURLIsRegularFileKey, NSURLTotalFileAllocatedSizeKey, NSURLFileAllocatedSizeKey];
    NSDirectoryEnumerator *enumerator =
        [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:path]
                           includingPropertiesForKeys:keys
                                              options:0
                                         errorHandler:^BOOL(NSURL *url, NSError *error) { return YES; }];
    unsigned long long total = 0;
    for (NSURL *url in enumerator) {
        NSNumber *isFile = nil;
        [url getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil];
        if (!isFile.boolValue) continue;

        NSNumber *size = nil;
        [url getResourceValue:&size forKey:NSURLTotalFileAllocatedSizeKey error:nil];
        if (!size) [url getResourceValue:&size forKey:NSURLFileAllocatedSizeKey error:nil];
        total += size.unsignedLongLongValue;
    }
    return total;
}

// Xoá nội dung bên trong thư mục (giữ lại chính thư mục đó)
static void AutoACRemoveContents(NSString *dir) {
    if (dir.length == 0) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
    }
}

// Dọn Library/Caches và tmp của app. Không đụng Documents, Preferences, tải xuống.
// Trả về số byte đã giải phóng.
static unsigned long long AutoACClearCache(void) {
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSArray<NSString *> *dirs = @[caches ?: @"", NSTemporaryDirectory() ?: @""];

    unsigned long long before = 0, after = 0;
    for (NSString *d in dirs) before += AutoACDirectorySize(d);
    for (NSString *d in dirs) AutoACRemoveContents(d);
    for (NSString *d in dirs) after += AutoACDirectorySize(d);

    return before > after ? before - after : 0;
}

#pragma mark - Hub kết quả (viên thuốc 1 dòng)

static __weak UIView *gHub = nil;

static void AutoACShowHub(NSString *symbol, UIColor *tint, NSString *text,
                          NSString *suffix, NSTimeInterval duration) {
    UIWindow *window = AutoACKeyWindow();
    if (!window) return;

    [gHub removeFromSuperview];

    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.userInteractionEnabled = NO;
    container.layer.shadowColor = UIColor.blackColor.CGColor;
    container.layer.shadowOpacity = 0.14;
    container.layer.shadowRadius = 8;
    container.layer.shadowOffset = CGSizeMake(0, 3);

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.layer.cornerRadius = 14;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    [container addSubview:blur];

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:symbol withConfiguration:cfg]];
    icon.tintColor = tint;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [icon setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc]
        initWithString:text
            attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold],
                         NSForegroundColorAttributeName: UIColor.labelColor}];
    if (suffix.length > 0) {
        [attributed appendAttributedString:[[NSAttributedString alloc]
            initWithString:[@"  ·  " stringByAppendingString:suffix]
                attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightRegular],
                             NSForegroundColorAttributeName: UIColor.secondaryLabelColor}]];
    }
    UILabel *label = [[UILabel alloc] init];
    label.attributedText = attributed;
    label.numberOfLines = 1;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 6;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [blur.contentView addSubview:row];

    [window addSubview:container];
    gHub = container;

    [NSLayoutConstraint activateConstraints:@[
        [blur.topAnchor constraintEqualToAnchor:container.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [row.topAnchor constraintEqualToAnchor:blur.contentView.topAnchor constant:7],
        [row.bottomAnchor constraintEqualToAnchor:blur.contentView.bottomAnchor constant:-7],
        [row.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor constant:11],
        [row.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor constant:-13],

        [container.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:4],
        [container.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:window.leadingAnchor constant:16],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:window.trailingAnchor constant:-16],
    ]];
    [window layoutIfNeeded];

    container.alpha = 0;
    container.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.9, 0.9),
                                                  CGAffineTransformMakeTranslation(0, -10));
    [UIView animateWithDuration:0.35
                          delay:0
         usingSpringWithDamping:0.85
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        container.alpha = 1;
        container.transform = CGAffineTransformIdentity;
    } completion:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.22
                         animations:^{
            container.alpha = 0;
            container.transform = CGAffineTransformMakeTranslation(0, -8);
        } completion:^(BOOL finished) {
            [container removeFromSuperview];
        }];
    });
}

// Hub báo kết quả dọn cache kèm dung lượng đã giải phóng
static void AutoACShowCacheHub(unsigned long long bytes) {
    NSString *tag = AutoACVersionTag();
    if (bytes > 0) {
        NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
        formatter.countStyle = NSByteCountFormatterCountStyleFile;
        formatter.allowsNonnumericFormatting = NO;
        NSString *text = [NSString stringWithFormat:@"Đã dọn %@",
                          [formatter stringFromByteCount:(long long)bytes]];
        AutoACShowHub(@"sparkles", UIColor.systemYellowColor, text, tag, 2.2);
    } else {
        AutoACShowHub(@"checkmark.circle.fill", UIColor.systemGreenColor,
                      @"Cache đã sạch", tag, 2.2);
    }
}

static BOOL gCleaning = NO;

// Dọn ở luồng nền, xong hiện hub trên luồng chính
static void AutoACRunCleanup(void) {
    if (gCleaning) return;
    gCleaning = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        unsigned long long freed = AutoACClearCache();
        dispatch_async(dispatch_get_main_queue(), ^{
            gCleaning = NO;
            AutoACShowCacheHub(freed);
        });
    });
}

#pragma mark - Menu mini (kiểu popover chọn mô hình)

static __weak UIView *gMenu = nil;

static void AutoACDismissMenu(void) {
    UIView *backdrop = gMenu;
    if (!backdrop) return;
    gMenu = nil;
    [UIView animateWithDuration:0.16 animations:^{
        backdrop.alpha = 0;
    } completion:^(BOOL finished) {
        [backdrop removeFromSuperview];
    }];
}

// Một hàng: biểu tượng + tiêu đề + dòng phụ (không nhận chạm, để nút bên dưới nhận)
static UIStackView *AutoACRowStack(NSString *symbol, UIColor *tint, NSString *title, NSString *sub) {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium];
    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:symbol withConfiguration:cfg]];
    icon.tintColor = tint;
    icon.contentMode = UIViewContentModeCenter;
    [icon.widthAnchor constraintEqualToConstant:22].active = YES;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;

    UILabel *subLabel = [[UILabel alloc] init];
    subLabel.text = sub;
    subLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    subLabel.textColor = UIColor.secondaryLabelColor;

    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subLabel]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 0;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 9;
    row.userInteractionEnabled = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    return row;
}

// Nền xám nhạt khi đang chạm vào hàng
static void AutoACAddHighlight(UIButton *button) {
    __weak UIButton *weakButton = button;
    UIColor *highlight = [UIColor.labelColor colorWithAlphaComponent:0.08];
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        weakButton.backgroundColor = highlight;
    }] forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        weakButton.backgroundColor = UIColor.clearColor;
    }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                        UIControlEventTouchCancel | UIControlEventTouchDragExit];
}

static void AutoACShowMenu(CGPoint anchor) {
    UIWindow *window = AutoACKeyWindow();
    if (!window || gMenu) return;

    const CGFloat cardWidth = 200;
    const CGFloat rowHeight = 44;
    CGFloat leadingConstant = MIN(MAX(anchor.x - 24, 12), CGRectGetWidth(window.bounds) - cardWidth - 12);
    CGFloat topConstant = anchor.y + 24;

    // Nền trong suốt: chạm ra ngoài để đóng
    UIButton *backdrop = [UIButton buttonWithType:UIButtonTypeCustom];
    backdrop.frame = window.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backdrop.backgroundColor = UIColor.clearColor;
    [backdrop addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        AutoACDismissMenu();
    }] forControlEvents:UIControlEventTouchUpInside];

    // Thẻ nhỏ: kính mờ + bóng nhẹ
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.18;
    card.layer.shadowRadius = 14;
    card.layer.shadowOffset = CGSizeMake(0, 5);

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.layer.cornerRadius = 16;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    [card addSubview:blur];

    NSMutableArray<UIView *> *arranged = [NSMutableArray array];
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];

    // Dòng chú thích nhỏ: tên + version build (để biết đang chạy bản nào)
    NSString *tag = AutoACVersionTag();
    if (tag.length > 0) {
        UIView *captionWrap = [[UIView alloc] init];
        captionWrap.translatesAutoresizingMaskIntoConstraints = NO;
        UILabel *caption = [[UILabel alloc] init];
        caption.translatesAutoresizingMaskIntoConstraints = NO;
        caption.text = [NSString stringWithFormat:@"AutoAC  ·  %@", tag];
        caption.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
        caption.textColor = UIColor.tertiaryLabelColor;
        [captionWrap addSubview:caption];
        [constraints addObjectsFromArray:@[
            [captionWrap.heightAnchor constraintEqualToConstant:24],
            [caption.leadingAnchor constraintEqualToAnchor:captionWrap.leadingAnchor constant:14],
            [caption.bottomAnchor constraintEqualToAnchor:captionWrap.bottomAnchor constant:-2],
        ]];
        [arranged addObject:captionWrap];
    }

    // Hàng 1: công tắc tự động dọn khi mở app
    UIView *autoRow = [[UIView alloc] init];
    autoRow.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *autoButton = [UIButton buttonWithType:UIButtonTypeCustom];
    autoButton.translatesAutoresizingMaskIntoConstraints = NO;
    AutoACAddHighlight(autoButton);

    UIStackView *autoStack = AutoACRowStack(@"arrow.triangle.2.circlepath", UIColor.systemGreenColor,
                                            @"Tự động dọn", @"Khi mở app");

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.onTintColor = UIColor.systemGreenColor;
    toggle.on = [kPrefs boolForKey:kAutoClearCacheKey];
    toggle.transform = CGAffineTransformMakeScale(0.75, 0.75);
    __weak UISwitch *weakToggle = toggle;
    [toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        [kPrefs setBool:weakToggle.isOn forKey:kAutoClearCacheKey];
        [[UISelectionFeedbackGenerator new] selectionChanged];
    }] forControlEvents:UIControlEventValueChanged];

    // Chạm vào cả hàng cũng bật/tắt công tắc
    [autoButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        UISwitch *strongToggle = weakToggle;
        if (!strongToggle) return;
        [strongToggle setOn:!strongToggle.isOn animated:YES];
        [kPrefs setBool:strongToggle.isOn forKey:kAutoClearCacheKey];
        [[UISelectionFeedbackGenerator new] selectionChanged];
    }] forControlEvents:UIControlEventTouchUpInside];

    [autoRow addSubview:autoButton];
    [autoRow addSubview:autoStack];
    [autoRow addSubview:toggle];
    [arranged addObject:autoRow];

    // Đường kẻ mảnh giữa hai hàng
    UIView *separatorWrap = [[UIView alloc] init];
    separatorWrap.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *separator = [[UIView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = UIColor.separatorColor;
    [separatorWrap addSubview:separator];
    [arranged addObject:separatorWrap];

    // Hàng 2: dọn cache thủ công
    UIButton *cleanButton = [UIButton buttonWithType:UIButtonTypeCustom];
    cleanButton.translatesAutoresizingMaskIntoConstraints = NO;
    AutoACAddHighlight(cleanButton);
    UIStackView *cleanStack = AutoACRowStack(@"trash", UIColor.systemBlueColor,
                                             @"Dọn ngay", @"Xoá cache thủ công");
    [cleanButton addSubview:cleanStack];
    [cleanButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        AutoACDismissMenu();
        AutoACRunCleanup();
    }] forControlEvents:UIControlEventTouchUpInside];
    [arranged addObject:cleanButton];

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:arranged];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 0;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [blur.contentView addSubview:column];

    [backdrop addSubview:card];
    [window addSubview:backdrop];
    gMenu = backdrop;

    [constraints addObjectsFromArray:@[
        // Thẻ
        [card.widthAnchor constraintEqualToConstant:cardWidth],
        [card.leadingAnchor constraintEqualToAnchor:backdrop.leadingAnchor constant:leadingConstant],
        [card.topAnchor constraintEqualToAnchor:backdrop.topAnchor constant:topConstant],
        [blur.topAnchor constraintEqualToAnchor:card.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],

        // Danh sách
        [column.topAnchor constraintEqualToAnchor:blur.contentView.topAnchor constant:4],
        [column.bottomAnchor constraintEqualToAnchor:blur.contentView.bottomAnchor constant:-4],
        [column.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor],
        [column.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor],

        // Hàng tự động
        [autoRow.heightAnchor constraintEqualToConstant:rowHeight],
        [autoButton.topAnchor constraintEqualToAnchor:autoRow.topAnchor],
        [autoButton.bottomAnchor constraintEqualToAnchor:autoRow.bottomAnchor],
        [autoButton.leadingAnchor constraintEqualToAnchor:autoRow.leadingAnchor],
        [autoButton.trailingAnchor constraintEqualToAnchor:autoRow.trailingAnchor],
        [autoStack.leadingAnchor constraintEqualToAnchor:autoRow.leadingAnchor constant:14],
        [autoStack.centerYAnchor constraintEqualToAnchor:autoRow.centerYAnchor],
        [autoStack.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-4],
        [toggle.trailingAnchor constraintEqualToAnchor:autoRow.trailingAnchor constant:-8],
        [toggle.centerYAnchor constraintEqualToAnchor:autoRow.centerYAnchor],

        // Đường kẻ
        [separatorWrap.heightAnchor constraintEqualToConstant:0.5],
        [separator.topAnchor constraintEqualToAnchor:separatorWrap.topAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:separatorWrap.bottomAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:separatorWrap.leadingAnchor constant:14],
        [separator.trailingAnchor constraintEqualToAnchor:separatorWrap.trailingAnchor],

        // Hàng dọn ngay
        [cleanButton.heightAnchor constraintEqualToConstant:rowHeight],
        [cleanStack.leadingAnchor constraintEqualToAnchor:cleanButton.leadingAnchor constant:14],
        [cleanStack.trailingAnchor constraintLessThanOrEqualToAnchor:cleanButton.trailingAnchor constant:-14],
        [cleanStack.centerYAnchor constraintEqualToAnchor:cleanButton.centerYAnchor],
    ]];
    [NSLayoutConstraint activateConstraints:constraints];
    [window layoutIfNeeded];

    // Mở ra như popover: phóng nhẹ từ góc trên-trái
    backdrop.alpha = 0;
    card.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.9, 0.9),
                                             CGAffineTransformMakeTranslation(-8, -6));
    [UIView animateWithDuration:0.3
                          delay:0
         usingSpringWithDamping:0.85
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        backdrop.alpha = 1;
        card.transform = CGAffineTransformIdentity;
    } completion:nil];

    [[UIImpactFeedbackGenerator new] impactOccurred];
}

#pragma mark - Nhận diện nhấn giữ logo

static BOOL AutoACViewIsLogo(UIView *v) {
    NSString *cls = NSStringFromClass(v.class);
    if ([cls rangeOfString:@"Logo" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    NSString *label = v.accessibilityLabel;
    return [label isEqualToString:@"YouTube"] || [label isEqualToString:@"YouTube Premium"];
}

// Điểm chạm có nằm trên logo không?
// 1) Lần theo chuỗi view tại điểm chạm, tìm view tên "Logo" hoặc nhãn "YouTube".
// 2) Không nhận ra thì coi vùng góc trên-trái (ngay dưới tai thỏ) là logo.
static BOOL AutoACPointIsOnLogo(UIWindow *window, CGPoint point) {
    UIView *hit = [window hitTest:point withEvent:nil];
    for (UIView *v = hit; v && v != window; v = v.superview) {
        if (AutoACViewIsLogo(v)) return YES;
    }
    CGFloat top = MAX(window.safeAreaInsets.top, 20);
    return point.y >= top - 8 &&
           point.y <= top + 64 &&
           point.x <= CGRectGetWidth(window.bounds) * 0.5;
}

#pragma mark - Cơ chế 1: cử chỉ nhấn giữ trên cửa sổ

@interface AutoACGestureHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@implementation AutoACGestureHandler

+ (instancetype)shared {
    static AutoACGestureHandler *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AutoACGestureHandler alloc] init]; });
    return instance;
}

// Chỉ "nhận" cử chỉ khi nhấn giữ đúng vùng logo.
// Nhấn giữ chỗ khác thì cử chỉ tự thất bại, không phá các tính năng nhấn giữ của YouTube.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    UIWindow *window = (UIWindow *)gestureRecognizer.view;
    if (![window isKindOfClass:UIWindow.class]) return NO;
    return AutoACPointIsOnLogo(window, [gestureRecognizer locationInView:window]);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIWindow *window = (UIWindow *)gesture.view;
    if (![window isKindOfClass:UIWindow.class]) return;
    AutoACShowMenu([gesture locationInView:window]);
}

@end

static const char kAutoACAttachedKey = 0;

static void AutoACAttachToWindow(UIWindow *window) {
    if (!window || objc_getAssociatedObject(window, &kAutoACAttachedKey)) return;

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[AutoACGestureHandler shared]
                action:@selector(handleLongPress:)];
    lp.delegate = [AutoACGestureHandler shared];
    lp.minimumPressDuration = 0.45;
    lp.allowableMovement = 12;
    lp.cancelsTouchesInView = YES;   // nhấn giữ xong thì nút logo không bị kích hoạt khi nhả tay
    lp.delaysTouchesBegan = NO;
    lp.delaysTouchesEnded = NO;
    [window addGestureRecognizer:lp];

    objc_setAssociatedObject(window, &kAutoACAttachedKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Cơ chế 2 (dự phòng): đếm giờ ngay trong sendEvent

static __weak UIWindow *gPressWindow = nil;
static CGPoint gPressStart;
static NSUInteger gPressToken = 0;

static void AutoACCancelPress(void) {
    gPressToken++;
    gPressWindow = nil;
}

%hook UIWindow

- (void)becomeKeyWindow {
    %orig;
    AutoACAttachToWindow(self);
}

- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (event.type != UIEventTypeTouches) return;

    NSSet<UITouch *> *touches = [event touchesForWindow:self];
    if (touches.count != 1) {
        if (gPressWindow == self) AutoACCancelPress();
        return;
    }

    UITouch *touch = touches.anyObject;
    CGPoint point = [touch locationInView:self];

    switch (touch.phase) {
        case UITouchPhaseBegan: {
            AutoACCancelPress();
            if (gMenu || !AutoACPointIsOnLogo(self, point)) break;

            gPressWindow = self;
            gPressStart = point;
            NSUInteger token = gPressToken;
            CGPoint start = point;
            __weak UIWindow *weakSelf = self;
            // 0.7s: sau cơ chế 1 (0.45s). Nếu menu đã mở thì bỏ qua.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                UIWindow *w = weakSelf;
                if (!w || token != gPressToken || gPressWindow != w || gMenu) return;
                AutoACCancelPress();
                AutoACShowMenu(start);
            });
            break;
        }
        case UITouchPhaseMoved:
            if (gPressWindow == self &&
                hypot(point.x - gPressStart.x, point.y - gPressStart.y) > 12) {
                AutoACCancelPress();
            }
            break;
        case UITouchPhaseEnded:
        case UITouchPhaseCancelled:
            if (gPressWindow == self) AutoACCancelPress();
            break;
        default:
            break;
    }
}

%end

#pragma mark - Fix Promo

%hook YTCommerceEventGroupHandler
- (void)addEventHandlers {}
%end

#pragma mark - Tự động dọn khi mở app

static BOOL gDidAutoClean = NO;

// Chỉ chạy một lần cho mỗi lần mở app, chờ 2 giây cho giao diện sẵn sàng
static void AutoACAutoCleanOnce(void) {
    if (gDidAutoClean) return;
    gDidAutoClean = YES;
    if (![kPrefs boolForKey:kAutoClearCacheKey]) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AutoACRunCleanup();
    });
}

%ctor {
    // Mặc định BẬT tự dọn cache
    [kPrefs registerDefaults:@{kAutoClearCacheKey: @YES}];

    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) {
        AutoACAttachToWindow(AutoACKeyWindow());
        AutoACAutoCleanOnce();
    }];

    // Phòng khi app đã active trước lúc dylib nạp xong
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AutoACAttachToWindow(AutoACKeyWindow());
        AutoACAutoCleanOnce();
    });
}
