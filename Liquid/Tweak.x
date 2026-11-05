// YTLiquidGlass v2 - Tweak.x
// Port cụm "Appearance+ > Enable Liquid Glass" của NeoFreeBird sang YouTube iOS:
//  - Trang Appearance+ (Đổi màu chủ đạo, Chỉnh thanh điều hướng, Thanh tab cổ điển, Nhãn tab...)
//  - Thanh tab kính nổi (capsule) + viên chọn tab + nút Tạo (+) tách thành vòng tròn
//  - Thu gọn thanh tab về 1 vòng tròn khi cuộn xuống, mở lại khi cuộn lên
//  - Ép giao diện iOS 26 cho toàn app (SDK spoof)
//
// File độc lập, KHÔNG cần YouTubeHeader. Nếu project đã import YouTubeHeader,
// xoá khối "Khai báo tối thiểu" để tránh trùng @interface.
// Tên class/selector của YouTube là best-effort, cần đối chiếu bằng FLEX/class-dump.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <substrate.h>

// MARK: - Khai báo tối thiểu (class riêng của YouTube)

@interface YTSettingsCell : UITableViewCell
@end

@interface YTSettingsSectionItem : NSObject
+ (instancetype)itemWithTitle:(NSString *)title
             titleDescription:(NSString *)titleDescription
      accessibilityIdentifier:(NSString *)accessibilityIdentifier
              detailTextBlock:(NSString *(^)(void))detailTextBlock
                  selectBlock:(BOOL (^)(YTSettingsCell *cell, NSUInteger arg1))selectBlock;
@end

@interface YTSettingsViewController : UIViewController
- (void)pushViewController:(UIViewController *)viewController;
- (void)setSectionItems:(NSMutableArray *)items
            forCategory:(NSUInteger)category
                  title:(NSString *)title
                   icon:(id)icon
       titleDescription:(NSString *)titleDescription
           headerHidden:(BOOL)headerHidden;
- (void)setSectionItems:(NSMutableArray *)items
            forCategory:(NSUInteger)category
                  title:(NSString *)title
       titleDescription:(NSString *)titleDescription
           headerHidden:(BOOL)headerHidden;
@end

@interface YTSettingsSectionItemManager : NSObject
- (void)updateYTLGSectionWithEntry:(id)entry;
@end

@interface YTSettingsGroupData : NSObject
@property (nonatomic, assign) NSUInteger type;
@end

@interface YTAppSettingsPresentationData : NSObject
+ (NSArray<NSNumber *> *)settingsCategoryOrder;
@end

@interface YTPivotBarView : UIView
@end

@interface YTPivotBarItemView : UIView
@end

@interface YTPivotBarViewController : UIViewController
- (void)selectItemWithPivotIdentifier:(NSString *)identifier;
@end

@interface YTHeaderView : UIView
@end

// MARK: - Cấu hình / lưu trữ

static const NSUInteger kYTLGCategory = 'ytlg';

static NSString *const kLiquidGlass = @"YTLG_liquid_glass";  // Bật Liquid Glass
static NSString *const kClassic     = @"YTLG_classic_bar";   // Thanh tab cổ điển: màu chủ đạo cho tab đang chọn
static NSString *const kShowLabels  = @"YTLG_tab_labels";    // Nhãn tab
static NSString *const kMinimize    = @"YTLG_minimize";      // Thu gọn khi cuộn
static NSString *const kSplit       = @"YTLG_split_create";  // Tách nút Tạo (+)
static NSString *const kAccentHex   = @"YTLG_accent_hex";    // Màu chủ đạo "#RRGGBB"
static NSString *const kTabOrder    = @"YTLG_tab_order";
static NSString *const kTabHidden   = @"YTLG_tab_hidden";
static NSString *const kStartupTab  = @"YTLG_startup_tab";

static NSString *const kHomeID   = @"FEwhat_to_watch";
static NSString *const kCreateID = @"FEuploads";

static NSString *const kYTLGRelayout = @"YTLGRelayout";

static BOOL gLiquidGlassSDK = NO;  // spoof SDK: đọc 1 lần lúc nạp, cần khởi động lại
static BOOL gGlassOn, gClassic, gShowLabels, gMinimize, gSplit;
static BOOL gCollapsed = NO;
static BOOL gOnShorts = NO;              // đang ở tab Shorts: tạm tắt kính để YouTube tự vẽ
static NSString *gCurrentPivotID = nil;  // tab hiện tại (ghi lại từ selectItemWithPivotIdentifier:)

static BOOL YTLGGlassActive(void) { return gGlassOn && !gOnShorts; }

static NSUserDefaults *YTLGDefaults(void) { return NSUserDefaults.standardUserDefaults; }
static BOOL YTLGBool(NSString *key) { return [YTLGDefaults() boolForKey:key]; }

static void YTLGReloadFlags(void) {
    gGlassOn    = YTLGBool(kLiquidGlass);
    gClassic    = YTLGBool(kClassic);
    gShowLabels = YTLGBool(kShowLabels);
    gMinimize   = YTLGBool(kMinimize);
    gSplit      = YTLGBool(kSplit);
}

static void YTLGPostRelayout(BOOL animated, BOOL rebuild) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:kYTLGRelayout object:nil
            userInfo:@{@"animated": @(animated), @"rebuild": @(rebuild)}];
    });
}

static void YTLGSetBool(NSString *key, BOOL value) {
    [YTLGDefaults() setBool:value forKey:key];
    YTLGReloadFlags();
    if (!gGlassOn) gCollapsed = NO;
    YTLGPostRelayout(NO, YES);
}

// Màu chủ đạo
static UIColor *YTLGColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:NSString.class] || hex.length != 7 || ![hex hasPrefix:@"#"]) return nil;
    unsigned int v = 0;
    [[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&v];
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0 alpha:1.0];
}

