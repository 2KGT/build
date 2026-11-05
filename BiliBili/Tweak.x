#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "BilibiliHDHeader/Bridge.h"

#pragma mark ==================================================
#pragma mark KHAI BÁO BIẾN TOÀN CỤC & HÀM HỖ TRỢ
#pragma mark ==================================================

static id _launchObserverToken = nil;
static id _bgObserverToken = nil;

// Màu sắc tương thích iOS cũ
static UIColor *BT_LabelColor() {
    if (@available(iOS 13.0, *)) return [UIColor labelColor];
    return [UIColor blackColor];
}
static UIColor *BT_RedColor() {
    if (@available(iOS 13.0, *)) return [UIColor systemRedColor];
    return [UIColor redColor];
}

// 1. Hàm hiển thị thông báo Toast (Popup nhỏ)
static void showToast(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) {
                        if (w.isKeyWindow) { keyWindow = w; break; }
                    }
                }
                if (keyWindow) break;
            }
        }
        if (!keyWindow) keyWindow = UIApplication.sharedApplication.keyWindow;
        if (!keyWindow) return;
        
        UIView *toast = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 280, 50)];
        toast.center = CGPointMake(keyWindow.bounds.size.width/2, keyWindow.bounds.size.height - 120);
        toast.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
        toast.layer.cornerRadius = 12;
        toast.clipsToBounds = YES;
        
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(toast.bounds, 10, 5)];
        label.text = msg;
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        label.font = [UIFont boldSystemFontOfSize:14];
        [toast addSubview:label];
        
        [keyWindow addSubview:toast];
        toast.alpha = 0;
        [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 1; } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.3 delay:2.0 options:0 animations:^{ toast.alpha = 0; } completion:^(BOOL finished) {
                [toast removeFromSuperview];
            }];
        }];
    });
}

// 2. Hàm xoá Cache an toàn
static void clearAppCache() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        // Xoá thư mục Caches
        NSArray *cachePaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        for (NSString *dir in cachePaths) {
            NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:nil];
            for (NSString *item in contents) {
                [fm removeItemAtPath:[dir stringByAppendingPathComponent:item] error:nil];
            }
        }
        // Xoá thư mục Tmp
        NSString *tmp = NSTemporaryDirectory();
        NSArray *tmpContents = [fm contentsOfDirectoryAtPath:tmp error:nil];
        for (NSString *item in tmpContents) {
            [fm removeItemAtPath:[tmp stringByAppendingPathComponent:item] error:nil];
        }
    });
}

// 3. Hàm ẩn Watermark
static void HideWatermarksInView(UIView *v) {
    if (!v) return;
    for (UIView *sub in v.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"Watermark"] || [cls containsString:@"LogoOverlay"] || [cls containsString:@"BrandView"]) {
            sub.hidden = YES;
            sub.alpha = 0.0;
        }
        HideWatermarksInView(sub);
    }
}

#pragma mark ==================================================
#pragma mark GIAO DIỆN CÀI ĐẶT (SETTINGS VIEW CONTROLLER)
#pragma mark ==================================================

@interface BiliTweakSettingsVC : UITableViewController
@end

@implementation BiliTweakSettingsVC

- (instancetype)init {
    if (@available(iOS 13.0, *)) {
        self = [super initWithStyle:UITableViewStyleInsetGrouped];
    } else {
        self = [super initWithStyle:UITableViewStyleGrouped];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"BiliTweak Settings";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismiss)];
}

- (void)dismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Tính năng Tweak";
    if (section == 1) return @"Bộ nhớ đệm (Cache)";
    return @"Thông tin";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 1) return 3;
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"BiliCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellID];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = BT_LabelColor();
    
    if (indexPath.section == 0) {
        cell.textLabel.text = @"Ẩn Watermark Video";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"kBT_HideWatermark"];
        [sw addTarget:self action:@selector(toggleWatermark:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } 
    else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Xoá cache khi mở app";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"kBT_ClearCacheOnLaunch"];
            [sw addTarget:self action:@selector(toggleCacheLaunch:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Xoá cache khi thoát app";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"kBT_ClearCacheOnExit"];
            [sw addTarget:self action:@selector(toggleCacheExit:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else {
            cell.textLabel.text = @"Xoá Cache Ngay";
            cell.textLabel.textColor = BT_RedColor();
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    } 
    else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Phiên bản Tweak";
            cell.detailTextLabel.text = @"1.0.0";
        } else {
            cell.textLabel.text = @"Tác giả";
            cell.detailTextLabel.text = @"2KGT";
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 2) {
        clearAppCache();
        showToast(@"Đang xoá cache ngầm...");
    }
}

- (void)toggleWatermark:(UISwitch *)sw { [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:@"kBT_HideWatermark"]; }
- (void)toggleCacheLaunch:(UISwitch *)sw { [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:@"kBT_ClearCacheOnLaunch"]; }
- (void)toggleCacheExit:(UISwitch *)sw { [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:@"kBT_ClearCacheOnExit"]; }

@end

// Hàm mở Settings
static void openSettings() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                    for (UIWindow *w in scene.windows) {
                        if (w.isKeyWindow) { keyWindow = w; break; }
                    }
                }
                if (keyWindow) break;
            }
        }
        if (!keyWindow) keyWindow = UIApplication.sharedApplication.keyWindow;
        if (!keyWindow) return;
        
        UIViewController *root = keyWindow.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        if ([root isKindOfClass:[BiliTweakSettingsVC class]]) return;
        
        BiliTweakSettingsVC *vc = [[BiliTweakSettingsVC alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        [root presentViewController:nav animated:YES completion:nil];
    });
}


