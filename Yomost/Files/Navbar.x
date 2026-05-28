// Navbar.x
#import "Headers.h"

// ==========================================
// ĐỊNH NGHĨA INTERFACE ĐỂ SỬA LỖI FORWARD CLASS
// ==========================================
@interface YTTabBarController : UIViewController
@property (nonatomic, assign, readonly) UITabBar *tabBar;
@end

// Định nghĩa các ID tương ứng cho từng Tab mặc định của YouTube
typedef NS_ENUM(NSInteger, YTTabType) {
    YTTabTypeHome = 0,
    YTTabTypeShorts = 1,
    YTTabTypeCreate = 2,
    YTTabTypeSubscriptions = 3,
    YTTabTypeLibrary = 4
};

// ==========================================
// 1. QUẢN LÝ THANH ĐIỀU HƯỚNG TRÊN (NAVBAR)
// ==========================================

%hook YTHeaderLogoController
- (void)setTopbarLogoRenderer:(id)renderer {
    // Sửa lỗi ẩn logo: Nếu bật ẩn, ta ẩn view của nó thay vì hủy khởi tạo init
    if (IS_ENABLED(HideYTLogo)) {
        if ([self respondsToSelector:@selector(view)]) {
            [[self valueForKey:@"view"] setHidden:YES];
        }
        return;
    }
    
    if (!IS_ENABLED(YTPremiumLogo) || !renderer) {
        %orig;
        return;
    }
    
    @try {
        if ([renderer respondsToSelector:@selector(iconImage)]) {
            id icon = [renderer iconImage];
            if (icon && [icon respondsToSelector:@selector(setIconType:)]) {
                [icon setIconType:537];
            }
        }
    } @catch (NSException *e) {}
    %orig(renderer);
}
- (void)setPremiumLogo:(BOOL)arg { IS_ENABLED(YTPremiumLogo) ? %orig(YES) : %orig; }
- (BOOL)isPremiumLogo { return IS_ENABLED(YTPremiumLogo) ? YES : %orig; }
%end

%hook YTHeaderLogoControllerImpl
- (void)setTopbarLogoRenderer:(id)renderer {
    if (IS_ENABLED(HideYTLogo)) {
        if ([self respondsToSelector:@selector(view)]) {
            [[self valueForKey:@"view"] setHidden:YES];
        }
        return;
    }
    
    if (!IS_ENABLED(YTPremiumLogo) || !renderer) {
        %orig;
        return;
    }
    
    @try {
        if ([renderer respondsToSelector:@selector(iconImage)]) {
            id icon = [renderer iconImage];
            if (icon && [icon respondsToSelector:@selector(setIconType:)]) {
                [icon setIconType:537];
            }
        }
    } @catch (NSException *e) {}
    %orig(renderer);
}
- (void)setPremiumLogo:(BOOL)arg { IS_ENABLED(YTPremiumLogo) ? %orig(YES) : %orig; }
- (BOOL)isPremiumLogo { return IS_ENABLED(YTPremiumLogo) ? YES : %orig; }
%end

// Ẩn các nút chức năng trên thanh Navbar an toàn
%hook YTRightNavigationButtons
- (void)layoutSubviews {
    %orig;
    @try {
        if (IS_ENABLED(HideNoti) && [self respondsToSelector:@selector(notificationButton)]) {
            [[self valueForKey:@"notificationButton"] setHidden:YES];
        }
        if (IS_ENABLED(HideSearch) && [self respondsToSelector:@selector(searchButton)]) {
            [[self valueForKey:@"searchButton"] setHidden:YES];
        }
        
        if ([self respondsToSelector:@selector(subviews)]) {
            for (UIView *subview in self.subviews) {
                if (IS_ENABLED(HideVoiceSearch) && [subview respondsToSelector:@selector(accessibilityLabel)]) {
                    if ([subview.accessibilityLabel isEqualToString:NSLocalizedString(@"search.voice.access", nil)]) {
                        subview.hidden = YES;
                    }
                }
                if (IS_ENABLED(HideCastButtonNav) && [subview respondsToSelector:@selector(accessibilityIdentifier)]) {
                    if ([subview.accessibilityIdentifier isEqualToString:@"id.mdx.playbackroute.button"]) {
                        subview.hidden = YES;
                    }
                }
            }
        }
    } @catch (NSException *e) {}
}
%end