static NSString *YTLGHexFromColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(r * 255), (int)lround(g * 255), (int)lround(b * 255)];
}

static UIColor *YTLGAccent(void) {
    return YTLGColorFromHex([YTLGDefaults() stringForKey:kAccentHex]) ?: UIColor.systemBlueColor;
}

// Danh sách tab
static NSArray<NSDictionary *> *YTLGKnownTabs(void) {
    return @[
        @{@"id": kHomeID,            @"title": @"Trang chủ"},
        @{@"id": @"FEshorts",        @"title": @"Shorts"},
        @{@"id": kCreateID,          @"title": @"Tạo (+)"},
        @{@"id": @"FEsubscriptions", @"title": @"Kênh đăng ký"},
        @{@"id": @"FElibrary",       @"title": @"Bạn"},
    ];
}

static NSString *YTLGTabTitle(NSString *identifier) {
    for (NSDictionary *tab in YTLGKnownTabs())
        if ([tab[@"id"] isEqualToString:identifier]) return tab[@"title"];
    return identifier;
}

static NSArray<NSString *> *YTLGOrderedIDs(void) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableArray<NSString *> *known = [NSMutableArray array];
    for (NSDictionary *tab in YTLGKnownTabs()) [known addObject:tab[@"id"]];
    for (id value in [YTLGDefaults() arrayForKey:kTabOrder])
        if ([value isKindOfClass:NSString.class] && [known containsObject:value] && ![result containsObject:value])
            [result addObject:value];
    for (NSString *identifier in known)
        if (![result containsObject:identifier]) [result addObject:identifier];
    return result;
}

static NSSet<NSString *> *YTLGHiddenIDs(void) {
    NSMutableSet *set = [NSMutableSet setWithArray:[YTLGDefaults() arrayForKey:kTabHidden] ?: @[]];
    [set removeObject:kHomeID];
    return set;
}

static NSArray<NSString *> *YTLGVisibleIDs(void) {
    NSSet *hidden = YTLGHiddenIDs();
    NSMutableArray *ids = [NSMutableArray array];
    for (NSString *identifier in YTLGOrderedIDs())
        if (![hidden containsObject:identifier]) [ids addObject:identifier];
    return ids;
}

// MARK: - Lọc / sắp xếp tab từ renderer (protobuf YouTube)

static NSString *YTLGPivotID(id supported) {
    for (NSString *name in @[@"pivotBarItemRenderer", @"pivotBarIconOnlyItemRenderer"]) {
        SEL sel = NSSelectorFromString(name);
        if (![supported respondsToSelector:sel]) continue;
        id renderer = ((id (*)(id, SEL))objc_msgSend)(supported, sel);
        SEL idSel = NSSelectorFromString(@"pivotIdentifier");
        if (renderer && [renderer respondsToSelector:idSel]) {
            NSString *identifier = ((id (*)(id, SEL))objc_msgSend)(renderer, idSel);
            if ([identifier isKindOfClass:NSString.class] && identifier.length) return identifier;
        }
    }
    return nil;
}

static char kPristineItemsKey;

static void YTLGApplyTabLayout(id renderer) {
    SEL itemsSel = NSSelectorFromString(@"itemsArray");
    if (!renderer || ![renderer respondsToSelector:itemsSel]) return;
    NSMutableArray *items = ((id (*)(id, SEL))objc_msgSend)(renderer, itemsSel);
    if (![items isKindOfClass:NSMutableArray.class]) return;

    NSArray *pristine = objc_getAssociatedObject(renderer, &kPristineItemsKey);
    if (!pristine) {
        pristine = [items copy];
        objc_setAssociatedObject(renderer, &kPristineItemsKey, pristine, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSSet<NSString *> *hidden = YTLGHiddenIDs();
    NSArray<NSString *> *order = YTLGOrderedIDs();

    NSMutableArray *kept = [NSMutableArray array];
    for (id item in pristine) {
        NSString *identifier = YTLGPivotID(item);
        if (identifier && [hidden containsObject:identifier]) continue;
        [kept addObject:item];
    }
    if (kept.count < 2) kept = [pristine mutableCopy];

    NSMutableArray *indexed = [NSMutableArray array];
    [kept enumerateObjectsUsingBlock:^(id item, NSUInteger idx, BOOL *stop) {
        NSString *identifier = YTLGPivotID(item);
        NSUInteger rank = identifier ? [order indexOfObject:identifier] : NSNotFound;
        if (rank == NSNotFound) rank = order.count + idx;
        [indexed addObject:@{@"rank": @(rank), @"item": item}];
    }];
    [indexed sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"rank"] compare:b[@"rank"]];
    }];

    [items removeAllObjects];
    for (NSDictionary *entry in indexed) [items addObject:entry[@"item"]];
}

// MARK: - Liquid Glass: tiện ích view

static char kGlassKey, kPillKey, kCircleKey, kObserverKey, kTapKey;
static char kLabelHiddenKey, kOrigTintKey, kOrigTextKey, kIsCreateKey;
static char kRendererKey, kOrigFrameKey, kLastFrameKey, kChromeKey, kOrigBGKey;

static UIVisualEffect *YTLGMakeGlassEffect(UIColor *tint) {
    Class glassClass = NSClassFromString(@"UIGlassEffect"); // iOS 26+
    if (glassClass) {
        @try {
            id effect = ((id (*)(Class, SEL, NSInteger))objc_msgSend)(
                glassClass, NSSelectorFromString(@"effectWithStyle:"), 0 /* regular */);
            if ([effect respondsToSelector:NSSelectorFromString(@"setInteractive:")])
                [effect setValue:@YES forKey:@"interactive"];
            if (tint && [effect respondsToSelector:NSSelectorFromString(@"setTintColor:")])
                [effect setValue:tint forKey:@"tintColor"];
            if ([effect isKindOfClass:UIVisualEffect.class]) return effect;
        } @catch (__unused id e) {}
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]; // iOS < 26
}

