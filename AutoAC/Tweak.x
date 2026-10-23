#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define kPrefs [NSUserDefaults standardUserDefaults]
static NSString *const kAutoClearCacheKey = @"kAutoClearCache";

#pragma mark - Interfaces (khai báo tối thiểu, không phụ thuộc YouTubeHeader)

// Thanh tiêu đề trên cùng của YouTube (chứa logo, chuông, tìm kiếm...)
@interface YTHeaderView : UIView
- (void)autoAC_handleLogoLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@interface YTCommerceEventGroupHandler : NSObject
@end

#pragma mark - Cửa sổ chính

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

#pragma mark - Hub thông báo

static __weak UIView *gHub = nil;

// Viên thuốc kính mờ trượt xuống từ trên cùng
static void AutoACShowHub(NSString *symbol, UIColor *tint, NSString *titleText,
                          NSString *subText, NSTimeInterval duration) {
    UIWindow *window = AutoACKeyWindow();
    if (!window) return;

    // Có hub cũ đang hiện thì gỡ trước
    [gHub removeFromSuperview];

    // Khung ngoài (đổ bóng) + lớp kính mờ bên trong
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.userInteractionEnabled = NO;
    container.layer.shadowColor = UIColor.blackColor.CGColor;
    container.layer.shadowOpacity = 0.18;
    container.layer.shadowRadius = 14;
    container.layer.shadowOffset = CGSizeMake(0, 6);

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.layer.cornerRadius = 22;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    [container addSubview:blur];

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:symbol withConfiguration:cfg]];
    icon.tintColor = tint;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [icon setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = titleText;
    titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.numberOfLines = 0;

    UILabel *subLabel = [[UILabel alloc] init];
    subLabel.text = subText;
    subLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    subLabel.textColor = UIColor.secondaryLabelColor;
    subLabel.numberOfLines = 0;

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subLabel]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 2;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, textStack]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [blur.contentView addSubview:row];

    [window addSubview:container];
    gHub = container;

    [NSLayoutConstraint activateConstraints:@[
        [blur.topAnchor constraintEqualToAnchor:container.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [row.topAnchor constraintEqualToAnchor:blur.contentView.topAnchor constant:12],
        [row.bottomAnchor constraintEqualToAnchor:blur.contentView.bottomAnchor constant:-12],
        [row.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor constant:18],
        [row.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor constant:-20],

        [container.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:8],
        [container.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:window.leadingAnchor constant:16],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:window.trailingAnchor constant:-16],
    ]];
    [window layoutIfNeeded];

    // Hiện: trượt xuống + phóng nhẹ
    container.alpha = 0;
    container.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.92, 0.92),
                                                  CGAffineTransformMakeTranslation(0, -16));
    [UIView animateWithDuration:0.45
                          delay:0
         usingSpringWithDamping:0.8
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        container.alpha = 1;
        container.transform = CGAffineTransformIdentity;
    } completion:nil];

    UINotificationFeedbackGenerator *haptic = [[UINotificationFeedbackGenerator alloc] init];
    [haptic notificationOccurred:UINotificationFeedbackTypeSuccess];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3
                         animations:^{
            container.alpha = 0;
            container.transform = CGAffineTransformMakeTranslation(0, -12);
        } completion:^(BOOL finished) {
            [container removeFromSuperview];
        }];
    });
}