#pragma mark ==================================================
#pragma mark 1. DIỆT QUẢNG CÁO MỞ APP (SPLASH ADS)
#pragma mark ==================================================

%group SplashAdsGroup
%hook BFCSplashLaunchInfo
+ (id)infoWith:(_Bool)with linkAwake:(_Bool)awake inHot:(_Bool)hot {
    return %orig(YES, awake, hot);
}
%end

%hook BStarAdSplashWindow
- (void)makeKeyAndVisible {
    NSLog(@"[BiliTweak] Chặn BStarAdSplashWindow");
}
%end

%hook PAGAppOpenAdViewController
- (void)viewDidAppear:(BOOL)animated {
    NSLog(@"[BiliTweak] Chặn PAGAppOpenAdViewController");
}
%end
%end


#pragma mark ==================================================
#pragma mark 2. CHẶN QUẢNG CÁO TRONG FEED & POPUP
#pragma mark ==================================================

%group FeedAdsGroup
%hook BiliAdManager
- (id)getSplashAdData { return nil; }
- (NSArray *)getFeedAdList { return @[]; }
- (BOOL)shouldShowPlayerAd { return NO; }
%end

%hook BiliPopupManager
- (void)showPopup:(id)popup {}
%end
%end


#pragma mark ==================================================
#pragma mark 3. MỞ KHÓA CHẤT LƯỢNG 4K & TẢI XUỐNG
#pragma mark ==================================================

%group QualityUnlockGroup
%hook BiliPlayerAPI
- (NSInteger)defaultQuality { return 120; }
- (BOOL)canDownloadQuality:(NSInteger)quality { if (quality == 120 || quality == 116) return YES; return %orig; }
%end

%hook BiliDownloadManager
- (BOOL)canDownloadQuality:(NSInteger)quality { return YES; }
%end
%end


#pragma mark ==================================================
#pragma mark 4. ẨN HÌNH MỜ (WATERMARK)
#pragma mark ==================================================

%group WatermarkGroup
%hook UIView
- (void)layoutSubviews {
    %orig;
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"kBT_HideWatermark"]) return;
    NSString *cls = NSStringFromClass([self class]);
    if ([cls containsString:@"Player"] || [cls containsString:@"Video"]) {
        HideWatermarksInView(self);
    }
}
%end
%end


#pragma mark ==================================================
#pragma mark 5. NHẤN GIỮ TAB BAR ĐỂ MỞ CÀI ĐẶT
#pragma mark ==================================================

%group UIGroup
%hook UITabBarController
- (void)viewDidLoad {
    %orig;
    static char gestureKey;
    if (objc_getAssociatedObject(self, &gestureKey)) return;
    objc_setAssociatedObject(self, &gestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(bt_openSettingsGesture:)];
    lp.minimumPressDuration = 1.0;
    lp.cancelsTouchesInView = NO; // Không chặn thao tác chuyển tab bình thường
    [self.tabBar addGestureRecognizer:lp];
}

- (void)bt_openSettingsGesture:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        openSettings();
    }
}
%end
%end


#pragma mark ==================================================
#pragma mark KHỞI TẠO HỆ THỐNG & LẮNG NGHE SỰ KIỆN APP
#pragma mark ==================================================

%ctor {
    // Đăng ký giá trị mặc định
    NSDictionary *defaults = @{
        @"kBT_ClearCacheOnLaunch": @NO,
        @"kBT_ClearCacheOnExit": @NO,
        @"kBT_HideWatermark": @YES,
    };
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    
    // Khởi tạo các Hook Groups
    %init(SplashAdsGroup);
    if (objc_getClass("BiliAdManager") || objc_getClass("BiliPopupManager")) %init(FeedAdsGroup);
    if (objc_getClass("BiliPlayerAPI") || objc_getClass("BiliDownloadManager")) %init(QualityUnlockGroup);
    %init(WatermarkGroup);
    %init(UIGroup);

    // Lắng nghe sự kiện Mở App (DidFinishLaunching)
    _launchObserverToken = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        // Đợi 1.5s để app load xong giao diện rồi mới báo Toast
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            showToast(@"BiliTweak đã hoạt động!\nNhấn giữ Tab Bar để mở Cài đặt.");
            
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"kBT_ClearCacheOnLaunch"]) {
                clearAppCache();
            }
        });
    }];

    // Lắng nghe sự kiện Thoát App (DidEnterBackground)
    _bgObserverToken = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"kBT_ClearCacheOnExit"]) {
            clearAppCache();
        }
    }];
    
    NSLog(@"[BiliTweak] Khởi tạo thành công toàn bộ hệ thống!");
}