#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#define kGlassTag 0x4C51
#define kGlassBlurName @"liquidGlassBlur"
#define kGlassSpecName @"liquidGlassSpec"
#define kGlassRimName  @"liquidGlassRim"
#define kGlassInnerName @"liquidGlassInner"
#define kGlassGrainName @"liquidGlassGrain"

// ═══════════════════════════════════════════════════════════════
//  CORE: Áp dụng hiệu ứng KÍNH LỎNG SIÊU THỰC lên 1 UIView
// ═══════════════════════════════════════════════════════════════
static void ApplyLiquidGlass(UIView *v, CGFloat radius, BOOL dark) {
    if (!v || v.tag == kGlassTag) return;
    v.tag = kGlassTag;

    // 1. NỀN KÍNH — màu trắng/đen alpha cực thấp
    v.backgroundColor = dark
        ? [UIColor colorWithWhite:0.1 alpha:0.35]
        : [UIColor colorWithWhite:1.0 alpha:0.10];

    v.layer.cornerRadius = radius;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.masksToBounds = NO;

    // Xoá lớp glass cũ nếu có
    for (CALayer *l in [v.layer.sublayers copy]) {
        if ([l.name hasPrefix:@"liquidGlass"]) [l removeFromSuperlayer];
    }
    for (UIView *s in [v.subviews copy]) {
        if ([s.restorationIdentifier isEqualToString:kGlassBlurName]) [s removeFromSuperview];
    }

    // 2. BLUR NỀN — UIVisualEffectView thay vì backdrop-filter (ổn định hơn)
    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:
            dark ? UIBlurEffectStyleSystemUltraThinMaterialDark
                 : UIBlurEffectStyleSystemUltraThinMaterialLight]];
    blur.restorationIdentifier = kGlassBlurName;
    blur.frame = v.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.layer.cornerRadius = radius;
    blur.layer.cornerCurve = kCACornerCurveContinuous;
    blur.clipsToBounds = YES;
    blur.userInteractionEnabled = NO;
    [v insertSubview:blur atIndex:0];

    // 3. SPECULAR HIGHLIGHT — gradient phản xạ ánh sáng phía trên (Fresnel)
    CAGradientLayer *spec = [CAGradientLayer layer];
    spec.name = kGlassSpecName;
    spec.frame = v.bounds;
    spec.cornerRadius = radius;
    spec.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.45].CGColor,  // đỉnh sáng
        (id)[UIColor colorWithWhite:1.0 alpha:0.05].CGColor,  // giữa
        (id)[UIColor colorWithWhite:1.0 alpha:0.00].CGColor,  // sát đáy tối
        (id)[UIColor colorWithWhite:1.0 alpha:0.18].CGColor   // đáy phản chiếu
    ];
    spec.locations = @[@0.0, @0.28, @0.92, @1.0];
    spec.startPoint = CGPointMake(0.5, 0);
    spec.endPoint   = CGPointMake(0.5, 1);
    [v.layer addSublayer:spec];

    // 4. RIM LIGHT — viền phát sáng 1px (Fresnel edge)
    CAGradientLayer *rim = [CAGradientLayer layer];
    rim.name = kGlassRimName;
    rim.frame = v.bounds;
    rim.cornerRadius = radius;
    rim.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.55].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.35].CGColor
    ];
    rim.locations = @[@0.0, @0.5, @1.0];
    rim.startPoint = CGPointMake(0, 0);
    rim.endPoint   = CGPointMake(1, 1);
    
    CAShapeLayer *rimMask = [CAShapeLayer layer];
    rimMask.path = [UIBezierPath bezierPathWithRoundedRect:v.bounds cornerRadius:radius].CGPath;
    rimMask.fillColor = [UIColor clearColor].CGColor;
    rimMask.strokeColor = [UIColor whiteColor].CGColor;
    rimMask.lineWidth = 1.2;
    rim.mask = rimMask;
    [v.layer addSublayer:rim];

    // 5. INNER SHADOW — chiều sâu bên trong
    CAShapeLayer *inner = [CAShapeLayer layer];
    inner.name = kGlassInnerName;
    UIBezierPath *outer = [UIBezierPath bezierPathWithRoundedRect:v.bounds cornerRadius:radius];
    UIBezierPath *hole  = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(v.bounds, 5, 5)
                                                        cornerRadius:MAX(radius - 5, 0)];
    [outer appendPath:hole];
    inner.path = outer.CGPath;
    inner.fillRule = kCAFillRuleEvenOdd;
    inner.fillColor = [UIColor colorWithWhite:0 alpha:0.6].CGColor;
    inner.shadowColor = [UIColor blackColor].CGColor;
    inner.shadowOpacity = 1.0;
    inner.shadowRadius = 5;
    inner.shadowOffset = CGSizeMake(0, 3);
    [v.layer addSublayer:inner];

    // 6. GRAIN / NOISE — tạo cảm giác kính thật (không hoàn toàn phẳng)
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc]
        initWithSize:CGSizeMake(120, 120)];
    UIImage *noise = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        for (int i = 0; i < 3000; i++) {
            CGFloat x = arc4random_uniform(120);
            CGFloat y = arc4random_uniform(120);
            CGFloat a = (arc4random_uniform(30) / 100.0);
            [[UIColor colorWithWhite:1.0 alpha:a] setFill];
            UIRectFill(CGRectMake(x, y, 1, 1));
        }
    }];
    UIColor *grainColor = [UIColor colorWithPatternImage:noise];
    CALayer *grain = [CALayer layer];
    grain.name = kGlassGrainName;
    grain.frame = v.bounds;
    grain.cornerRadius = radius;
    grain.backgroundColor = grainColor.CGColor;
    grain.opacity = 0.28;
    [v.layer addSublayer:grain];
}

