#import <AutoACheaders/AutoACheaders.h>
#import <YouTubeHeader/YTIShowFullscreenInterstitialCommand.h> // Theo tham khảo từ image.png
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define kPrefs [NSUserDefaults standardUserDefaults]
static const NSInteger AutoACSection = 2026;

#pragma mark - Interfaces

@interface YTSettingsSectionItem : NSObject
+ (id)switchItemWithTitle:(id)arg1
       titleDescription:(id)arg2
 accessibilityIdentifier:(id)arg3
             switchOn:(BOOL)arg4
          switchBlock:(id)arg5
       settingItemId:(int)arg6;
@end

@interface UIViewController (AutoAC)
- (void)setSectionItems:(id)items
           forCategory:(NSInteger)category
                 title:(id)title
      titleDescription:(id)description;
@end

#pragma mark - Hook Settings

%hook YTSettingsSectionItemManager
- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == AutoACSection) {
        Class itemClass = %c(YTSettingsSectionItem);
        if (!itemClass) return %orig;

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

        // Sửa lỗi truy xuất Delegate: Thử nhiều key khác nhau để tránh bị nil
        id settingsVC = [self valueForKey:@"_settingsViewControllerDelegate"] 
                     ?: [self valueForKey:@"settingsViewControllerDelegate"]
                     ?: [self valueForKey:@"_delegate"];

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
    NSMutableArray *order = [%orig mutableCopy];
    if (order && ![order containsObject:@(AutoACSection)]) {
        [order insertObject:@(AutoACSection) atIndex:1];
    }
    return [order copy];
}
%end

#pragma mark - Hook Long Press (Sửa lỗi không nhận diện)

%hook YTTabBar // Hook vào class con của YouTube thay vì UITabBar thuần

- (void)layoutSubviews {
    %orig;
    
    // Sử dụng associated object hoặc tag để kiểm tra tránh add trùng
    if (!objc_getAssociatedObject(self, @selector(autoAC_handleLongPress:))) {
        
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] 
            initWithTarget:self 
            action:@selector(autoAC_handleLongPress:)];
        
        lp.minimumPressDuration = 0.5;
        lp.cancelsTouchesInView = NO; // Quan trọng: Không làm liệt các nút bấm khác
        
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

    NSLog(@"[AutoAC] ✅ LONG PRESS DETECTED");

    // Lấy Top ViewController một cách an toàn hơn
    UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AutoAC"
                                                                   message:@"Kích hoạt tính năng thành công! ✅"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    
    [topVC presentViewController:alert animated:YES completion:nil];
}
%end

#pragma mark - Fix Promo (Tham khảo từ image.png)

// Chặn các thông báo làm phiền có thể đè lên UI theo image.png
%hook YTPromoThrottleController
- (BOOL)canShowThrottledPromo { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1 { return NO; }
%end

%hook YTCommerceEventGroupHandler
- (void)addEventHandlers {}
%end
