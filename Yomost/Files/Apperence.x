// Appearance.x
#import "Headers.h"

// Khai báo các thuộc tính ẩn của UIView phục vụ cho hàm kiểm tra Dark Mode
@interface UIView (YomostAppearance)
@property (nonatomic, readonly) BOOL _mapkit_isDarkModeEnabled;
@property (nonatomic, readonly) UIViewController *_viewControllerForAncestor;
@end

// OLEDKeyboard (https://github.com/dayanch96/OledKeyboard)
static BOOL isDarkMode(UIView *view) {
    if (!view) return NO;
    if ([view respondsToSelector:@selector(_mapkit_isDarkModeEnabled)]) {
        return view._mapkit_isDarkModeEnabled;
    }
    if ([view respondsToSelector:@selector(_viewControllerForAncestor)]) {
        UIViewController *vc = view._viewControllerForAncestor;
        if (vc && [vc respondsToSelector:@selector(traitCollection)]) {
            return vc.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        }
    }
    // Lớp bọc dự phòng nếu không tìm thấy tổ tiên view controller
    if ([view respondsToSelector:@selector(traitCollection)]) {
        return view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

// ==========================================
// 1. OLED THEME CHO GIAO DIỆN (OLED BLACK)
// ==========================================
%group OLEDTheme
%hook YTColor
+ (UIColor *)black0 { return [UIColor blackColor]; }
+ (UIColor *)black1 { return [UIColor blackColor]; }
+ (UIColor *)black2 { return [UIColor blackColor]; }
+ (UIColor *)black3 { return [UIColor blackColor]; }
+ (UIColor *)black4 { return [UIColor blackColor]; }
%end

%hook YTCommonColorPalette
- (UIColor *)baseBackground { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
- (UIColor *)brandBackgroundSolid { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
- (UIColor *)brandBackgroundPrimary { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
- (UIColor *)brandBackgroundSecondary { return self.pageStyle == 1 ? [[UIColor blackColor] colorWithAlphaComponent:0.9] : %orig; }
- (UIColor *)raisedBackground { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
- (UIColor *)staticBrandBlack { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
- (UIColor *)generalBackgroundA { return self.pageStyle == 1 ? [UIColor blackColor] : %orig; }
%end

%hook YTInnerTubeCollectionViewController
- (UIColor *)backgroundColor:(NSInteger)pageStyle { return pageStyle == 1 ? [UIColor blackColor] : %orig; }
%end
%end

// ==========================================
// 2. OLED KEYBOARD (BÀN PHÍM TỐI MÀU TUYỆT ĐỐI)
// ==========================================
%group OLEDKeyboard
%hook UIKeyboard
- (void)displayLayer:(id)arg1 {
    %orig;
    self.backgroundColor = isDarkMode(self) ? [UIColor blackColor] : [UIColor clearColor];
}
%end

%hook UIPredictionViewController
- (id)_currentTextSuggestions {
    // Sửa lỗi đệ quy: Chỉ can thiệp màu khi View đã thực sự được nạp
    if ([self isViewLoaded]) {
        UIKeyboard *keyboard = [%c(UIKeyboard) activeKeyboard];
        if (isDarkMode(keyboard)) {
            self.view.backgroundColor = [UIColor blackColor];
            if (keyboard) keyboard.backgroundColor = [UIColor blackColor];
        } else {
            self.view.backgroundColor = [UIColor clearColor];
            if (keyboard) keyboard.backgroundColor = [UIColor clearColor];
        }
    }
    return %orig;
}
%end

%hook UIKeyboardDockView
- (void)layoutSubviews {
    %orig;
    self.backgroundColor = isDarkMode(self) ? [UIColor blackColor] : [UIColor clearColor];
}
%end

// Kiểm tra class name thông qua class gần nhất của UIKit để can thiệp vào private framework (Emoji, Autofill)
%hook UIInputView
- (void)layoutSubviews {
    %orig;
    if ([self isKindOfClass:NSClassFromString(@"TUIEmojiSearchInputView")] // Khung tìm kiếm Emoji
     || [self isKindOfClass:NSClassFromString(@"_SFAutoFillInputView")]) { // Khung tự động điền mật khẩu
        self.backgroundColor = isDarkMode(self) ? [UIColor blackColor] : [UIColor clearColor];
    }
}
%end

%hook UIKBVisualEffectView
- (void)layoutSubviews {
    %orig;
    if (isDarkMode(self)) {
        // Thay vì gán backgroundEffects = nil gây crash trên iOS mới, ta làm ẩn các lớp con tạo mờ hiệu quả hơn
        self.backgroundColor = [UIColor blackColor];
        @try {
            if ([self respondsToSelector:@selector(subviews)]) {
                for (UIView *subview in self.subviews) {
                    if ([subview isKindOfClass:NSClassFromString(@"UIVisualEffectView")]) {
                        subview.hidden = YES;
                    }
                }
            }
        } @catch (NSException *e) {}
    }
}
%end
%end

// ==========================================
// 3. KHỞI TẠO CÁC NHÓM HOOK (CONSTRUCTOR)
// ==========================================
%ctor {
    // Đảm bảo bọc kiểm tra an toàn macro tránh lỗi thiết lập trống
    @try {
        if (IS_ENABLED(OLEDTheme)) {
            %init(OLEDTheme);
        }
        if (IS_ENABLED(OLEDKeyboard)) {
            %init(OLEDKeyboard);
        }
    } @catch (NSException *exception) {}
}