// ═══════════════════════════════════════════════════════════════
//  HOOKS — Phủ sóng toàn bộ control
// ═══════════════════════════════════════════════════════════════

// UIButton — nút bấm phổ biến nhất
%hook UIButton
- (void)didMoveToWindow {
    %orig;
    if (self.window && !self.superview.tag == kGlassTag)
        ApplyLiquidGlass(self, 12, NO);
}
%end

// UITabBar
%hook UITabBar
- (void)didMoveToWindow {
    %orig;
    if (self.window) ApplyLiquidGlass(self, 22, YES);
}
%end

// UINavigationBar
%hook UINavigationBar
- (void)didMoveToWindow {
    %orig;
    if (self.window) ApplyLiquidGlass(self, 0, YES);
}
%end

// UIToolbar
%hook UIToolbar
- (void)didMoveToWindow {
    %orig;
    if (self.window) ApplyLiquidGlass(self, 22, YES);
}
%end

// UITableViewCell
%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    ApplyLiquidGlass(self.contentView, 14, NO);
}
%end

// UICollectionViewCell
%hook UICollectionViewCell
- (void)layoutSubviews {
    %orig;
    ApplyLiquidGlass(self.contentView, 14, NO);
}
%end

// UISwitch, UISlider, UISegmentedControl
%hook UISwitch
- (void)layoutSubviews { %orig; ApplyLiquidGlass(self, self.bounds.size.height/2, NO); }
%end

%hook UISlider
- (void)layoutSubviews { %orig; ApplyLiquidGlass(self, self.bounds.size.height/2, NO); }
%end

%hook UISegmentedControl
- (void)layoutSubviews { %orig; ApplyLiquidGlass(self, 10, NO); }
%end

// UISearchBar + UITextField
%hook UISearchBar
- (void)didMoveToWindow { %orig; if (self.window) ApplyLiquidGlass(self, 14, NO); }
%end

%hook UITextField
- (void)layoutSubviews { %orig; ApplyLiquidGlass(self, self.layer.cornerRadius ?: 10, NO); }
%end

// UIAlertController / Action Sheet
%hook UIAlertController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    for (UIView *v in self.view.subviews) {
        if ([NSStringFromClass(v.class) containsString:@"Alert"]) {
            ApplyLiquidGlass(v, 22, YES);
        }
    }
}
%end