// Hub báo kết quả dọn cache kèm dung lượng đã giải phóng
static void AutoACShowCacheHub(unsigned long long bytes) {
    if (bytes > 0) {
        NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
        formatter.countStyle = NSByteCountFormatterCountStyleFile;
        formatter.allowsNonnumericFormatting = NO;
        NSString *sub = [NSString stringWithFormat:@"Giải phóng %@",
                         [formatter stringFromByteCount:(long long)bytes]];
        AutoACShowHub(@"sparkles", UIColor.systemYellowColor, @"Đã dọn sạch cache", sub, 2.6);
    } else {
        AutoACShowHub(@"checkmark.circle.fill", UIColor.systemGreenColor,
                      @"Cache đã sạch", @"Không có gì cần dọn", 2.6);
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

#pragma mark - Menu trên logo (công tắc + nút dọn ngay)

static __weak UIView *gMenu = nil;

static void AutoACDismissMenu(void) {
    UIView *backdrop = gMenu;
    if (!backdrop) return;
    gMenu = nil;
    [UIView animateWithDuration:0.2 animations:^{
        backdrop.alpha = 0;
    } completion:^(BOOL finished) {
        [backdrop removeFromSuperview];
    }];
}

static void AutoACShowMenu(void) {
    UIWindow *window = AutoACKeyWindow();
    if (!window || gMenu) return;

    // Nền mờ toàn màn hình: chạm ra ngoài để đóng
    UIButton *backdrop = [UIButton buttonWithType:UIButtonTypeCustom];
    backdrop.frame = window.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
    [backdrop addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        AutoACDismissMenu();
    }] forControlEvents:UIControlEventTouchUpInside];

    // Thẻ menu: kính mờ + bóng
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.22;
    card.layer.shadowRadius = 18;
    card.layer.shadowOffset = CGSizeMake(0, 8);

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.layer.cornerRadius = 22;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    [card addSubview:blur];

    // Hàng 1: tiêu đề
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
    UIImageView *headIcon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"sparkles" withConfiguration:cfg]];
    headIcon.tintColor = UIColor.systemYellowColor;
    UILabel *headLabel = [[UILabel alloc] init];
    headLabel.text = @"AutoAC";
    headLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    headLabel.textColor = UIColor.labelColor;
    UIStackView *headRow = [[UIStackView alloc] initWithArrangedSubviews:@[headIcon, headLabel]];
    headRow.axis = UILayoutConstraintAxisHorizontal;
    headRow.alignment = UIStackViewAlignmentCenter;
    headRow.spacing = 8;

    // Hàng 2: công tắc tự dọn khi mở app
    UILabel *swTitle = [[UILabel alloc] init];
    swTitle.text = @"Xoá cache tự động";
    swTitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    swTitle.textColor = UIColor.labelColor;
    UILabel *swSub = [[UILabel alloc] init];
    swSub.text = @"Tự dọn khi mở app";
    swSub.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    swSub.textColor = UIColor.secondaryLabelColor;
    UIStackView *swText = [[UIStackView alloc] initWithArrangedSubviews:@[swTitle, swSub]];
    swText.axis = UILayoutConstraintAxisVertical;
    swText.spacing = 2;

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.onTintColor = UIColor.systemGreenColor;
    toggle.on = [kPrefs boolForKey:kAutoClearCacheKey];
    __weak UISwitch *weakToggle = toggle;
    [toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        [kPrefs setBool:weakToggle.isOn forKey:kAutoClearCacheKey];
        [[UISelectionFeedbackGenerator new] selectionChanged];
    }] forControlEvents:UIControlEventValueChanged];

    UIStackView *swRow = [[UIStackView alloc] initWithArrangedSubviews:@[swText, toggle]];
    swRow.axis = UILayoutConstraintAxisHorizontal;
    swRow.alignment = UIStackViewAlignmentCenter;
    swRow.spacing = 12;

    // Hàng 3: nút dọn ngay
    UIButton *cleanButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [cleanButton setTitle:@"🧹  Dọn cache ngay" forState:UIControlStateNormal];
    cleanButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    cleanButton.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.14];
    cleanButton.layer.cornerRadius = 12;
    cleanButton.layer.cornerCurve = kCACornerCurveContinuous;
    [cleanButton.heightAnchor constraintEqualToConstant:44].active = YES;
    [cleanButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        AutoACDismissMenu();
        AutoACRunCleanup();
    }] forControlEvents:UIControlEventTouchUpInside];

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[headRow, swRow, cleanButton]];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 16;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [blur.contentView addSubview:column];

    [backdrop addSubview:card];
    [window addSubview:backdrop];
    gMenu = backdrop;

    NSLayoutConstraint *widthConstraint = [card.widthAnchor constraintEqualToConstant:300];
    widthConstraint.priority = UILayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        [blur.topAnchor constraintEqualToAnchor:card.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],

        [column.topAnchor constraintEqualToAnchor:blur.contentView.topAnchor constant:18],
        [column.bottomAnchor constraintEqualToAnchor:blur.contentView.bottomAnchor constant:-18],
        [column.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor constant:18],
        [column.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor constant:-18],

        // Thả ngay dưới logo, góc trái
        [card.topAnchor constraintEqualToAnchor:backdrop.safeAreaLayoutGuide.topAnchor constant:56],
        [card.leadingAnchor constraintEqualToAnchor:backdrop.safeAreaLayoutGuide.leadingAnchor constant:16],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:backdrop.trailingAnchor constant:-16],
        widthConstraint,
    ]];
    [window layoutIfNeeded];

    backdrop.alpha = 0;
    card.transform = CGAffineTransformMakeTranslation(0, -10);
    [UIView animateWithDuration:0.35
                          delay:0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        backdrop.alpha = 1;
        card.transform = CGAffineTransformIdentity;
    } completion:nil];

    [[UIImpactFeedbackGenerator new] impactOccurred];
}