static UIVisualEffectView *YTLGGlassView(UIView *bar, const void *key, UIColor *tint) {
    UIVisualEffectView *view = objc_getAssociatedObject(bar, key);
    if (!view) {
        UIVisualEffect *effect = YTLGMakeGlassEffect(tint);
        view = [[UIVisualEffectView alloc] initWithEffect:effect];
        view.userInteractionEnabled = NO;
        if (tint && [effect isKindOfClass:UIBlurEffect.class])
            view.contentView.backgroundColor = [tint colorWithAlphaComponent:0.85];
        objc_setAssociatedObject(bar, key, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return view;
}

static void YTLGRound(UIView *view) {
    SEL setter = NSSelectorFromString(@"setCornerConfiguration:");
    Class cornerClass = NSClassFromString(@"UICornerConfiguration");
    if ([view respondsToSelector:setter] && cornerClass) {
        @try {
            id config = ((id (*)(Class, SEL))objc_msgSend)(cornerClass, NSSelectorFromString(@"capsuleConfiguration"));
            [view setValue:config forKey:@"cornerConfiguration"];
            return;
        } @catch (__unused id e) {}
    }
    view.layer.cornerRadius = CGRectGetHeight(view.bounds) / 2.0;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.clipsToBounds = YES;
}

static void YTLGCollectItems(UIView *view, Class itemClass, NSMutableArray<UIView *> *items) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:itemClass]) [items addObject:sub];
        else YTLGCollectItems(sub, itemClass, items);
    }
}

