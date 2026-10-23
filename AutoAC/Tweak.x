#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define kPrefs [NSUserDefaults standardUserDefaults]
static const NSInteger AutoACSection = 2026;

#pragma mark - Interfaces (khai báo tối thiểu, không phụ thuộc YouTubeHeader)

@interface YTSettingsSectionItem : NSObject
+ (id)switchItemWithTitle:(id)arg1
         titleDescription:(id)arg2
  accessibilityIdentifier:(id)arg3
                 switchOn:(BOOL)arg4
              switchBlock:(id)arg5
            settingItemId:(int)arg6;
@end

@interface YTSettingsSectionItemManager : NSObject
@end

@interface YTAppSettingsPresentationData : NSObject
@end

@interface YTTabBar : UIView
- (void)autoAC_handleLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@interface YTPromoThrottleController : NSObject
@end

@interface YTCommerceEventGroupHandler : NSObject
@end

@interface UIViewController (AutoAC)
- (void)setSectionItems:(id)items
            forCategory:(NSInteger)category
                  title:(id)title
       titleDescription:(id)description;
@end

#pragma mark - Helpers

// Lấy ViewController trên cùng, không dùng keyWindow (đã bị deprecated từ iOS 13)
static UIViewController *AutoACTopViewController(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
        }
        if (keyWindow) break;
    }
    UIViewController *topVC = keyWindow.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

#pragma mark - Hook Settings

%hook YTSettingsSectionItemManager
- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == AutoACSection) {
        Class itemClass = %c(YTSettingsSectionItem);
        if (!itemClass) {
            %orig;
            return;
        }

        NSMutableArray *items = [NSMutableArray array];

        [items addObject:[itemClass switchItemWithTitle:@"Xoá cache tự động"
                                      titleDescription:@"Tự dọn khi mở app"
                                accessibilityIdentifier:nil
                                              switchOn:[kPrefs boolForKey:@"kAutoClearCache"]
                                           switchBlock:^BOOL(id cell, BOOL enabled) {
                                               [kPrefs setBool:enabled forKey:@"kAutoClearCache"];
                                               return YES;
                                           }
                                         settingItemId:0]];

        // Truy xuất Delegate: thử nhiều key khác nhau để tránh bị nil
        id settingsVC = nil;
        NSArray<NSString *> *keys = @[@"_settingsViewControllerDelegate",
                                      @"settingsViewControllerDelegate",
                                      @"_delegate"];
        for (NSString *key in keys) {
            @try {
                settingsVC = [self valueForKey:key];
            } @catch (NSException *e) {
                settingsVC = nil;
            }
            if (settingsVC) break;
        }

        if (settingsVC && [settingsVC respondsToSelector:@selector(setSectionItems:forCategory:title:titleDescription:)]) {
            [(id)settingsVC setSectionItems:items
                                forCategory:AutoACSection
                                      title:@"AutoAC Settings"
                           titleDescription:@"Cấu hình bởi 2KGT"];
        }
        return;
    }
    %orig;
}
%end

%hook YTAppSettingsPresentationData
+ (NSArray *)settingsCategoryOrder {
    NSArray *origOrder = %orig;
    NSMutableArray *order = [origOrder mutableCopy];
    if (!order) return origOrder;

    if (![order containsObject:@(AutoACSection)]) {
        NSUInteger index = order.count > 1 ? 1 : order.count;
        [order insertObject:@(AutoACSection) atIndex:index];
    }
    return [order copy];
}
%end

#pragma mark - Hook Long Press

%hook YTTabBar

- (void)layoutSubviews {
    %orig;

    // Dùng associated object để tránh add trùng
    if (!objc_getAssociatedObject(self, @selector(autoAC_handleLongPress:))) {

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(autoAC_handleLongPress:)];

        lp.minimumPressDuration = 0.5;
        lp.cancelsTouchesInView = NO; // Không làm liệt các nút bấm khác

        [self addGestureRecognizer:lp];

        objc_setAssociatedObject(self,
                                 @selector(autoAC_handleLongPress:),
                                 @(YES),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        NSLog(@"[AutoAC] Gesture đã được nạp vào YTTabBar");
    }
}

%new
- (void)autoAC_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    NSLog(@"[AutoAC] LONG PRESS DETECTED");

    UIViewController *topVC = AutoACTopViewController();
    if (!topVC) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AutoAC"
                                                                   message:@"Kích hoạt tính năng thành công! ✅"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];

    [topVC presentViewController:alert animated:YES completion:nil];
}
%end

#pragma mark - Fix Promo

// Chặn các thông báo làm phiền có thể đè lên UI
%hook YTPromoThrottleController
- (BOOL)canShowThrottledPromo { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1 { return NO; }
%end

%hook YTCommerceEventGroupHandler
- (void)addEventHandlers {}
%end