#pragma mark - Tìm logo trong thanh tiêu đề

// Tìm view logo: tên class chứa "Logo" hoặc nhãn trợ năng là "YouTube" / "YouTube Premium"
static UIView *AutoACFindLogoView(UIView *root) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count > 0) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v != root) {
            NSString *cls = NSStringFromClass(v.class);
            NSString *label = v.accessibilityLabel;
            if ([cls rangeOfString:@"Logo" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [label isEqualToString:@"YouTube"] ||
                [label isEqualToString:@"YouTube Premium"]) {
                return v;
            }
        }
        [queue addObjectsFromArray:v.subviews];
    }
    return nil;
}

static BOOL gLogoAttached = NO;

#pragma mark - Hook logo YouTube

%hook YTHeaderView

- (void)layoutSubviews {
    %orig;

    // Mỗi thanh tiêu đề chỉ gắn một lần
    if (!objc_getAssociatedObject(self, @selector(autoAC_handleLogoLongPress:))) {

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(autoAC_handleLogoLongPress:)];

        lp.minimumPressDuration = 0.45;
        lp.cancelsTouchesInView = NO; // Không làm liệt các nút bấm khác

        [self addGestureRecognizer:lp];

        objc_setAssociatedObject(self,
                                 @selector(autoAC_handleLogoLongPress:),
                                 @(YES),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gLogoAttached = YES;
    }
}

%new
- (void)autoAC_handleLogoLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    CGPoint point = [gesture locationInView:self];
    UIView *logo = AutoACFindLogoView(self);

    BOOL hit;
    if (logo) {
        // Trúng logo (nới thêm vùng chạm cho dễ bấm)
        CGRect frame = [self convertRect:logo.bounds fromView:logo];
        hit = CGRectContainsPoint(CGRectInset(frame, -16, -12), point);
    } else {
        // Không nhận ra view logo: coi 40% bên trái thanh tiêu đề là vùng logo
        hit = point.x < CGRectGetWidth(self.bounds) * 0.4;
    }

    if (hit) AutoACShowMenu();
}
%end

#pragma mark - Fix Promo

%hook YTCommerceEventGroupHandler
- (void)addEventHandlers {}
%end

#pragma mark - Chẩn đoán nếu không gắn được vào logo

// Gom tên các class YT* nằm ở dải trên cùng màn hình để biết thanh tiêu đề tên gì
static void AutoACCollectTopClasses(UIView *view, UIWindow *window, CGFloat maxY,
                                    NSMutableOrderedSet<NSString *> *out) {
    if (out.count >= 10 || view.hidden) return;
    CGRect rect = [view convertRect:view.bounds toView:window];
    if (CGRectIsEmpty(rect) || rect.origin.y > maxY || CGRectGetMaxY(rect) < 0) return;

    NSString *name = NSStringFromClass(view.class);
    if ([name hasPrefix:@"YT"]) [out addObject:name];
    for (UIView *sub in view.subviews) AutoACCollectTopClasses(sub, window, maxY, out);
}

static void AutoACReportIfLogoMissing(void) {
    if (gLogoAttached) return;
    UIWindow *window = AutoACKeyWindow();
    if (!window) return;

    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    AutoACCollectTopClasses(window, window, window.safeAreaInsets.top + 70, names);
    NSString *sub = names.count > 0
        ? [names.array componentsJoinedByString:@", "]
        : @"Không đọc được view nào";
    AutoACShowHub(@"questionmark.circle.fill", UIColor.systemOrangeColor,
                  @"Chưa gắn được vào logo", sub, 10);
}

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
        AutoACAutoCleanOnce();
    }];

    // Phòng khi app đã active trước lúc dylib nạp xong
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AutoACAutoCleanOnce();
    });

    // Sau 15 giây vẫn chưa gắn được vào thanh tiêu đề thì báo kèm tên class để sửa
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AutoACReportIfLogoMissing();
    });
}