// Ẩn ảnh biểu trưng sự kiện (Yoodle) an toàn, sửa lỗi chỉ mục vượt mảng [1]
%hook YTNavigationBarTitleView
- (void)layoutSubviews {
    %orig;
    if (IS_ENABLED(HideYTLogo) && [self respondsToSelector:@selector(subviews)]) {
        for (UIView *subview in self.subviews) {
            if ([subview respondsToSelector:@selector(accessibilityIdentifier)]) {
                if ([subview.accessibilityIdentifier isEqualToString:@"id.yoodle.logo"]) {
                    subview.hidden = YES;
                }
            }
        }
    }
}
%end

// ==========================================
// 2. QUẢN LÝ SẮP XẾP & ẨN/HIỆN TAB (TABBAR)
// ==========================================

%hook YTTabBarController

- (void)setViewControllers:(NSArray *)viewControllers animated:(BOOL)animated {
    if (!viewControllers || viewControllers.count == 0) {
        %orig;
        return;
    }

    // Lấy danh sách sắp xếp tab được lưu từ cài đặt
    NSArray *tabOrder = [[NSUserDefaults standardUserDefaults] objectForKey:@"YomostTabOrder"];
    if (!tabOrder) {
        tabOrder = @[@0, @1, @2, @3, @4];
    }

    NSMutableDictionary *tabMap = [NSMutableDictionary dictionary];
    
    for (id vc in viewControllers) {
        if (!vc) continue;
        NSString *className = NSStringFromClass([vc class]);
        
        if ([className containsString:@"Home"] || ([vc respondsToSelector:@selector(navigationBarTitle)] && [[vc performSelector:@selector(navigationBarTitle)] containsString:@"Home"])) {
            tabMap[@(YTTabTypeHome)] = vc;
        } else if ([className containsString:@"Shorts"]) {
            tabMap[@(YTTabTypeShorts)] = vc;
        } else if ([className containsString:@"Create"] || [className containsString:@"Upload"]) {
            tabMap[@(YTTabTypeCreate)] = vc;
        } else if ([className containsString:@"Subscription"]) {
            tabMap[@(YTTabTypeSubscriptions)] = vc;
        } else if ([className containsString:@"Library"] || [className containsString:@"You"] || [className containsString:@"History"]) {
            tabMap[@(YTTabTypeLibrary)] = vc;
        }
    }

    NSMutableArray *filteredAndOrderedVCs = [NSMutableArray array];

    for (NSNumber *tabNum in tabOrder) {
        NSInteger tabType = [tabNum integerValue];
        
        if (tabType == YTTabTypeHome && IS_ENABLED(HideHomeTab)) continue;
        if (tabType == YTTabTypeShorts && IS_ENABLED(HideShortsTab)) continue;
        if (tabType == YTTabTypeCreate && IS_ENABLED(HideCreateButton)) continue;
        if (tabType == YTTabTypeSubscriptions && IS_ENABLED(HideSubscriptTab)) continue;
        if (tabType == YTTabTypeLibrary && [[NSUserDefaults standardUserDefaults] boolForKey:@"HideLibraryTab"]) continue;

        id targetVC = tabMap[tabNum];
        if (targetVC) {
            [filteredAndOrderedVCs addObject:targetVC];
        }
    }

    if (filteredAndOrderedVCs.count == 0 && tabMap[@(YTTabTypeHome)]) {
        [filteredAndOrderedVCs addObject:tabMap[@(YTTabTypeHome)]];
    }

    %orig(filteredAndOrderedVCs.copy, animated);
}
%end

// Sửa lỗi layoutSubviews trong UIViewController bằng cách di chuyển hook sang đúng thực thể UITabBar của hệ thống
%hook UITabBar
- (void)layoutSubviews {
    %orig;
    if (IS_ENABLED(HideTabLabels) && [self respondsToSelector:@selector(subviews)]) {
        for (UIView *tabButton in self.subviews) {
            if ([tabButton isKindOfClass:NSClassFromString(@"UITabBarButton")]) {
                for (UIView *subview in tabButton.subviews) {
                    if ([subview isKindOfClass:[UILabel class]]) {
                        subview.hidden = YES;
                    }
                }
            }
        }
    }
}
%end