// Các item tab, sắp xếp từ trái sang phải
static NSArray<UIView *> *YTLGItemViews(UIView *bar) {
    Class itemClass = NSClassFromString(@"YTPivotBarItemView");
    if (!itemClass) return @[];
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    YTLGCollectItems(bar, itemClass, items);
    [items sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = CGRectGetMidX([a convertRect:a.bounds toView:bar]);
        CGFloat bx = CGRectGetMidX([b convertRect:b.bounds toView:bar]);
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    return items;
}

static BOOL YTLGItemSelected(UIView *item) {
    SEL isSelected = NSSelectorFromString(@"isSelected");
    if ([item respondsToSelector:isSelected] && ((BOOL (*)(id, SEL))objc_msgSend)(item, isSelected)) return YES;
    @try {
        id button = [item valueForKey:@"navigationButton"];
        if ([button isKindOfClass:UIButton.class] && [(UIButton *)button isSelected]) return YES;
    } @catch (__unused id e) {}
    return NO;
}

static void YTLGApplyLabels(UIView *view, BOOL show) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UILabel.class]) {
            if (!show) {
                if (!sub.hidden) {
                    sub.hidden = YES;
                    objc_setAssociatedObject(sub, &kLabelHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            } else if ([objc_getAssociatedObject(sub, &kLabelHiddenKey) boolValue]) {
                sub.hidden = NO;
                objc_setAssociatedObject(sub, &kLabelHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } else {
            YTLGApplyLabels(sub, show);
        }
    }
}

// Tô màu icon/nhãn của 1 item; color = nil để trả về màu gốc
static void YTLGTint(UIView *view, UIColor *color) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UIImageView.class]) {
            UIImageView *iv = (UIImageView *)sub;
            if (color) {
                if (!objc_getAssociatedObject(iv, &kOrigTintKey))
                    objc_setAssociatedObject(iv, &kOrigTintKey, iv.tintColor ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                iv.tintColor = color;
            } else {
                id original = objc_getAssociatedObject(iv, &kOrigTintKey);
                if (original) {
                    iv.tintColor = original == NSNull.null ? nil : original;
                    objc_setAssociatedObject(iv, &kOrigTintKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
        } else if ([sub isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)sub;
            if (color) {
                if (!objc_getAssociatedObject(label, &kOrigTextKey))
                    objc_setAssociatedObject(label, &kOrigTextKey, label.textColor ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                label.textColor = color;
            } else {
                id original = objc_getAssociatedObject(label, &kOrigTextKey);
                if (original) {
                    label.textColor = original == NSNull.null ? nil : original;
                    objc_setAssociatedObject(label, &kOrigTextKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
        }
        YTLGTint(sub, color);
    }
}

static UIImageView *YTLGFirstImageView(UIView *view) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UIImageView.class]) return (UIImageView *)sub;
        UIImageView *found = YTLGFirstImageView(sub);
        if (found) return found;
    }
    return nil;
}

// Nhãn + màu của từng item (gọi cả từ layout của bar lẫn của item)
static void YTLGStyleItem(UIView *item) {
    YTLGApplyLabels(item, gShowLabels || !YTLGGlassActive());

    BOOL isCreate = [objc_getAssociatedObject(item, &kIsCreateKey) boolValue];
    if (isCreate && YTLGGlassActive()) {
        YTLGTint(item, UIColor.whiteColor);
    } else if (gClassic && YTLGItemSelected(item)) {
        YTLGTint(item, YTLGAccent());
    } else {
        YTLGTint(item, nil);
    }

    // Khi ẩn nhãn, đưa icon về giữa item
    if (YTLGGlassActive() && !gShowLabels) {
        UIImageView *iv = YTLGFirstImageView(item);
        if (iv && iv.superview) {
            CGPoint center = CGPointMake(CGRectGetMidX(item.bounds), CGRectGetMidY(item.bounds));
            iv.center = [iv.superview convertPoint:center fromView:item];
        }
    }
}

// MARK: - Liquid Glass: layout thanh tab

static BOOL YTLGRectNear(CGRect a, CGRect b) {
    return fabs(a.origin.x - b.origin.x) < 0.5 && fabs(a.origin.y - b.origin.y) < 0.5 &&
           fabs(a.size.width - b.size.width) < 0.5 && fabs(a.size.height - b.size.height) < 0.5;
}

// Đặt frame cho item nhưng nhớ frame gốc do YouTube tính để khôi phục khi cần (vd. tab Shorts)
static void YTLGSetItemFrame(UIView *item, CGRect frame) {
    NSValue *last = objc_getAssociatedObject(item, &kLastFrameKey);
    if (!last || !YTLGRectNear(item.frame, last.CGRectValue))
        objc_setAssociatedObject(item, &kOrigFrameKey, [NSValue valueWithCGRect:item.frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    item.frame = frame;
    objc_setAssociatedObject(item, &kLastFrameKey, [NSValue valueWithCGRect:item.frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Nhớ trạng thái gốc của nền/ẩn hiện để trả lại khi tắt kính
static void YTLGRememberChrome(UIView *bar, UIView *sub) {
    if (objc_getAssociatedObject(sub, &kOrigBGKey)) return;
    objc_setAssociatedObject(sub, &kOrigBGKey,
        @{@"hidden": @(sub.hidden), @"bg": sub.backgroundColor ?: (id)NSNull.null},
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSHashTable *table = objc_getAssociatedObject(bar, &kChromeKey);
    if (!table) {
        table = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(bar, &kChromeKey, table, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [table addObject:sub];
}

static void YTLGRestoreChrome(UIView *bar) {
    NSHashTable *table = objc_getAssociatedObject(bar, &kChromeKey);
    for (UIView *sub in table.allObjects) {
        NSDictionary *saved = objc_getAssociatedObject(sub, &kOrigBGKey);
        if (!saved) continue;
        objc_setAssociatedObject(sub, &kOrigBGKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        sub.hidden = [saved[@"hidden"] boolValue];
        id bg = saved[@"bg"];
        sub.backgroundColor = bg == NSNull.null ? nil : bg;
    }
    [table removeAllObjects];
}

static void YTLGTeardownBar(UIView *bar) {
    for (NSValue *keyValue in @[[NSValue valueWithPointer:&kGlassKey],
                                [NSValue valueWithPointer:&kPillKey],
                                [NSValue valueWithPointer:&kCircleKey]]) {
        const void *key = keyValue.pointerValue;
        UIView *view = objc_getAssociatedObject(bar, key);
        [view removeFromSuperview];
        objc_setAssociatedObject(bar, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    YTLGRestoreChrome(bar);
    for (UIView *item in YTLGItemViews(bar)) {
        NSValue *orig = objc_getAssociatedObject(item, &kOrigFrameKey);
        if (orig) item.frame = orig.CGRectValue;
        objc_setAssociatedObject(item, &kOrigFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(item, &kLastFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        item.alpha = 1.0;
        item.userInteractionEnabled = YES;
        objc_setAssociatedObject(item, &kIsCreateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        YTLGStyleItem(item);
    }
}

static CGRect YTLGInSuperview(UIView *view, CGRect rectInBar, UIView *bar) {
    return view.superview ? [view.superview convertRect:rectInBar fromView:bar] : rectInBar;
}

static void YTLGLayoutBar(UIView *bar) {
    BOOL hasOurs = objc_getAssociatedObject(bar, &kGlassKey) || objc_getAssociatedObject(bar, &kChromeKey);
    if (!gGlassOn) {
        gOnShorts = NO;
        if (hasOurs) YTLGTeardownBar(bar);
        return;
    }
    CGFloat W = CGRectGetWidth(bar.bounds), H = CGRectGetHeight(bar.bounds);
    if (W < 200.0 || H < 40.0) return;

    NSArray<UIView *> *items = YTLGItemViews(bar);
    if (items.count < 2) return;

    // Xác định item Tạo (+): item thứ i ứng với tab hiển thị thứ i
    NSArray<NSString *> *ids = YTLGVisibleIDs();
    NSUInteger createIdx = NSNotFound;
    if (gSplit && ids.count == items.count) createIdx = [ids indexOfObject:kCreateID];
    BOOL split = createIdx != NSNotFound && items.count > 2;

    NSUInteger selectedIdx = NSNotFound;
    for (NSUInteger i = 0; i < items.count; i++)
        if (i != createIdx && YTLGItemSelected(items[i])) { selectedIdx = i; break; }

    // Tab Shorts: trả lại giao diện gốc của YouTube (nền đen và chân video do YouTube tự xử lý)
    NSString *current = nil;
    @try {
        id value = [bar valueForKey:@"selectedPivotIdentifier"];
        if ([value isKindOfClass:NSString.class] && [value length]) current = value;
    } @catch (__unused id e) {}
    if (!current && selectedIdx != NSNotFound && ids.count == items.count) current = ids[selectedIdx];
    if (!current) current = gCurrentPivotID;
    gOnShorts = [current isEqualToString:@"FEshorts"];
    if (gOnShorts) {
        if (hasOurs) YTLGTeardownBar(bar);
        return;
    }

    NSUInteger selected = selectedIdx == NSNotFound ? 0 : selectedIdx;
    if (split && selected == createIdx) selected = 0;

    const CGFloat margin = 14.0, gap = 8.0;
    CGFloat contentHeight = MAX(H - bar.safeAreaInsets.bottom, 44.0);
    CGFloat d = MAX(contentHeight - 8.0, 40.0);

    BOOL collapsed = gMinimize && gCollapsed;
    UIColor *accent = YTLGAccent();

    // 1) Nền kính của bar
    CGFloat fullWidth = W - 2 * margin - (split ? d + gap : 0);
    CGRect capsule = CGRectMake(margin, 4.0, collapsed ? d : fullWidth, d);

    UIVisualEffectView *glass = YTLGGlassView(bar, &kGlassKey, nil);
    UIView *pill = objc_getAssociatedObject(bar, &kPillKey);
    if (!pill) {
        pill = [UIView new];
        pill.userInteractionEnabled = NO;
        objc_setAssociatedObject(bar, &kPillKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glass.superview != bar) [bar insertSubview:glass atIndex:0];
    if (pill.superview != bar) [bar insertSubview:pill atIndex:1];
    glass.frame = capsule;
    YTLGRound(glass);

    // 2) Vòng tròn kính cho nút Tạo (+)
    UIVisualEffectView *circle = objc_getAssociatedObject(bar, &kCircleKey);
    if (split) {
        circle = YTLGGlassView(bar, &kCircleKey, accent);
        if (circle.superview != bar) [bar insertSubview:circle atIndex:2];
        circle.frame = CGRectMake(W - margin - d, 4.0, d, d);
        YTLGRound(circle);
    } else if (circle) {
        [circle removeFromSuperview];
        objc_setAssociatedObject(bar, &kCircleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        circle = nil;
    }

    // 3) Đặt frame các item
    NSUInteger regularCount = items.count - (split ? 1 : 0);
    CGFloat slotWidth = fullWidth / MAX(regularCount, 1);
    NSUInteger slot = 0;
    CGRect selectedFrame = capsule;
    for (NSUInteger i = 0; i < items.count; i++) {
        UIView *item = items[i];
        BOOL isCreate = split && i == createIdx;
        objc_setAssociatedObject(item, &kIsCreateKey, isCreate ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        CGRect target;
        if (isCreate) {
            target = CGRectMake(W - margin - d, 4.0, d, d);
        } else {
            target = CGRectMake(margin + slot * slotWidth, 4.0, slotWidth, d);
            slot++;
        }
        BOOL isSelected = (i == selected);
        if (isSelected) selectedFrame = target;
        if (collapsed && !isCreate && isSelected) target = capsule;

        YTLGSetItemFrame(item, YTLGInSuperview(item, target, bar));
        BOOL visible = !collapsed || isCreate || isSelected;
        item.alpha = visible ? 1.0 : 0.0;
        item.userInteractionEnabled = visible;
        YTLGStyleItem(item);
    }

    // 4) Viên chọn tab
    pill.hidden = collapsed;
    pill.frame = CGRectInset(selectedFrame, 4.0, 4.0);
    pill.layer.cornerRadius = CGRectGetHeight(pill.frame) / 2.0;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.backgroundColor = gClassic ? [accent colorWithAlphaComponent:0.18]
                                    : [UIColor.labelColor colorWithAlphaComponent:0.10];

    // 5) Làm trong suốt nền gốc của bar (nhớ lại để trả khi cần)
    YTLGRememberChrome(bar, bar);
    bar.backgroundColor = UIColor.clearColor;
    for (UIView *sub in bar.subviews) {
        if (sub == glass || sub == pill || sub == circle) continue;
        if ([sub isKindOfClass:UIVisualEffectView.class]) { YTLGRememberChrome(bar, sub); sub.hidden = YES; continue; }
        if (CGRectGetHeight(sub.bounds) <= 1.5) { YTLGRememberChrome(bar, sub); sub.hidden = YES; continue; }
        if (object_getClass(sub) == UIView.class) { YTLGRememberChrome(bar, sub); sub.backgroundColor = UIColor.clearColor; }
    }
}

static void YTLGFindBars(UIView *view, NSMutableArray<UIView *> *bars) {
    Class barClass = NSClassFromString(@"YTPivotBarView");
    if (!barClass) return;
    if ([view isKindOfClass:barClass]) { [bars addObject:view]; return; }
    for (UIView *sub in view.subviews) YTLGFindBars(sub, bars);
}

// Áp dụng lại cấu hình tab ngay lên thanh tab đang hiển thị
static void YTLGReapplyTabs(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray<UIView *> *bars = [NSMutableArray array];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) YTLGFindBars(window, bars);
        }
        for (UIView *bar in bars) {
            id renderer = objc_getAssociatedObject(bar, &kRendererKey);
            if (renderer && [bar respondsToSelector:NSSelectorFromString(@"setRenderer:")])
                ((void (*)(id, SEL, id))objc_msgSend)(bar, NSSelectorFromString(@"setRenderer:"), renderer);
            [bar setNeedsLayout];
        }
    });
}

// MARK: - Thu gọn khi cuộn

static CGFloat gScrollAccum = 0;

static void YTLGSetCollapsed(BOOL collapsed) {
    if (gCollapsed == collapsed) return;
    gCollapsed = collapsed;
    YTLGPostRelayout(YES, NO);
}

static void YTLGHandleScroll(CGFloat dy, CGFloat distanceFromTop) {
    if (distanceFromTop <= 1.0) { gScrollAccum = 0; YTLGSetCollapsed(NO); return; }
    if ((dy > 0) != (gScrollAccum > 0)) gScrollAccum = 0;
    gScrollAccum += dy;
    if (gScrollAccum > 28.0) YTLGSetCollapsed(YES);
    else if (gScrollAccum < -18.0) YTLGSetCollapsed(NO);
}

%hook UIScrollView

- (void)setContentOffset:(CGPoint)offset {
    CGFloat previous = self.contentOffset.y;
    %orig(offset);
    if (!gGlassOn || !gMinimize) return;
    if (!(self.isTracking || self.isDecelerating)) return;
    CGSize contentSize = self.contentSize;
    CGRect bounds = self.bounds;
    if (contentSize.width > bounds.size.width + 1.0 || bounds.size.width < 300.0 ||
        contentSize.height < bounds.size.height * 1.5) return;
    YTLGHandleScroll(offset.y - previous, offset.y + self.adjustedContentInset.top);
}

%end

// MARK: - Trang "Chỉnh thanh điều hướng" (thêm / bớt / sắp xếp tab)

@interface YTLGTabEditorViewController : UITableViewController
@property (nonatomic, strong) NSMutableArray<NSString *> *visible;
@property (nonatomic, strong) NSMutableArray<NSString *> *available;
@property (nonatomic, copy) NSString *startup;
@end

@implementation YTLGTabEditorViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"Chỉnh thanh điều hướng";
        [self reloadModel];
    }
    return self;
}

- (void)reloadModel {
    NSSet *hidden = YTLGHiddenIDs();
    _visible = [NSMutableArray array];
    _available = [NSMutableArray array];
    for (NSString *identifier in YTLGOrderedIDs())
        [([hidden containsObject:identifier] ? _available : _visible) addObject:identifier];
    _startup = [YTLGDefaults() stringForKey:kStartupTab] ?: @"";
    if ([_available containsObject:_startup]) _startup = @"";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
}

- (void)save {
    NSMutableArray *order = [self.visible mutableCopy];
    [order addObjectsFromArray:self.available];
    [YTLGDefaults() setObject:order forKey:kTabOrder];
    [YTLGDefaults() setObject:self.available forKey:kTabHidden];
    [YTLGDefaults() setObject:self.startup ?: @"" forKey:kStartupTab];
    YTLGReapplyTabs();
    YTLGPostRelayout(NO, NO);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return self.visible.count;
        case 1: return self.available.count;
        case 2: return self.visible.count + 1;
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Đang hiển thị (kéo để sắp xếp)";
    if (section == 1) return self.available.count ? @"Có thể thêm" : nil;
    if (section == 2) return @"Tab mở đầu";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Dấu − để bớt tab, dấu + ở mục bên dưới để thêm lại. Nếu thanh tab chưa đổi ngay, hãy khởi động lại YouTube.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.showsReorderControl = YES;
    switch (indexPath.section) {
        case 0:
            cell.textLabel.text = YTLGTabTitle(self.visible[indexPath.row]);
            break;
        case 1:
            cell.textLabel.text = YTLGTabTitle(self.available[indexPath.row]);
            break;
        case 2: {
            NSString *identifier = indexPath.row == 0 ? @"" : self.visible[indexPath.row - 1];
            cell.textLabel.text = indexPath.row == 0 ? @"Mặc định của YouTube" : YTLGTabTitle(identifier);
            cell.editingAccessoryType = [self.startup isEqualToString:identifier]
                ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            break;
        }
        default:
            cell.textLabel.text = @"Đặt lại về mặc định";
            cell.textLabel.textColor = UIColor.systemRedColor;
    }
    return cell;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0)
        return [self.visible[indexPath.row] isEqualToString:kHomeID]
            ? UITableViewCellEditingStyleNone : UITableViewCellEditingStyleDelete;
    if (indexPath.section == 1) return UITableViewCellEditingStyleInsert;
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section <= 1;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style
                                             forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style == UITableViewCellEditingStyleDelete && indexPath.section == 0) {
        NSString *identifier = self.visible[indexPath.row];
        if ([identifier isEqualToString:kHomeID]) return;
        [self.visible removeObjectAtIndex:indexPath.row];
        [self.available addObject:identifier];
        if ([self.startup isEqualToString:identifier]) self.startup = @"";
    } else if (style == UITableViewCellEditingStyleInsert && indexPath.section == 1) {
        NSString *identifier = self.available[indexPath.row];
        [self.available removeObjectAtIndex:indexPath.row];
        [self.visible addObject:identifier];
    } else {
        return;
    }
    [self save];
    [tableView reloadData];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
    targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source
                         toProposedIndexPath:(NSIndexPath *)proposed {
    if (proposed.section == 0) return proposed;
    return [NSIndexPath indexPathForRow:(proposed.section > 0 ? self.visible.count - 1 : 0) inSection:0];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    NSString *moved = self.visible[source.row];
    [self.visible removeObjectAtIndex:source.row];
    [self.visible insertObject:moved atIndex:destination.row];
    [self save];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        [self tableView:tableView commitEditingStyle:UITableViewCellEditingStyleInsert forRowAtIndexPath:indexPath];
    } else if (indexPath.section == 2) {
        self.startup = indexPath.row == 0 ? @"" : self.visible[indexPath.row - 1];
        [self save];
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
    } else if (indexPath.section == 3) {
        [YTLGDefaults() removeObjectForKey:kTabOrder];
        [YTLGDefaults() removeObjectForKey:kTabHidden];
        [YTLGDefaults() removeObjectForKey:kStartupTab];
        [self reloadModel];
        YTLGReapplyTabs();
        YTLGPostRelayout(NO, NO);
        [tableView reloadData];
    }
}

@end

// MARK: - Trang Appearance+ (mô phỏng trang Appearance của NeoFreeBird)

@interface YTLGAppearanceViewController : UITableViewController <UIColorPickerViewControllerDelegate>
@property (nonatomic, copy) NSArray<NSDictionary *> *rows;
@end

@implementation YTLGAppearanceViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = @"Appearance+";
        _rows = @[
            @{@"type": @"nav", @"title": @"Đổi màu chủ đạo",
              @"sub": @"Màu cho tab đang chọn và nút Tạo (+).", @"action": @"openAccent"},
            @{@"type": @"nav", @"title": @"Chỉnh thanh điều hướng",
              @"sub": @"Ẩn/hiện, sắp xếp tab và chọn tab mở đầu.", @"action": @"openTabEditor"},
            @{@"type": @"switch", @"title": @"Bật Liquid Glass", @"key": kLiquidGlass,
              @"sub": @"Thanh tab kính nổi, và giao diện iOS 26 cho toàn app (cần iOS 26+). Khởi động lại để áp dụng đầy đủ."},
            @{@"type": @"switch", @"title": @"Thanh tab cổ điển", @"key": kClassic,
              @"sub": @"Áp dụng màu chủ đạo cho mục tab đang chọn."},
            @{@"type": @"switch", @"title": @"Nhãn tab", @"key": kShowLabels,
              @"sub": @"Hiện nhãn chữ dưới biểu tượng trên thanh tab."},
            @{@"type": @"switch", @"title": @"Thu gọn thanh tab khi cuộn", @"key": kMinimize,
              @"sub": @"Cuộn xuống thì thanh tab thu về 1 vòng tròn, cuộn lên thì mở lại."},
            @{@"type": @"switch", @"title": @"Tách nút Tạo (+)", @"key": kSplit,
              @"sub": @"Đưa nút Tạo ra thành vòng tròn kính riêng bên phải."},
            @{@"type": @"nav", @"title": @"Thoát YouTube để áp dụng",
              @"sub": @"Mở lại YouTube sau khi thoát.", @"action": @"quitApp"},
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.estimatedRowHeight = 72;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = self.rows[indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = UIColor.clearColor;
    cell.textLabel.text = row[@"title"];
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    cell.detailTextLabel.text = row[@"sub"];
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:14];

    if ([row[@"type"] isEqualToString:@"switch"]) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = YTLGBool(row[@"key"]);
        toggle.tag = indexPath.row;
        [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([row[@"action"] isEqualToString:@"quitApp"]) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.textColor = UIColor.systemRedColor;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    NSDictionary *row = self.rows[sender.tag];
    YTLGSetBool(row[@"key"], sender.isOn);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *action = self.rows[indexPath.row][@"action"];
    if (action.length) {
        SEL selector = NSSelectorFromString(action);
        if ([self respondsToSelector:selector]) ((void (*)(id, SEL))objc_msgSend)(self, selector);
    }
}

- (void)openAccent {
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.selectedColor = YTLGAccent();
    picker.supportsAlpha = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    [YTLGDefaults() setObject:YTLGHexFromColor(viewController.selectedColor) forKey:kAccentHex];
    YTLGPostRelayout(NO, YES);
}

- (void)openTabEditor {
    [self.navigationController pushViewController:[YTLGTabEditorViewController new] animated:YES];
}

- (void)quitApp {
    [YTLGDefaults() synchronize];
    exit(0);
}

@end

// MARK: - Mở Appearance+ bằng cách nhấn giữ logo YouTube

static char kYTLGLogoGestureKey;

static UIViewController *YTLGTopVC(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows)
            if (w.isKeyWindow) window = w;
    }
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

@interface YTLGHandler : NSObject
+ (instancetype)shared;
@end

@implementation YTLGHandler

+ (instancetype)shared {
    static YTLGHandler *handler;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ handler = [self new]; });
    return handler;
}

- (void)closeSheet { [YTLGTopVC() dismissViewControllerAnimated:YES completion:nil]; }

- (void)logoLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIViewController *top = YTLGTopVC();
    if (!top) return;
    YTLGAppearanceViewController *page = [YTLGAppearanceViewController new];
    page.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self action:@selector(closeSheet)];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:page];
    [top presentViewController:nav animated:YES completion:nil];
}

// Chạm vào thanh tab khi đang thu gọn thì mở lại
- (void)barTapped:(UITapGestureRecognizer *)gesture {
    if (gCollapsed) { gScrollAccum = 0; YTLGSetCollapsed(NO); }
    // Sau khi chạm đổi tab, bố cục cần chạy lại để vào/ra chế độ Shorts
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        YTLGPostRelayout(NO, NO);
    });
}

@end

static UIView *YTLGFindLogo(UIView *view) {
    for (UIView *sub in view.subviews) {
        if ([NSStringFromClass(sub.class) rangeOfString:@"Logo" options:NSCaseInsensitiveSearch].location != NSNotFound)
            return sub;
        UIView *found = YTLGFindLogo(sub);
        if (found) return found;
    }
    return nil;
}

%hook YTHeaderView

- (void)layoutSubviews {
    %orig;
    UIView *logo = YTLGFindLogo((UIView *)self);
    if (!logo || objc_getAssociatedObject(logo, &kYTLGLogoGestureKey)) return;
    UILongPressGestureRecognizer *press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:[YTLGHandler shared]
                                                      action:@selector(logoLongPress:)];
    press.minimumPressDuration = 0.6;
    logo.userInteractionEnabled = YES;
    [logo addGestureRecognizer:press];
    objc_setAssociatedObject(logo, &kYTLGLogoGestureKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end

// MARK: - Mục "Appearance+" trong Cài đặt YouTube

%hook YTSettingsGroupData

- (NSArray<NSNumber *> *)orderedCategories {
    NSArray<NSNumber *> *orig = %orig;
    if (self.type != 1 || [orig containsObject:@(kYTLGCategory)]) return orig;
    NSMutableArray *categories = [orig mutableCopy];
    [categories insertObject:@(kYTLGCategory) atIndex:0];
    return categories.copy;
}

%end

%hook YTAppSettingsPresentationData

+ (NSArray<NSNumber *> *)settingsCategoryOrder {
    NSArray<NSNumber *> *order = %orig;
    if ([order containsObject:@(kYTLGCategory)]) return order;
    NSUInteger index = [order indexOfObject:@(1)];
    if (index == NSNotFound) return order;
    NSMutableArray *mutableOrder = [order mutableCopy];
    [mutableOrder insertObject:@(kYTLGCategory) atIndex:index + 1];
    return mutableOrder.copy;
}

%end

%hook YTSettingsSectionItemManager

%new(v@:@)
- (void)updateYTLGSectionWithEntry:(id)entry {
    NSMutableArray *items = [NSMutableArray array];
    Class itemClass = %c(YTSettingsSectionItem);
    YTSettingsViewController *settingsVC = [self valueForKey:@"_settingsViewControllerDelegate"];
    __weak YTSettingsViewController *weakVC = settingsVC;

    [items addObject:[itemClass
        itemWithTitle:@"Appearance+"
     titleDescription:@"Liquid Glass, thanh tab, màu chủ đạo."
accessibilityIdentifier:nil
      detailTextBlock:^NSString *{ return YTLGBool(kLiquidGlass) ? @"Bật" : @"Tắt"; }
          selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
              YTSettingsViewController *vc = weakVC;
              if (!vc) return NO;
              UIViewController *page = [YTLGAppearanceViewController new];
              page.overrideUserInterfaceStyle = vc.traitCollection.userInterfaceStyle;
              if ([vc respondsToSelector:@selector(pushViewController:)])
                  [vc pushViewController:page];
              else
                  [vc.navigationController pushViewController:page animated:YES];
              return YES;
          }]];

    if ([settingsVC respondsToSelector:@selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)])
        [settingsVC setSectionItems:items forCategory:kYTLGCategory title:@"Appearance+"
                               icon:nil titleDescription:nil headerHidden:NO];
    else
        [settingsVC setSectionItems:items forCategory:kYTLGCategory title:@"Appearance+"
                   titleDescription:nil headerHidden:NO];
}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == kYTLGCategory) {
        [self updateYTLGSectionWithEntry:entry];
        return;
    }
    %orig;
}

%end

// MARK: - Hook thanh tab của YouTube

%hook YTPivotBarView

- (void)setRenderer:(id)renderer {
    YTLGApplyTabLayout(renderer);
    objc_setAssociatedObject(self, &kRendererKey, renderer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(renderer);
}

// YouTube (nhất là ở tab Shorts) có thể tô nền đen lại; khi kính đang bật thì giữ trong suốt
- (void)setBackgroundColor:(UIColor *)color {
    if (YTLGGlassActive()) color = UIColor.clearColor;
    %orig(color);
}

- (void)didMoveToWindow {
    %orig;
    UIView *bar = (UIView *)self;
    if (!bar.window || objc_getAssociatedObject(bar, &kObserverKey)) return;

    __weak UIView *weakBar = bar;
    id token = [NSNotificationCenter.defaultCenter
        addObserverForName:kYTLGRelayout object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) {
        UIView *strongBar = weakBar;
        if (!strongBar) return;
        if ([note.userInfo[@"rebuild"] boolValue]) YTLGTeardownBar(strongBar);
        void (^relayout)(void) = ^{
            [strongBar setNeedsLayout];
            [strongBar layoutIfNeeded];
        };
        if ([note.userInfo[@"animated"] boolValue])
            [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.2
                                options:UIViewAnimationOptionAllowUserInteraction
                             animations:relayout completion:nil];
        else
            relayout();
    }];
    objc_setAssociatedObject(bar, &kObserverKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[YTLGHandler shared]
                                                                          action:@selector(barTapped:)];
    tap.cancelsTouchesInView = NO;
    [bar addGestureRecognizer:tap];
    objc_setAssociatedObject(bar, &kTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)layoutSubviews {
    %orig;
    YTLGLayoutBar((UIView *)self);
}

%end

%hook YTPivotBarItemView

- (void)layoutSubviews {
    %orig;
    YTLGStyleItem((UIView *)self);
}

%end

// Tab mở đầu: chọn 1 lần mỗi lần khởi động app
%hook YTPivotBarViewController

- (void)selectItemWithPivotIdentifier:(NSString *)identifier {
    %orig;
    gCurrentPivotID = [identifier copy];
    YTLGPostRelayout(NO, NO);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *startup = [YTLGDefaults() stringForKey:kStartupTab];
        if (!startup.length || [YTLGHiddenIDs() containsObject:startup]) return;
        if (![self respondsToSelector:@selector(selectItemWithPivotIdentifier:)]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self selectItemWithPivotIdentifier:startup];
        });
    });
}

%end

// MARK: - Giao diện iOS 26 cho toàn app (SDK spoof)
//
// X bật Liquid Glass bằng feature switch nội bộ; YouTube không có, nên ép UIKit dùng
// giao diện iOS 26 cho app build bằng SDK cũ:
//  1) Giả lập app được link với SDK iOS 26 (dyld_program_sdk_at_least).
//  2) Gỡ cờ UIDesignRequiresCompatibility trong Info.plist nếu có.

typedef struct { uint32_t platform; uint32_t version; } YTLGDyldBuildVersion;
static bool (*orig_dyld_program_sdk_at_least)(YTLGDyldBuildVersion version);

static bool hook_dyld_program_sdk_at_least(YTLGDyldBuildVersion version) {
    if (gLiquidGlassSDK) {
        if (version.platform == 0xffffffff && (version.version >> 16) >= 2025) return true;
        if (version.platform == 2 && version.version >= 0x001A0000) return true;
    }
    return orig_dyld_program_sdk_at_least(version);
}

%hook NSBundle

- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (gLiquidGlassSDK && [key isEqualToString:@"UIDesignRequiresCompatibility"]) return @NO;
    return %orig;
}

%end

%ctor {
    [YTLGDefaults() registerDefaults:@{
        kLiquidGlass: @NO,
        kClassic: @NO,
        kShowLabels: @YES,
        kMinimize: @YES,
        kSplit: @YES,
    }];
    YTLGReloadFlags();

    gLiquidGlassSDK = gGlassOn &&
        [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){26, 0, 0}];

    if (gLiquidGlassSDK) {
        void *symbol = dlsym(RTLD_DEFAULT, "dyld_program_sdk_at_least");
        if (symbol)
            MSHookFunction(symbol, (void *)hook_dyld_program_sdk_at_least, (void **)&orig_dyld_program_sdk_at_least);
    }

    %init;
}
