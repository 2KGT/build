#import <dlfcn.h>
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <Photos/Photos.h>
#import <Security/Security.h>
#import <execinfo.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>

// BuildInfo.h do build_engine.py tạo tự động (chứa version của lần build này).
// Không có file này thì tweak vẫn build bình thường, chỉ không hiện số version.
#if __has_include("BuildInfo.h")
#import "BuildInfo.h"
#endif
#ifndef TWEAK_BUILD_VERSION
#define TWEAK_BUILD_VERSION @"2.1.71"
#endif
#ifndef TWEAK_UPSTREAM_COUNT
#define TWEAK_UPSTREAM_COUNT 0
#endif
#ifndef TWEAK_UPSTREAM_INFO
#define TWEAK_UPSTREAM_INFO @""
#endif
// =1 khi bản build có YouTube X và đã bọc được công tắc (do build_engine.py ghi vào BuildInfo.h)
#ifndef TWEAK_UPSTREAM_YOUTUBEX_GATED
#define TWEAK_UPSTREAM_YOUTUBEX_GATED 0
#endif
// =1 khi bản build có NoYTPremium và đã bọc được công tắc: công tắc "No premium" điều khiển luôn cả phần của NoYTPremium
#ifndef TWEAK_UPSTREAM_NOYTPREMIUM_GATED
#define TWEAK_UPSTREAM_NOYTPREMIUM_GATED 0
#endif

#define kPrefs [NSUserDefaults standardUserDefaults]
// Chế độ an toàn tự động: app thoát bất ngờ -> lần mở sau tự tắt dần các nhóm hook rủi ro
// 0 = đầy đủ; 1 = tắt Liquid Glass gốc; 2 = tắt thêm mọi hook trình phát/nội dung; 3 = chỉ giữ menu
static NSString *AutoACT(NSString *vi);
static NSInteger gSafeLevel = 0;
static NSString *const kRunningFlagKey = @"kAutoACRunningFlag";
static NSString *const kSafeLevelKey = @"kAutoACSafeLevel";
static NSString *const kBuildIDKey = @"kAutoACBuildID";
static NSString *const kDiagKey = @"kAutoACDiag";   // công tắc chẩn đoán hệ thống ở trang (i)
// Bộ đếm chẩn đoán Shorts: YouTube có gọi "tự sang Short kế" không, và bao nhiêu phần tử đã bị AutoAC chặn
static NSInteger gAdvSeen = 0, gAdvBlocked = 0, gAdvTickArmed = 0;
static BOOL gListFilterAllowed = YES;   // tab hiện tại có được lọc danh sách không (chỉ Trang chủ)
static CFTimeInterval gListScopeLockUntil = 0;   // vừa đổi tab: giữ kết quả của chính lần đổi tab, chưa cho quét lại
static NSString *gListTabIdent = nil;
static NSInteger gFeedCellsSeen = 0;   // số ô bảng tin đã duyệt qua (hiện ở Chẩn đoán để biết bộ lọc có chạy không)
static NSInteger gDropShelf = 0, gDropPost = 0, gDropMix = 0, gDropGame = 0, gDropBanner = 0;   // số mục đã bỏ khỏi danh sách (hiện ở Chẩn đoán)
static NSString *gAdvLast = nil;
static NSMutableOrderedSet<NSString *> *gReelSeen = nil;   // mã · nhãn các nút cột phải của Shorts (hiện ở trang "i" để chẩn đoán)
static NSMutableOrderedSet<NSString *> *gOverlaySeen = nil;   // mã view thấy trong lớp phủ Shorts (để biết tên thẻ sản phẩm)
static NSMutableOrderedSet<NSString *> *gPremiumSeen;   // mã thẻ có chữ premium/music/upsell/banner đã thấy (hiện ở Chẩn đoán)

typedef id (^AutoACHookMaker)(IMP original, SEL selector);
static BOOL AutoACHook(NSString *className, NSString *selectorName, BOOL classMethod,
                       const char *prefix, AutoACHookMaker maker);

static NSString *const kCurrentBuildID = @"2.1.71";

// ── Nhật ký lỗi: ghi dấu vết và nguyên nhân crash vào Documents/AutoAC_crash.log ──
static int gTraceFD = -1;
static NSString *gPreviousTrace = nil;
static NSString *gPrevRunNote = nil;
static NSUncaughtExceptionHandler *gPrevExceptionHandler = NULL;

static void AutoACTrace(const char *msg) {
    if (gTraceFD < 0 || !msg) return;
    write(gTraceFD, msg, strlen(msg));
    write(gTraceFD, "\n", 1);
}

static void AutoACSignalHandler(int sig) {
    char head[48];
    int n = snprintf(head, sizeof(head), "CRASH signal %d\n", sig);
    if (gTraceFD >= 0) {
        write(gTraceFD, head, (size_t)n);
        void *frames[48];
        int count = backtrace(frames, 48);
        backtrace_symbols_fd(frames, count, gTraceFD);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static void AutoACExceptionHandler(NSException *e) {
    NSString *text = [NSString stringWithFormat:@"CRASH exception %@: %@\n%@", e.name, e.reason,
                      [e.callStackSymbols componentsJoinedByString:@"\n"]];
    AutoACTrace(text.UTF8String);
    if (gPrevExceptionHandler) gPrevExceptionHandler(e);
}

// Cài (hoặc cài lại) bộ bắt lỗi; YouTube có trình báo lỗi riêng và có thể ghi đè bộ của mình, nên gọi lại nhiều lần
static void AutoACInstallCrashHandlers(void) {
    NSUncaughtExceptionHandler *current = NSGetUncaughtExceptionHandler();
    if (current != &AutoACExceptionHandler) {
        gPrevExceptionHandler = current;
        NSSetUncaughtExceptionHandler(&AutoACExceptionHandler);
    }
    static char altStack[65536];
    stack_t ss; ss.ss_sp = altStack; ss.ss_size = sizeof(altStack); ss.ss_flags = 0;
    sigaltstack(&ss, NULL);
    const int sigs[] = {SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGTRAP, SIGFPE};
    for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) {
        struct sigaction sa;
        memset(&sa, 0, sizeof(sa));
        sa.sa_handler = AutoACSignalHandler;
        sa.sa_flags = SA_ONSTACK;
        sigemptyset(&sa.sa_mask);
        sigaction(sigs[i], &sa, NULL);
    }
}

static void AutoACAtExit(void) { AutoACTrace("CRASH atexit: app gọi exit()"); }

static void AutoACSetupTrace(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs.length == 0) return;
    NSString *path = [docs stringByAppendingPathComponent:@"AutoAC_crash.log"];
    gPreviousTrace = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    gTraceFD = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    AutoACInstallCrashHandlers();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
        object:nil queue:nil usingBlock:^(NSNotification *n) { AutoACTrace("MEMORY WARNING"); }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
        object:nil queue:nil usingBlock:^(NSNotification *n) { AutoACTrace("enter background"); }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:nil usingBlock:^(NSNotification *n) { AutoACTrace("active"); AutoACInstallCrashHandlers(); }];
    atexit(AutoACAtExit);
    AutoACTrace([@"start v" stringByAppendingString:TWEAK_BUILD_VERSION].UTF8String);
}
static NSString *const kAutoClearCacheKey = @"kAutoClearCache2";
static NSString *const kHideShortsKey = @"kHideShortsTab";
static NSString *const kYTXAdsKey = @"kYTXAds";                 // khoá do upstream.json đặt cho YouTube X
static NSString *const kYTXBackgroundKey = @"kYTXBackground";
// Chức năng bổ sung theo ytkace (github.com/itzzace/ytkace)
static NSString *const kLoopKey = @"kLoopVideo";                // lặp video
static NSString *const kAutoplayOffKey = @"kAutoplayOff";       // tắt tự phát video kế tiếp
static NSString *const kAskQualityKey = @"kDLAskQuality";       // hỏi chất lượng trước khi tải
static NSString *const kShareAfterKey = @"kDLShareAfter";       // mở bảng chia sẻ sau khi tải
static NSString *const kAskDestKey = @"kDLAskDest";             // hỏi nơi lưu (Ảnh / chia sẻ) trước khi tải video
static NSString *const kHidePromosKey = @"kHidePromos";         // chặn popup khuyến mãi / nâng cấp Premium (cũng là khoá công tắc của NoYTPremium trong upstream.json)
static NSString *const kShortsFullBleedKey = @"kShortsFullBleed";   // Shorts: dock trong suốt, video kéo xuống tận thanh tab (không còn dải trắng/đen)
static NSString *const kGlassTopKey = @"kGlassTop";         // kính lỏng cho thanh trên (nút tìm kiếm/thông báo, nút quay lại)
static NSString *const kGlassSheetKey = @"kGlassSheet";     // kính lỏng cho bảng chọn, hộp thoại
static NSString *const kGlassPlayerKey = @"kGlassPlayer";   // kính lỏng cho các nền mờ của trình phát
static NSString *const kHidePaidPromoKey = @"kHidePaidPromo";   // ẩn nhãn "Có quảng cáo trả phí" trên trình phát
static NSString *const kZoomFreeKey = @"kZoomUnlimited";        // phóng to video tự do bằng 2 ngón
static NSString *const kNoLaunchAnimKey = @"kNoLaunchAnim";     // bỏ hoạt ảnh logo khi mở app
static NSString *const kOpenPausedKey = @"kOpenPaused";         // mở video ở trạng thái tạm dừng
static NSString *const kStartRateKey = @"kStartRate";           // tốc độ phát khi mở video (0 = theo YouTube)
static NSString *const kDoubleTapKey = @"kDoubleTapSeconds";    // số giây tua khi chạm đúp (0 = theo YouTube)
static NSString *const kShortsLikeKey = @"kShortsHideLike";      // ẩn nút Thích của Shorts
static NSString *const kShortsCommentKey = @"kShortsHideComment";
static NSString *const kShortsShareKey = @"kShortsHideShare";
static NSString *const kShortsSaveKey = @"kShortsHideSave";
static NSString *const kShortsRemixKey = @"kShortsHideRemix";
static NSString *const kShortsSoundKey = @"kShortsHideSound";
static NSString *const kShortsPauseCardKey = @"kShortsHidePauseCard";
static NSString *const kHideCommunityKey = @"kHideCommunityPosts";
static NSString *const kHideMixesKey = @"kHideMixes";
static NSString *const kHideShopTagKey = @"kHideShopTag";   // ẩn thẻ sản phẩm / giỏ hàng trong Shorts (chỉ lớp phủ của Short đang xem)
static NSString *const kHideGamesKey = @"kHideGames";   // ẩn mục chơi game (Playables) khỏi trang chủ
static NSString *const kHideShortsShelfKey = @"kHideShortsShelf";   // ẩn các hàng video Short trong trang chủ
static NSString *const kSponsorKey = @"kSponsorBlock";          // tự bỏ qua đoạn nhúng (SponsorBlock)
static NSString *const kSponsorCatsKey = @"kSponsorCategories"; // danh sách loại đoạn cần bỏ qua
static NSString *const kSponsorAlertKey = @"kSponsorAlert";     // hiện thông báo khi bỏ qua
static NSString *const kNoAutoplayKey = @"kNoAutoplay";   // không tự phát video khi mở (trang chủ và khi chọn video)
static NSString *const kPlayFixKey = @"kPlayFix";   // tự thử lại khi phát lỗi "Đã xảy ra lỗi" (từ YTKACE Playback Fix)
static NSString *const kShortsNoLoopKey = @"kShortsNoLoop";         // Short phát hết không lặp lại
static NSString *const kShortsNoScrollKey = @"kShortsNoScroll";       // chặn tự cuộn sang Short kế
static NSString *const kPlayerSpeedBtnKey = @"kPlayerSpeedBtn";   // nút tốc độ dưới bánh răng
static NSString *const kPlayerFloatKey = @"kPlayerFloatBtn";    // nút tải bằng icon trong trình phát (video)
static NSString *const kPlayerPiPKey = @"kPlayerPiPBtn";         // nút PiP trong trình phát
static NSString *const kPlayerSleepBtnKey = @"kPlayerSleepBtn";   // nút hẹn giờ ngủ trong trình phát
static NSString *const kPlayerExternalKey = @"kPlayerExternalBtn";   // nút phát bằng trình phát ngoài trong trình phát
static NSString *const kPlayerQualityKey = @"kPlayerQualityBtn";   // nút chọn chất lượng video trong trình phát (mặc định tắt: kéo vào ở Tuỳ chỉnh Overlay)
static NSString *const kPlayerLoopKey = @"kPlayerLoopBtn";         // nút lặp video trong trình phát (mặc định tắt)
static NSString *const kOverlayTopKey = @"kOverlayTop";         // Tuỳ chỉnh Overlay: mã các nút ở hàng trên (dưới nút bánh răng), thứ tự trái → phải
static NSString *const kOverlayBottomKey = @"kOverlayBottom";   // Tuỳ chỉnh Overlay: mã các nút ở hàng dưới (cạnh nút toàn màn hình), thứ tự trái → phải
static NSString *const kPlayerButtonKey = @"kPlayerButton";     // nút AutoAC ngay trên trình phát

#pragma mark - Interfaces (khai báo tối thiểu, không phụ thuộc YouTubeHeader)

@interface YTCommerceEventGroupHandler : NSObject
@end

// Thanh tab dưới cùng của YouTube 21.x
@interface YTPivotBarView : UIView
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

#pragma mark - Liquid Glass (iOS 26 / 27) có dự phòng cho iOS cũ

// Gọi qua runtime nên build vẫn chạy với mọi SDK; máy iOS < 26 tự dùng kính mờ thường.
static BOOL AutoACGlassAvailable(void) {
    static BOOL available = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        available = NSClassFromString(@"UIGlassEffect") != Nil;
    });
    return available;
}

// Tạo lớp nền kính bo góc. Trên iOS 26+: UIGlassEffect + cornerConfiguration (bo tối đa `radius`).
static UIVisualEffectView *AutoACMakeGlass(CGFloat radius) {
    UIVisualEffectView *view = nil;
    if (AutoACGlassAvailable()) {
        id glass = ((id (*)(Class, SEL, NSInteger))objc_msgSend)(
            NSClassFromString(@"UIGlassEffect"), NSSelectorFromString(@"effectWithStyle:"), 0);
        if ([glass isKindOfClass:UIVisualEffect.class]) {
            view = [[UIVisualEffectView alloc] initWithEffect:(UIVisualEffect *)glass];
            // Bo góc kiểu iOS 26 nếu có; không có thì bo bằng layer như kính mờ thường
            BOOL rounded = NO;
            Class config = NSClassFromString(@"UICornerConfiguration");
            SEL capsule = NSSelectorFromString(@"capsuleConfigurationWithMaximumRadius:");
            if (config && [config respondsToSelector:capsule]) {
                id value = ((id (*)(Class, SEL, CGFloat))objc_msgSend)(config, capsule, radius);
                @try { [view setValue:value forKey:@"cornerConfiguration"]; rounded = YES; } @catch (NSException *e) {}
            }
            if (!rounded) {
                view.layer.cornerRadius = radius;
                view.layer.cornerCurve = kCACornerCurveContinuous;
                view.clipsToBounds = YES;
            }
        }
    }
    if (!view) {
        view = [[UIVisualEffectView alloc]
            initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        view.layer.cornerRadius = radius;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.clipsToBounds = YES;
    }
    view.translatesAutoresizingMaskIntoConstraints = NO;
    return view;
}

// Kính tự có bóng và viền sáng, nên bỏ bóng phụ để không lộ xuyên qua lớp kính trong suốt
static void AutoACStyleShadow(UIView *container, float opacity, CGFloat radius, CGSize offset) {
    container.layer.shadowColor = UIColor.blackColor.CGColor;
    container.layer.shadowOpacity = AutoACGlassAvailable() ? 0 : opacity;
    container.layer.shadowRadius = radius;
    container.layer.shadowOffset = offset;
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

// Chỉ xoá tệp cache cũ (quá 24 giờ), bỏ qua mọi thứ liên quan đăng nhập và cơ sở dữ liệu đang dùng.
// Xoá sạch cả Caches/tmp khi app đang chạy từng làm YouTube thoát và mất đăng nhập.
// Thư mục tải xuống đang dùng (đang tải, đang ghép, đang mở bảng chia sẻ): tuyệt đối không dọn
static NSString *gHeldDir = nil;

static BOOL AutoACIsProtectedCachePath(NSString *path) {
    NSString *p = path.lowercaseString;
    // Chỉ giữ tệp đăng nhập và cơ sở dữ liệu đang mở. Không giữ "webkit"/"session": đó là phần lớn dung lượng cache thật
    for (NSString *word in @[@"sso", @"auth", @"token", @"cookie", @"account", @"identity", @"keychain", @"credential",
                             @"firebase", @"installations", @"gtm", @".sqlite", @".db", @"-wal", @"-shm", @".plist"]) {
        if ([p containsString:word]) return YES;
    }
    return NO;
}

// Tệp do chức năng tải xuống tạo ra (tmp/AutoAC-<UUID>/...) mà không còn được dùng
static BOOL AutoACIsStaleDownloadPath(NSString *path) {
    if ([path rangeOfString:@"/AutoAC-"].location == NSNotFound) return NO;
    if (gHeldDir.length > 0 && [path hasPrefix:gHeldDir]) return NO;
    return YES;
}

// Danh sách tệp cũ có thể xoá (dùng chung cho việc đo và việc xoá để hai con số luôn khớp)
static NSArray<NSURL *> *AutoACRemovableFiles(NSString *dir, NSTimeInterval minAge) {
    if (dir.length == 0) return @[];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:-minAge];
    NSDirectoryEnumerator *e = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:dir]
                        includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLContentModificationDateKey]
                                           options:0 errorHandler:^BOOL(NSURL *u, NSError *err) { return YES; }];
    NSMutableArray<NSURL *> *old = [NSMutableArray array];
    for (NSURL *url in e) {
        NSNumber *isFile = nil; NSDate *date = nil;
        [url getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil];
        [url getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
        if (!isFile.boolValue) continue;
        if (gHeldDir.length > 0 && [url.path hasPrefix:gHeldDir]) continue;
        if (AutoACIsStaleDownloadPath(url.path)) { [old addObject:url]; continue; }   // tệp tải xuống bỏ lại: dọn ngay, không chờ quá hạn
        if (!date || [date compare:limit] != NSOrderedAscending) continue;
        if (AutoACIsProtectedCachePath(url.path)) continue;
        [old addObject:url];
    }
    return old;
}

static unsigned long long AutoACFileSize(NSURL *url) {
    NSNumber *size = nil;
    [url getResourceValue:&size forKey:NSURLTotalFileAllocatedSizeKey error:nil];
    if (!size) [url getResourceValue:&size forKey:NSURLFileAllocatedSizeKey error:nil];
    return size.unsignedLongLongValue;
}

// Xoá các tệp cũ trong `dir`, trả về số byte đã giải phóng
static unsigned long long AutoACRemoveContents(NSString *dir, NSTimeInterval minAge) {
    unsigned long long freed = 0;
    for (NSURL *url in AutoACRemovableFiles(dir, minAge)) {
        unsigned long long size = AutoACFileSize(url);
        if ([NSFileManager.defaultManager removeItemAtURL:url error:nil]) freed += size;
    }
    return freed;
}

// Dọn Library/Caches và tmp của app. Không đụng Documents, Preferences, tải xuống.
// Trả về số byte đã giải phóng.
// Bấm tay: dọn mọi tệp cache không còn dùng (quá 90 giây); tự động: chỉ tệp quá 24 giờ
static const NSTimeInterval kManualCleanAge = 90;
static const NSTimeInterval kAutoCleanAge = 1800;   // tự động: tệp không đụng tới quá 30 phút

// Xoá thư mục rỗng sót lại sau khi dọn (từ trong ra ngoài), không đụng thư mục gốc
static void AutoACPruneEmptyDirs(NSString *root) {
    if (root.length == 0) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *dirs = [NSMutableArray array];
    for (NSString *rel in [fm enumeratorAtPath:root]) {
        NSString *full = [root stringByAppendingPathComponent:rel];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) [dirs addObject:full];
    }
    for (NSString *d in [dirs reverseObjectEnumerator]) {
        if (gHeldDir.length > 0 && [d hasPrefix:gHeldDir]) continue;
        if ([fm contentsOfDirectoryAtPath:d error:nil].count == 0) [fm removeItemAtPath:d error:nil];
    }
}

static unsigned long long AutoACClearCache(BOOL manual) {
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    unsigned long long freed = 0;
    for (NSString *d in @[caches ?: @"", NSTemporaryDirectory() ?: @""]) {
        freed += AutoACRemoveContents(d, manual ? kManualCleanAge : kAutoCleanAge);
        AutoACPruneEmptyDirs(d);
    }
    // Bộ nhớ đệm mạng của hệ thống (Cache.db, fsCachedData): xoá bằng API chính thức để không hỏng cơ sở dữ liệu đang mở
    // Chỉ khi bấm tay: dọn tự động chạy ngay sau khi mở app, xoá cache mạng lúc đó làm ảnh bìa và dữ liệu trang chủ
    // phải tải lại nên trang chủ bị trắng một lúc
    if (manual) {
        NSURLCache *shared = NSURLCache.sharedURLCache;
        NSUInteger before = shared.currentDiskUsage;
        [shared removeAllCachedResponses];
        NSUInteger after = shared.currentDiskUsage;
        if (before > after) freed += (before - after);
    }
    return freed;
}

#pragma mark - Hub kết quả (viên thuốc 1 dòng)

static __weak UIView *gHub = nil;

// Màu nhấn cho chữ "Mặc định" của tốc độ (thông báo và bánh xe) và icon đi kèm: xanh đậm ở nền sáng, xanh trời sáng ở nền tối,
// để không chìm vào phản chiếu của kính lỏng như xanh hệ thống
static UIColor *AutoACSpeedAccent(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.49 green:0.76 blue:1.0 alpha:1]
            : [UIColor colorWithRed:0.04 green:0.31 blue:0.84 alpha:1];
    }];
}

static void AutoACShowHub(NSString *symbol, UIColor *tint, NSString *text,
                          NSString *suffix, NSTimeInterval duration) {
    UIWindow *window = AutoACKeyWindow();
    if (!window) return;

    [gHub removeFromSuperview];

    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.userInteractionEnabled = NO;
    AutoACStyleShadow(container, 0.14, 8, CGSizeMake(0, 3));

    UIVisualEffectView *blur = AutoACMakeGlass(15);
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
            initWithString:@"  ·  "
                attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightRegular],
                             NSForegroundColorAttributeName: UIColor.secondaryLabelColor}]];
        // "Mặc định" (về tốc độ gốc): màu xanh, đậm và cùng cỡ với chữ chính ("Tốc độ"); phần phụ khác giữ kiểu nhỏ, mờ
        BOOL emphasized = [suffix isEqualToString:AutoACT(@"Mặc định")];
        NSShadow *glow = [NSShadow new];   // bóng mờ rất nhẹ giữ chữ rõ trên nền video sáng
        glow.shadowColor = [UIColor colorWithWhite:0 alpha:0.30];
        glow.shadowOffset = CGSizeZero;
        glow.shadowBlurRadius = 2.5;
        if (emphasized) icon.tintColor = AutoACSpeedAccent();   // icon cùng màu với chữ
        [attributed appendAttributedString:[[NSAttributedString alloc]
            initWithString:suffix
                attributes:emphasized
                    ? @{NSFontAttributeName: [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold],
                        NSForegroundColorAttributeName: AutoACSpeedAccent(),
                        NSShadowAttributeName: glow}
                    : @{NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightRegular],
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
        NSString *text = [NSString stringWithFormat:AutoACT(@"Đã dọn %@"),
                          [formatter stringFromByteCount:(long long)bytes]];
        AutoACShowHub(@"sparkles", UIColor.systemYellowColor, text, tag, 2.2);
    } else {
        AutoACShowHub(@"checkmark.circle.fill", UIColor.systemGreenColor,
                      AutoACT(@"Cache đã sạch"), tag, 2.2);
    }
}

static BOOL gCleaning = NO;

// Dọn ở luồng nền, xong hiện hub trên luồng chính
static void AutoACRunCleanup(BOOL manual) {
    if (gCleaning) return;
    gCleaning = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        unsigned long long freed = AutoACClearCache(manual);
        dispatch_async(dispatch_get_main_queue(), ^{
            gCleaning = NO;
            AutoACShowCacheHub(freed);
        });
    });
}

#pragma mark - Menu mini (kiểu popover chọn mô hình)

static __weak UIView *gMenu = nil;

// ── Hiệu ứng nổi lên dùng chung (giống nút tốc độ): thẻ bung ra từ điểm chạm/biểu tượng vừa bấm ──
static CGPoint gPopAnchor;
static CFTimeInterval gPopAnchorStamp = 0;
static void AutoACSetPopAnchor(CGPoint windowPoint) { gPopAnchor = windowPoint; gPopAnchorStamp = CACurrentMediaTime(); }
static void AutoACSetPopAnchorFromView(UIView *v) {
    UIWindow *w = v.window;
    if (!v || !w) return;
    AutoACSetPopAnchor([v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds)) toView:w]);
}
// Hướng chuyển cảnh giữa menu và bảng con: +1 đi tới (trượt sang trái, bảng mới trượt vào từ phải), -1 quay lại
static int gNavDir = 0;
static CFTimeInterval gNavStamp = 0, gDismissStamp = 0;
static BOOL AutoACNavActive(void) { return NO; }   // một kiểu chuyển duy nhất: nổi lên, bật nhẹ (không còn trượt ngang)

// Lò xo êm kiểu iOS (như ứng dụng Cài đặt): không nảy, giảm tốc mượt, cho phép ngắt giữa chừng
static void AutoACSmooth(NSTimeInterval duration, CGFloat damping, void (^anim)(void), void (^done)(BOOL)) {
    [UIView animateWithDuration:duration delay:0 usingSpringWithDamping:damping initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:anim completion:done];
}

// Hiệu ứng chung của toàn hệ thống: nổi lên và bật nhẹ
static void AutoACBounce(void (^anim)(void), void (^done)(BOOL)) {
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.74 initialSpringVelocity:0.55
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:anim completion:done];
}

static void AutoACPopIn(UIView *card, UIView *backdrop) {
    CGPoint c = card.center;
    CGFloat w = CGRectGetWidth(backdrop.bounds);
    if (AutoACNavActive()) {   // đi tới / quay lại: trượt ngang như đẩy trang trong Cài đặt
        CGFloat dx = gNavDir > 0 ? w * 0.18 : -w * 0.12;
        backdrop.alpha = 0;
        card.alpha = 0;
        card.transform = CGAffineTransformMakeTranslation(dx, 0);
        AutoACSmooth(0.42, 1.0, ^{ backdrop.alpha = 1; card.alpha = 1; card.transform = CGAffineTransformIdentity; }, nil);
        return;
    }
    BOOL anchored = gPopAnchorStamp > 0 && CACurrentMediaTime() - gPopAnchorStamp < 2.0;
    CGPoint a = anchored ? gPopAnchor : CGPointMake(c.x, c.y + CGRectGetHeight(card.bounds) * 0.12);
    CGFloat scale = anchored ? 0.2 : 0.9;
    gPopAnchorStamp = 0;
    backdrop.alpha = 0;
    card.alpha = 0;
    card.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale), CGAffineTransformMakeTranslation(a.x - c.x, a.y - c.y));
    AutoACBounce(^{ backdrop.alpha = 1; card.alpha = 1; card.transform = CGAffineTransformIdentity; }, nil);
}

static void AutoACDismissMenu(void) {
    UIView *backdrop = gMenu;
    if (!backdrop) return;
    gMenu = nil;
    gDismissStamp = CACurrentMediaTime();
    backdrop.userInteractionEnabled = NO;
    // Chạy ở vòng lặp kế để biết có bảng con nào mở ngay sau đó không (khi đó menu trượt sang trái nhường chỗ)
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL forward = AutoACNavActive() && gNavDir > 0;
        CGFloat w = CGRectGetWidth(backdrop.bounds);
        AutoACSmooth(forward ? 0.3 : 0.28, 1.0, ^{
            backdrop.alpha = 0;
            for (UIView *v in backdrop.subviews)
                v.transform = forward ? CGAffineTransformMakeTranslation(-w * 0.12, 0) : CGAffineTransformMakeScale(0.94, 0.94);
        }, ^(BOOL finished) { [backdrop removeFromSuperview]; });
    });
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

// ── Ẩn tab Shorts (tuỳ chọn, mặc định tắt) ──────────────────────────────

static const char kAutoACHiddenKey = 0;

// Tìm view của tab "Shorts" bên trong thanh tab (nhãn trợ năng bắt đầu bằng "Shorts")
static void AutoACCollectShortsViews(UIView *view, NSInteger depth, CGFloat barWidth,
                                     NSMutableArray<UIView *> *out) {
    if (depth > 4) return;
    for (UIView *sub in view.subviews) {
        NSString *label = sub.accessibilityLabel;
        if (label.length > 0 && [label hasPrefix:@"Shorts"] && CGRectGetWidth(sub.frame) < barWidth * 0.5) {
            [out addObject:sub];
            continue;
        }
        AutoACCollectShortsViews(sub, depth + 1, barWidth, out);
    }
}

static BOOL gShortsEverHidden = NO;
static void AutoACApplyShortsPreference(UIView *bar) {
    BOOL hide = [kPrefs boolForKey:kHideShortsKey];
    if (hide) gShortsEverHidden = YES;
    else if (!gShortsEverHidden) return;   // chưa từng ẩn thì khỏi duyệt cây view ở mỗi lần cuộn
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    AutoACCollectShortsViews(bar, 0, CGRectGetWidth(bar.bounds), found);

    for (UIView *v in found) {
        if (hide) {
            v.hidden = YES;
            objc_setAssociatedObject(v, &kAutoACHiddenKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (objc_getAssociatedObject(v, &kAutoACHiddenKey)) {
            v.hidden = NO;   // chỉ bỏ ẩn những view do chính tweak đã ẩn
            objc_setAssociatedObject(v, &kAutoACHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    if (!hide || found.count == 0) return;

    // Chia đều lại chỗ cho các tab còn lại (bỏ qua nếu thanh tab tự sắp xếp bằng stack view)
    UIView *container = found.firstObject.superview;
    if (!container || [container isKindOfClass:UIStackView.class]) return;
    CGRect ref = found.firstObject.frame;
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *sibling in container.subviews) {
        if (sibling.isHidden) continue;
        if (fabs(CGRectGetWidth(sibling.frame) - CGRectGetWidth(ref)) < 2 &&
            fabs(CGRectGetMinY(sibling.frame) - CGRectGetMinY(ref)) < 2) {
            [items addObject:sibling];
        }
    }
    if (items.count < 2) return;
    [items sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return CGRectGetMinX(a.frame) < CGRectGetMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending;
    }];
    CGFloat slot = CGRectGetWidth(container.bounds) / items.count;
    for (NSUInteger i = 0; i < items.count; i++) {
        UIView *item = items[i];
        item.frame = CGRectMake(i * slot, CGRectGetMinY(item.frame), slot, CGRectGetHeight(item.frame));
    }
}

static void AutoACFindViews(UIView *root, NSString *className, NSMutableArray<UIView *> *out) {
    if ([NSStringFromClass(root.class) isEqualToString:className]) {
        [out addObject:root];
        return;
    }
    for (UIView *sub in root.subviews) AutoACFindViews(sub, className, out);
}

// Bắt thanh tab bố trí lại ngay khi người dùng bật/tắt công tắc
static void AutoACRelayoutPivotBars(void) {
    UIWindow *window = AutoACKeyWindow();
    if (!window) return;
    NSMutableArray<UIView *> *bars = [NSMutableArray array];
    AutoACFindViews(window, @"YTPivotBarView", bars);
    for (UIView *bar in bars) {
        [bar setNeedsLayout];
        [bar layoutIfNeeded];
    }
}

// ── Thành phần dựng menu ─────────────────────────────────────────────────


static const CGFloat kMenuMaxWidth = 560;   // khung menu rộng tối đa, luôn căn giữa ở cả hai chiều màn hình

// Bề rộng khung tính theo cửa sổ thật lúc mở (tối đa kMenuMaxWidth, cách mép 16pt) và tự co dãn lại khi xoay màn hình
static void AutoACPinCardWidth(UIView *card, UIWindow *window) {
    NSLayoutConstraint *wc = [card.widthAnchor constraintEqualToConstant:MAX(240, MIN(kMenuMaxWidth, CGRectGetWidth(window.bounds) - 32))];
    wc.active = YES;
    __weak UIWindow *weakWindow = window;
    __weak NSLayoutConstraint *weakWc = wc;
    __block id token = nil;
    token = [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil
                                                              queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        UIWindow *w = weakWindow; NSLayoutConstraint *c = weakWc;
        if (!w || !c || !card.superview) { [[NSNotificationCenter defaultCenter] removeObserver:token]; return; }
        c.constant = MAX(240, MIN(kMenuMaxWidth, CGRectGetWidth(w.bounds) - 32));
    }];
}


// Dung lượng cache hiện tại (byte): Library/Caches + tmp
// Dung lượng sẽ được giải phóng khi bấm "Dọn cache ngay" (đúng bằng số hub báo sau khi dọn)
static unsigned long long AutoACCacheRemovableNow(void) {
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    unsigned long long total = 0;
    for (NSString *d in @[caches ?: @"", NSTemporaryDirectory() ?: @""]) {
        for (NSURL *url in AutoACRemovableFiles(d, kManualCleanAge)) total += AutoACFileSize(url);
    }
    return total;
}

static unsigned long long AutoACCacheSizeNow(void) {
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    return AutoACDirectorySize(caches) + AutoACDirectorySize(NSTemporaryDirectory());
}

// Báo cáo nơi dung lượng đang nằm (chỉ đọc, không xoá gì): để biết 1,5 GB còn lại thật sự ở đâu
static NSString *gStorageReport = nil;

static NSString *AutoACFormatBytes(unsigned long long bytes);

// Liệt kê mục lớn; mục nào từ 100 MB trở lên thì liệt kê thêm một cấp con để thấy đúng thư mục gây nặng
static void AutoACCollectStorage(NSString *root, NSString *label, int depth, NSMutableArray<NSArray *> *rows) {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *name in [fm contentsOfDirectoryAtPath:root error:nil]) {
        NSString *full = [root stringByAppendingPathComponent:name];
        unsigned long long size = AutoACDirectorySize(full);
        if (size < 20ULL * 1024 * 1024) continue;
        NSString *shown = [label stringByAppendingPathComponent:name];
        [rows addObject:@[shown, @(size)]];
        if (depth < 2 && size >= 100ULL * 1024 * 1024) AutoACCollectStorage(full, shown, depth + 1, rows);
    }
}

static NSString *AutoACBuildStorageReport(void) {
    NSString *home = NSHomeDirectory();
    NSMutableArray<NSArray *> *rows = [NSMutableArray array];
    for (NSString *base in @[@"Documents", @"Library/Caches", @"Library/Application Support", @"Library/WebKit", @"Library/Saved Application State", @"tmp"]) {
        AutoACCollectStorage([home stringByAppendingPathComponent:base], base, 1, rows);
    }
    [rows sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [b[1] compare:a[1]]; }];
    NSMutableString *out = [NSMutableString stringWithFormat:@"%@  %@\n", AutoACFormatBytes(AutoACDirectorySize(home)), @"(tổng / total)"];
    NSUInteger n = 0;
    for (NSArray *r in rows) {
        if (n++ >= 14) break;
        [out appendFormat:@"%@  %@\n", AutoACFormatBytes([r[1] unsignedLongLongValue]), r[0]];
    }
    return out;
}

// Tính báo cáo ở luồng nền rồi gọi `done` trên luồng chính
static void AutoACRefreshStorageReportForce(BOOL force, void (^done)(void)) {
    static CFTimeInterval lastAt = 0;
    if (!force && gStorageReport && CACurrentMediaTime() - lastAt < 60) { if (done) done(); return; }
    lastAt = CACurrentMediaTime();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *r = AutoACBuildStorageReport();
        dispatch_async(dispatch_get_main_queue(), ^{ gStorageReport = r; if (done) done(); });
    });
}

static void AutoACRefreshStorageReport(void (^done)(void)) { AutoACRefreshStorageReportForce(NO, done); }

static NSString *AutoACFormatBytes(unsigned long long bytes) {
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    formatter.allowsNonnumericFormatting = NO;
    return [formatter stringFromByteCount:(long long)bytes];
}

// Viên thuốc nhỏ: chữ màu + nền cùng màu nhạt
static UIView *AutoACPill(NSString *text, UIColor *color, CGFloat fontSize, CGFloat hPad, CGFloat vPad) {
    UIView *pill = [[UIView alloc] init];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [color colorWithAlphaComponent:0.16];
    pill.layer.cornerRadius = fontSize / 2 + vPad + 2;
    pill.layer.cornerCurve = kCACornerCurveContinuous;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
    label.textColor = color;
    [pill addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:pill.topAnchor constant:vPad],
        [label.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-vPad],
        [label.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:hPad],
        [label.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-hPad],
    ]];
    return pill;
}

// Ô biểu tượng bo góc đặc màu (giống Cài đặt của iOS)
static UIView *AutoACIconTile(NSString *symbol, UIColor *color) {
    UIView *tile = [[UIView alloc] init];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    tile.backgroundColor = color;
    tile.layer.cornerRadius = 8;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    tile.userInteractionEnabled = NO;

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:symbol withConfiguration:cfg]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeCenter;
    [tile addSubview:icon];

    [NSLayoutConstraint activateConstraints:@[
        [tile.widthAnchor constraintEqualToConstant:30],
        [tile.heightAnchor constraintEqualToConstant:30],
        [icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
    ]];
    return tile;
}

static UIView *AutoACSeparator(void) {
    UIView *wrap = [[UIView alloc] init];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *line = [[UIView alloc] init];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = [UIColor.separatorColor colorWithAlphaComponent:0.6];
    [wrap addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [wrap.heightAnchor constraintEqualToConstant:0.5],
        [line.topAnchor constraintEqualToAnchor:wrap.topAnchor],
        [line.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
        [line.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:52],
        [line.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-10],
    ]];
    return wrap;
}

#pragma mark - Phiên bản & trạng thái dùng chung

static __weak id gPlayerVC = nil;            // YTPlayerViewController đang phát (do hook gán)
static NSDate *gSleepEnd = nil;
static NSUInteger gSleepToken = 0;
static BOOL gDownloading = NO;
static BOOL gDLPaused = NO, gDLCancelled = NO;   // tạm dừng / huỷ tải (điều khiển từ trang Thông tin)
static double gDLFraction = 0;
static NSString *gDLLabel = nil;
static NSString *gDLName = nil;
static BOOL gToPhotos = NO;                  // lần tải hiện tại lưu thẳng vào Ảnh

static NSString *gVideoIDOverride = nil;     // ID video của Shorts đang chọn (Shorts không đi qua gPlayerVC)

static NSString *AutoACCurrentVideoID(void) {
    if (gVideoIDOverride.length > 0) return gVideoIDOverride;
    id player = gPlayerVC;
    SEL getter = NSSelectorFromString(@"currentVideoID");
    if (!player || ![player respondsToSelector:getter]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(player, getter);
    return [value isKindOfClass:NSString.class] && [(NSString *)value length] > 0 ? value : nil;
}

static UIViewController *AutoACTopViewController(void) {
    UIViewController *vc = AutoACKeyWindow().rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

// Bảng chọn dạng action sheet; `pick` nhận chỉ số lựa chọn
static UILabel *AutoACLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color);

// Bảng chọn nhỏ gọn kiểu kính lỏng, cùng phong cách menu logo (thay cho bảng hành động mặc định của hệ thống)
static NSInteger gSheetSelected = -1;   // dòng đang chọn: tô màu chữ thay cho dấu ✓
static void AutoACPresentSheet(NSString *title, NSString *message, NSArray<NSString *> *options,
                               void (^pick)(NSInteger index)) {
    UIWindow *window = AutoACKeyWindow();
    if (!window) return;
    NSInteger selectedRow = gSheetSelected;
    gSheetSelected = -1;

    UIButton *backdrop = [UIButton buttonWithType:UIButtonTypeCustom];
    backdrop.frame = window.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    AutoACStyleShadow(card, 0.22, 20, CGSizeMake(0, 8));
    UIVisualEffectView *blur = AutoACMakeGlass(26);
    [card addSubview:blur];

    __weak UIButton *weakBackdrop = backdrop;
    __weak UIView *weakCard = card;
    void (^close)(void (^)(void)) = ^(void (^after)(void)) {
        AutoACSmooth(0.26, 1.0, ^{
            weakBackdrop.alpha = 0;
            weakCard.alpha = 0;
            weakCard.transform = CGAffineTransformMakeScale(0.94, 0.94);
        }, ^(BOOL finished) {
            [weakBackdrop removeFromSuperview];
            if (after) after();
        });
    };
    [backdrop addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { close(nil); }]
       forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    if (title.length) {
        UILabel *t = AutoACLabel(title, 15, UIFontWeightSemibold, UIColor.labelColor);
        t.textAlignment = NSTextAlignmentCenter;
        [stack addArrangedSubview:t];
        [stack setCustomSpacing:message.length ? 2 : 8 afterView:t];
    }
    if (message.length) {
        UILabel *m = AutoACLabel(message, 12, UIFontWeightRegular, UIColor.secondaryLabelColor);
        m.textAlignment = NSTextAlignmentCenter;
        m.numberOfLines = 0;
        [stack addArrangedSubview:m];
        [stack setCustomSpacing:8 afterView:m];
    }
    void (^addRow)(NSString *, UIColor *, UIFontWeight, void (^)(void)) = ^(NSString *name, UIColor *color, UIFontWeight weight, void (^tap)(void)) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.translatesAutoresizingMaskIntoConstraints = NO;
        [b setTitle:name forState:UIControlStateNormal];
        [b setTitleColor:color forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:16 weight:weight];
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.titleLabel.minimumScaleFactor = 0.8;
        b.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.08];
        b.layer.cornerRadius = 14;
        b.layer.cornerCurve = kCACornerCurveContinuous;
        [b.heightAnchor constraintEqualToConstant:46].active = YES;
        [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { tap(); }]
    forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:b];
    };
    [options enumerateObjectsUsingBlock:^(NSString *name, NSUInteger idx, BOOL *stop) {
        addRow(name, (NSInteger)idx == selectedRow ? UIColor.systemBlueColor : UIColor.labelColor, (NSInteger)idx == selectedRow ? UIFontWeightBold : UIFontWeightMedium, ^{
            close(^{ if (pick) pick((NSInteger)idx); });
        });
    }];
    addRow(AutoACT(@"Huỷ"), UIColor.systemBlueColor, UIFontWeightSemibold, ^{ close(nil); });

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = NO;
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [scroll addSubview:stack];
    [blur.contentView addSubview:scroll];
    [backdrop addSubview:card];
    [window addSubview:backdrop];

    NSLayoutConstraint *fit = [scroll.heightAnchor constraintEqualToAnchor:stack.heightAnchor constant:24];
    fit.priority = UILayoutPriorityDefaultHigh;
    AutoACPinCardWidth(card, window);
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:backdrop.centerXAnchor],
        [card.widthAnchor constraintLessThanOrEqualToConstant:400],
        [card.bottomAnchor constraintEqualToAnchor:backdrop.safeAreaLayoutGuide.bottomAnchor constant:-14],
        [card.topAnchor constraintGreaterThanOrEqualToAnchor:backdrop.safeAreaLayoutGuide.topAnchor constant:40],
        [blur.topAnchor constraintEqualToAnchor:card.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:blur.contentView.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:blur.contentView.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor],
        fit,
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-12],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-24],
    ]];
    [window layoutIfNeeded];
    AutoACPopIn(card, backdrop);
}


#pragma mark - Hẹn giờ ngủ

static void AutoACRefreshSleepButton(void);   // đổi biểu tượng nút hẹn giờ trong trình phát (định nghĩa cạnh các nút công cụ)
static double AutoACPlayerDouble(id player, NSArray<NSString *> *names);

// Chế độ "Cuối video" (giống hẹn giờ gốc của YouTube): dừng đúng lúc video hiện tại hết, không tự phát video kế
static BOOL gSleepAtEnd = NO;
static NSString *gSleepAtEndVideo = nil;
static BOOL AutoACSleepActive(void) { return gSleepEnd != nil || gSleepAtEnd; }

static void AutoACSleepEndFinish(NSUInteger token) {
    if (token != gSleepToken || !gSleepAtEnd) return;
    gSleepAtEnd = NO;
    gSleepAtEndVideo = nil;
    AutoACRefreshSleepButton();
    id player = gPlayerVC;
    SEL pause = NSSelectorFromString(@"pause");
    if ([player respondsToSelector:pause]) ((void (*)(id, SEL))objc_msgSend)(player, pause);
    AutoACShowHub(@"pause.circle.fill", UIColor.systemIndigoColor, AutoACT(@"Đã tạm dừng"), AutoACT(@"Hết video"), 2.6);
}

// Theo dõi mỗi 0,5 giây; còn dưới ~1,2 giây thì hẹn đúng lúc rồi dừng (nhịp báo thời gian của YouTube thưa nên không dựa vào nó)
static void AutoACSleepEndPoll(NSUInteger token) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != gSleepToken || !gSleepAtEnd) return;
        NSString *vid = AutoACCurrentVideoID();
        if (gSleepAtEndVideo.length && vid.length && ![vid isEqualToString:gSleepAtEndVideo]) {   // đã sang video khác (YouTube tự chuyển kịp): dừng ngay
            AutoACSleepEndFinish(token);
            return;
        }
        id player = gPlayerVC;
        double duration = player ? AutoACPlayerDouble(player, @[@"currentVideoTotalMediaTime", @"currentVideoTotalTime",
                                                                  @"currentVideoDuration", @"totalMediaTime"]) : 0;
        double time = player ? AutoACPlayerDouble(player, @[@"currentVideoMediaTime", @"currentVideoTime"]) : 0;
        if (duration > 1 && time > 0) {
            double rate = AutoACPlayerDouble(player, @[@"currentPlaybackRate", @"playbackRate", @"currentRate"]);
            if (rate <= 0) rate = 1;
            double remaining = (duration - time) / rate;
            if (remaining <= 1.2) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(remaining - 0.15, 0.0) * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (token != gSleepToken || !gSleepAtEnd) return;
                    id p = gPlayerVC;
                    double t2 = p ? AutoACPlayerDouble(p, @[@"currentVideoMediaTime", @"currentVideoTime"]) : 0;
                    if (t2 > 0 && (duration - t2) / rate > 1.2) { AutoACSleepEndPoll(token); return; }   // người dùng đã tua lại
                    AutoACSleepEndFinish(token);
                });
                return;
            }
        }
        AutoACSleepEndPoll(token);
    });
}

static void AutoACSetSleepTimer(NSInteger minutes) {
    gSleepToken++;
    NSUInteger token = gSleepToken;
    gSleepAtEnd = NO;
    gSleepAtEndVideo = nil;
    if (minutes == 0) {
        gSleepEnd = nil;
        AutoACRefreshSleepButton();
        AutoACShowHub(@"moon.zzz", UIColor.systemGrayColor, AutoACT(@"Đã tắt hẹn giờ"), @"", 2.0);
        return;
    }
    if (minutes < 0) {   // Cuối video
        gSleepEnd = nil;
        gSleepAtEnd = YES;
        gSleepAtEndVideo = AutoACCurrentVideoID();
        AutoACRefreshSleepButton();
        AutoACShowHub(@"moon.zzz.fill", UIColor.systemIndigoColor, AutoACT(@"Dừng khi hết video"), @"", 2.2);
        AutoACSleepEndPoll(token);
        return;
    }
    gSleepEnd = [NSDate dateWithTimeIntervalSinceNow:minutes * 60.0];
    AutoACRefreshSleepButton();
    AutoACShowHub(@"moon.zzz.fill", UIColor.systemIndigoColor,
                  [NSString stringWithFormat:AutoACT(@"Dừng sau %ld phút"), (long)minutes], @"", 2.2);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(minutes * 60.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (token != gSleepToken) return;
        gSleepEnd = nil;
        AutoACRefreshSleepButton();
        id player = gPlayerVC;
        SEL pause = NSSelectorFromString(@"pause");
        if ([player respondsToSelector:pause]) ((void (*)(id, SEL))objc_msgSend)(player, pause);
        AutoACShowHub(@"pause.circle.fill", UIColor.systemIndigoColor, AutoACT(@"Đã tạm dừng"), AutoACT(@"Hẹn giờ"), 2.6);
    });
}

#pragma mark - Tải xuống

static NSString *const kDownloadUA =
    @"Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";

static NSData *AutoACHTTP(NSURLRequest *request, NSInteger *status) {
    __block NSData *result = nil;
    __block NSInteger code = 0;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            result = data;
            code = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
            dispatch_semaphore_signal(done);
        }];
    [task resume];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(90 * NSEC_PER_SEC))) != 0) {
        [task cancel];
    }
    if (status) *status = code;
    return result;
}

static NSDictionary *AutoACAPIContext(NSString *visitor) {
    NSMutableDictionary *client = [@{
        @"clientName": @"VISIONOS", @"clientVersion": @"1.02",
        @"osName": @"visionOS", @"osVersion": @"26.5.23O471",
        @"deviceMake": @"Apple", @"deviceModel": @"RealityDevice17,1",
        @"userAgent": kDownloadUA, @"hl": @"en", @"gl": @"US"} mutableCopy];
    if (visitor.length > 0) client[@"visitorData"] = visitor;
    return @{@"client": client};
}

static NSMutableURLRequest *AutoACAPIRequest(NSString *path, NSDictionary *body, NSString *visitor) {
    NSURL *url = [NSURL URLWithString:[@"https://youtubei.googleapis.com/youtubei/v1/" stringByAppendingString:path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:kDownloadUA forHTTPHeaderField:@"User-Agent"];
    if (visitor.length > 0) [request setValue:visitor forHTTPHeaderField:@"X-Goog-Visitor-Id"];
    return request;
}

static NSString *gVisitorCache = nil;
static NSString *AutoACFetchVisitor(void) {
    if (gVisitorCache.length) return gVisitorCache;   // dùng lại, bỏ một lượt gọi mạng mỗi lần tải
    for (int attempt = 0; attempt < 3; attempt++) {
        NSData *data = AutoACHTTP(AutoACAPIRequest(@"guide?prettyPrint=false&fields=responseContext.visitorData",
                                                   @{@"context": AutoACAPIContext(nil)}, nil), NULL);
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        id value = [json isKindOfClass:NSDictionary.class] ? json[@"responseContext"][@"visitorData"] : nil;
        if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) { gVisitorCache = value; return value; }
        [NSThread sleepForTimeInterval:0.4];
    }
    return nil;
}

static NSDictionary *AutoACFetchPlayer(NSString *videoID, NSString *visitor) {
    NSDictionary *body = @{@"context": AutoACAPIContext(visitor), @"videoId": videoID,
                           @"contentCheckOk": @YES, @"racyCheckOk": @YES};
    NSData *data = AutoACHTTP(AutoACAPIRequest(@"player?prettyPrint=false", body, visitor), NULL);
    id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}

// Mỗi độ phân giải giữ một luồng H.264/MP4 tốt nhất (ghép được bằng AVFoundation, không cần FFmpeg)
static NSArray<NSDictionary *> *AutoACVideoChoices(NSDictionary *streaming) {
    NSMutableDictionary<NSNumber *, NSDictionary *> *best = [NSMutableDictionary dictionary];
    for (NSDictionary *f in streaming[@"adaptiveFormats"]) {
        NSString *mime = f[@"mimeType"];
        if (![mime hasPrefix:@"video/mp4"] || ![mime containsString:@"avc1"] || ![f[@"url"] isKindOfClass:NSString.class]) continue;
        NSNumber *height = @([f[@"height"] integerValue]);
        if (height.integerValue <= 0) continue;
        NSDictionary *current = best[height];
        if (!current || [f[@"bitrate"] longLongValue] > [current[@"bitrate"] longLongValue]) best[height] = f;
    }
    NSArray *keys = [best.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [b compare:a];
    }];
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *k in keys) [out addObject:best[k]];
    return out;
}

static NSDictionary *AutoACBestAudio(NSDictionary *streaming) {
    NSDictionary *best = nil;
    for (NSDictionary *f in streaming[@"adaptiveFormats"]) {
        if (![f[@"mimeType"] hasPrefix:@"audio/mp4"] || ![f[@"url"] isKindOfClass:NSString.class]) continue;
        if (!best || [f[@"bitrate"] longLongValue] > [best[@"bitrate"] longLongValue]) best = f;
    }
    return best;
}

static BOOL AutoACDownloadURL(NSURL *source, int64_t total, NSURL *dest, void (^progress)(int64_t bytes)) {
    [NSFileManager.defaultManager createFileAtPath:dest.path contents:nil attributes:nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:dest.path];
    if (!handle) return NO;
    const int64_t chunk = 6 * 1024 * 1024;
    int64_t offset = 0;
    BOOL finished = NO;
    while (!finished) {
        while (gDLPaused && !gDLCancelled) [NSThread sleepForTimeInterval:0.3];   // tạm dừng giữa các đoạn
        if (gDLCancelled) { [handle closeFile]; return NO; }
        int64_t end = total > 0 ? MIN(offset + chunk, total) - 1 : offset + chunk - 1;
        NSData *data = nil;
        for (int attempt = 0; attempt < 4 && !data; attempt++) {
            if (attempt > 0) [NSThread sleepForTimeInterval:0.6 * attempt];
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:source];
            [request setValue:[NSString stringWithFormat:@"bytes=%lld-%lld", offset, end] forHTTPHeaderField:@"Range"];
            [request setValue:kDownloadUA forHTTPHeaderField:@"User-Agent"];
            request.timeoutInterval = 45;
            NSInteger status = 0;
            NSData *d = AutoACHTTP(request, &status);
            if ((status == 206 || status == 200) && d.length > 0) data = d;
        }
        if (!data) { [handle closeFile]; return NO; }
        @try { [handle writeData:data]; }
        @catch (__unused NSException *e) { [handle closeFile]; return NO; }   // đầy bộ nhớ máy / lỗi ghi: dừng tải thay vì sập app
        offset += (int64_t)data.length;
        if (progress) progress(offset);
        finished = total > 0 ? offset >= total : (int64_t)data.length < chunk;
    }
    [handle closeFile];
    return YES;
}

static NSString *AutoACSafeFileName(NSString *name) {
    NSMutableString *s = [NSMutableString string];
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|\n\r\t"];
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        [s appendString:[bad characterIsMember:c] ? @" " : [NSString stringWithCharacters:&c length:1]];
    }
    NSString *trim = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (trim.length > 80) trim = [trim substringToIndex:80];
    return trim.length > 0 ? trim : @"YouTube";
}


static void AutoACReleaseDir(NSString *dir) {   // xoá đúng thư mục của lần tải này (lần tải kế tiếp có thể đã đổi gHeldDir)
    if ([gHeldDir isEqualToString:dir]) gHeldDir = nil;
    if (dir.length == 0) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
    });
}

static void AutoACShareFile(NSURL *file, NSString *dir) {
    UIViewController *top = AutoACTopViewController();
    if (!top || !file) { AutoACReleaseDir(dir); return; }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[file]
                                                                        applicationActivities:nil];
    // Chia sẻ xong (lưu, gửi hay đóng bảng) thì xoá bản tạm
    share.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *err) {
        AutoACReleaseDir(dir);
    };
    share.popoverPresentationController.sourceView = top.view;
    share.popoverPresentationController.sourceRect =
        CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMaxY(top.view.bounds) - 1, 1, 1);
    [top presentViewController:share animated:YES completion:nil];
}

// Xin quyền "chỉ thêm vào Ảnh" rồi chạy `change`; `done` luôn được gọi trên main queue
static void AutoACPhotosAdd(void (^change)(void), void (^done)(BOOL ok)) {
    void (^run)(PHAuthorizationStatus) = ^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(NO); });
            return;
        }
        [PHPhotoLibrary.sharedPhotoLibrary performChanges:change
            completionHandler:^(BOOL success, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{ done(success); });
            }];
    };
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:run];
}

static void AutoACDownloadFinishedOne(NSURL *file, NSString *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gDownloading = NO;
        NSString *myDir = gHeldDir;
        gDLPaused = NO;
        BOOL wasCancelled = gDLCancelled;
        gDLCancelled = NO;
        BOOL toPhotos = gToPhotos;
        gToPhotos = NO;
        if (wasCancelled) {
            AutoACShowHub(@"xmark.circle.fill", UIColor.systemGrayColor, AutoACT(@"Đã huỷ tải"), @"", 1.8);
            AutoACReleaseDir(myDir);
            return;
        }
        if (!file) {
            AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemRedColor,
                          error ?: AutoACT(@"Tải không thành công"), @"", 3.0);
            AutoACReleaseDir(myDir);   // tải lỗi: bỏ phần đã tải dở
            return;
        }
        if (toPhotos && [file.pathExtension.lowercaseString isEqualToString:@"mp4"]) {
            AutoACPhotosAdd(^{ [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:file]; },
                            ^(BOOL ok) {
                if (ok) {
                    AutoACShowHub(@"checkmark.circle.fill", UIColor.systemGreenColor, AutoACT(@"Đã lưu vào Ảnh"), @"", 2.0);
                    AutoACReleaseDir(myDir);   // đã có bản trong Ảnh: xoá bản tạm
                } else {
                    AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor,
                                  AutoACT(@"Không lưu được vào Ảnh"), AutoACT(@"Mở chia sẻ"), 2.6);
                    AutoACShareFile(file, myDir);
                }
            });
            return;
        }
        AutoACShowHub(@"checkmark.circle.fill", UIColor.systemGreenColor, AutoACT(@"Đã tải xong"), @"", 1.8);
        if (![kPrefs boolForKey:kShareAfterKey]) { if ([gHeldDir isEqualToString:myDir]) gHeldDir = nil; return; }   // không mở chia sẻ: thả khoá, bộ dọn sẽ xử lý tệp tạm
        AutoACShareFile(file, myDir);
    });
}

// Hàng đợi tải: bấm tải khi đang có video được tải thì xếp hàng, tải lần lượt từng video
static NSMutableArray<void (^)(void)> *gDLQueue = nil;
static NSMutableArray<NSString *> *gDLQueueIDs = nil;   // ID video của từng mục đang chờ (hiện ở trang Thông tin)
static NSMutableArray<NSDictionary *> *gDLQueueMeta = nil;   // {id, audio, photos, tries} song song với gDLQueue, để lưu lại
static NSDictionary *gDLCurrentJob = nil;                // lượt tải đang chạy, cùng dạng với trên
static NSInteger gDLResumeTries = 0;                     // số lần đã tự tiếp tục của lượt sắp bắt đầu (chống lặp vô hạn nếu tải làm app thoát)
static NSString *const kDLPendingKey = @"AutoACDLPending";

// Lưu lượt tải đang chạy và hàng đợi để mở lại app thì tiếp tục (bị thoát giữa chừng không mất)
static void AutoACPersistDownloads(void) {
    NSMutableArray *list = [NSMutableArray array];
    if (gDLCurrentJob) [list addObject:gDLCurrentJob];
    if (gDLQueueMeta.count) [list addObjectsFromArray:gDLQueueMeta];
    if (list.count) [kPrefs setObject:list forKey:kDLPendingKey]; else [kPrefs removeObjectForKey:kDLPendingKey];
}

static void AutoACDownloadFinished(NSURL *file, NSString *error) {
    AutoACDownloadFinishedOne(file, error);
    dispatch_async(dispatch_get_main_queue(), ^{ gDLCurrentJob = nil; AutoACPersistDownloads(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gDownloading || gDLQueue.count == 0) return;
        void (^next)(void) = gDLQueue.firstObject;
        [gDLQueue removeObjectAtIndex:0];
        if (gDLQueueIDs.count) [gDLQueueIDs removeObjectAtIndex:0];
        if (gDLQueueMeta.count) [gDLQueueMeta removeObjectAtIndex:0];
        next();
    });
}

static void AutoACMux(NSURL *video, NSURL *audio, NSURL *output) {
    AVURLAsset *va = [AVURLAsset URLAssetWithURL:video options:nil];
    AVURLAsset *aa = [AVURLAsset URLAssetWithURL:audio options:nil];
    AVAssetTrack *vt = [va tracksWithMediaType:AVMediaTypeVideo].firstObject;
    AVAssetTrack *at = [aa tracksWithMediaType:AVMediaTypeAudio].firstObject;
    if (!vt || !at) { AutoACDownloadFinished(nil, AutoACT(@"Không ghép được video và âm thanh")); return; }
    CMTime duration = CMTimeMinimum(va.duration, aa.duration);
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *ct = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                             preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *cat = [composition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                              preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError *error = nil;
    [ct insertTimeRange:CMTimeRangeMake(kCMTimeZero, duration) ofTrack:vt atTime:kCMTimeZero error:&error];
    [cat insertTimeRange:CMTimeRangeMake(kCMTimeZero, duration) ofTrack:at atTime:kCMTimeZero error:&error];
    ct.preferredTransform = vt.preferredTransform;
    // Ghép giữ nguyên luồng (nhanh, không mất chất lượng); nếu thất bại thì thử lại với preset chất lượng cao nhất
    __block void (^attempt)(NSString *, BOOL) = nil;
    attempt = ^(NSString *preset, BOOL last) {
        AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:composition presetName:preset];
        [NSFileManager.defaultManager removeItemAtURL:output error:nil];
        export.outputURL = output;
        export.outputFileType = AVFileTypeMPEG4;
        export.shouldOptimizeForNetworkUse = YES;
        [export exportAsynchronouslyWithCompletionHandler:^{
            BOOL ok = export.status == AVAssetExportSessionStatusCompleted;
            if (!ok && !last) { attempt(AVAssetExportPresetHighestQuality, YES); return; }
            attempt = nil;
            [NSFileManager.defaultManager removeItemAtURL:video error:nil];
            [NSFileManager.defaultManager removeItemAtURL:audio error:nil];
            AutoACDownloadFinished(ok ? output : nil, ok ? nil : AutoACT(@"Ghép video và âm thanh thất bại"));
        }];
    };
    attempt(AVAssetExportPresetPassthrough, NO);
}

static void AutoACProgressHub(double fraction, NSString *label) {
    static NSInteger lastStep = -1;
    gDLFraction = fraction;
    gDLLabel = label;
    NSInteger step = (NSInteger)(fraction * 10);
    if (step == lastStep) return;
    lastStep = step;
    dispatch_async(dispatch_get_main_queue(), ^{
        AutoACShowHub(@"arrow.down.circle.fill", UIColor.systemBlueColor,
                      [NSString stringWithFormat:@"%@ %ld%%", label, (long)MIN(100, step * 10)], @"", 60);
    });
}

// Tải theo lựa chọn: video (kèm âm thanh ghép) hoặc chỉ âm thanh
static void AutoACRunDownload(NSDictionary *video, NSDictionary *audio, NSString *title) {
    gDLPaused = NO; gDLCancelled = NO; gDLFraction = 0;
    gDLName = title;
    gDLLabel = video ? AutoACT(@"Đang tải video") : AutoACT(@"Đang tải âm thanh");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSURL *dir = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
                      URLByAppendingPathComponent:[@"AutoAC-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
        gHeldDir = dir.path;   // giữ thư mục này khỏi bị dọn cho tới khi tải xong và dùng xong
        NSString *name = AutoACSafeFileName(title);
        int64_t vTotal = video ? [video[@"contentLength"] longLongValue] : 0;
        int64_t aTotal = audio ? [audio[@"contentLength"] longLongValue] : 0;
        __block int64_t vBytes = 0, aBytes = 0;
        double sum = (double)MAX(vTotal + aTotal, 1);
        NSString *label = video ? AutoACT(@"Đang tải video") : AutoACT(@"Đang tải âm thanh");

        NSURL *videoFile = video ? [dir URLByAppendingPathComponent:@"video.mp4"] : nil;
        NSURL *audioFile = audio ? [dir URLByAppendingPathComponent:@"audio.m4a"] : nil;
        if (video && !AutoACDownloadURL([NSURL URLWithString:video[@"url"]], vTotal, videoFile, ^(int64_t b) {
                vBytes = b; AutoACProgressHub((vBytes + aBytes) / sum, label); })) {
            AutoACDownloadFinished(gDLCancelled ? videoFile : nil, AutoACT(@"Không tải được video")); return;
        }
        if (audio && !AutoACDownloadURL([NSURL URLWithString:audio[@"url"]], aTotal, audioFile, ^(int64_t b) {
                aBytes = b; AutoACProgressHub((vBytes + aBytes) / sum, label); })) {
            AutoACDownloadFinished(gDLCancelled ? audioFile : nil, AutoACT(@"Không tải được âm thanh")); return;
        }
        if (video && audio) {
            dispatch_async(dispatch_get_main_queue(), ^{
                gDLLabel = AutoACT(@"Đang ghép tệp"); gDLFraction = 1;
                AutoACShowHub(@"film.stack", UIColor.systemOrangeColor, AutoACT(@"Đang ghép tệp"), @"", 60);
            });
            AutoACMux(videoFile, audioFile, [dir URLByAppendingPathComponent:[name stringByAppendingString:@".mp4"]]);
        } else if (video) {
            NSURL *out = [dir URLByAppendingPathComponent:[name stringByAppendingString:@".mp4"]];
            [NSFileManager.defaultManager moveItemAtURL:videoFile toURL:out error:nil];
            AutoACDownloadFinished(out, nil);
        } else {
            NSURL *out = [dir URLByAppendingPathComponent:[name stringByAppendingString:@".m4a"]];
            [NSFileManager.defaultManager moveItemAtURL:audioFile toURL:out error:nil];
            AutoACDownloadFinished(out, nil);
        }
    });
}

static void AutoACBeginDownloadID(NSString *videoID, BOOL audioOnly);
static void AutoACBeginDownload(BOOL audioOnly) {
    NSString *videoID = AutoACCurrentVideoID();
    if (videoID.length == 0) {
        AutoACShowHub(@"play.slash.fill", UIColor.systemOrangeColor, AutoACT(@"Hãy mở một video trước"), @"", 2.4);
        return;
    }
    if (gDownloading) {
        if (!gDLQueue) gDLQueue = [NSMutableArray array];
        if (!gDLQueueIDs) gDLQueueIDs = [NSMutableArray array];
        if (!gDLQueueMeta) gDLQueueMeta = [NSMutableArray array];
        [gDLQueueIDs addObject:videoID];
        BOOL photos = gToPhotos;
        [gDLQueueMeta addObject:@{@"id": videoID, @"audio": @(audioOnly), @"photos": @(photos), @"tries": @0}];
        [gDLQueue addObject:^{ gToPhotos = photos; AutoACBeginDownloadID(videoID, audioOnly); }];
        AutoACPersistDownloads();
        AutoACShowHub(@"text.badge.plus", UIColor.systemOrangeColor, AutoACT(@"Đã thêm vào hàng đợi tải"),
                      [NSString stringWithFormat:@"%lu", (unsigned long)gDLQueue.count], 2.2);
        return;
    }
    AutoACBeginDownloadID(videoID, audioOnly);
}

static void AutoACBeginDownloadID(NSString *videoID, BOOL audioOnly) {
    gDownloading = YES;
    gDLCurrentJob = @{@"id": videoID, @"audio": @(audioOnly), @"photos": @(gToPhotos), @"tries": @(gDLResumeTries)};
    gDLResumeTries = 0;
    AutoACPersistDownloads();
    gDLPaused = NO; gDLCancelled = NO; gDLFraction = 0; gDLLabel = AutoACT(@"Đang chuẩn bị");
    AutoACShowHub(@"magnifyingglass", UIColor.systemBlueColor, AutoACT(@"Đang lấy thông tin"), @"", 60);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *json = AutoACFetchPlayer(videoID, AutoACFetchVisitor());
        NSDictionary *streaming = json[@"streamingData"];
        NSString *title = json[@"videoDetails"][@"title"] ?: videoID;
        NSDictionary *audio = AutoACBestAudio(streaming);
        NSArray<NSDictionary *> *videos = AutoACVideoChoices(streaming);

        if (![streaming isKindOfClass:NSDictionary.class] || (audioOnly ? !audio : (videos.count == 0 || !audio))) {
            NSString *reason = json[@"playabilityStatus"][@"reason"];
            AutoACDownloadFinished(nil, reason.length ? reason : AutoACT(@"Video này không hỗ trợ tải"));
            return;
        }
        if (audioOnly) { AutoACRunDownload(nil, audio, title); return; }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (![kPrefs boolForKey:kAskQualityKey]) {
                AutoACRunDownload(videos.firstObject, audio, title);
                return;
            }
            NSMutableArray<NSString *> *names = [NSMutableArray array];
            for (NSDictionary *f in videos) {
                double mb = [f[@"contentLength"] longLongValue] / 1048576.0;
                [names addObject:[NSString stringWithFormat:@"%ldp · %.0f MB", (long)[f[@"height"] integerValue], mb]];
            }
            gDownloading = NO;
            AutoACShowHub(@"checkmark", UIColor.systemBlueColor, AutoACT(@"Chọn chất lượng"), @"", 1.0);
            AutoACPresentSheet(AutoACT(@"Chất lượng video"), title, names, ^(NSInteger i) {
                gDownloading = YES;
                AutoACRunDownload(videos[i], audio, title);
            });
        });
    });
}

// Mở lại app: tiếp tục lượt tải dở và hàng đợi đã lưu (tải lại từ đầu vì tệp tạm đã bị dọn; mỗi mục thử lại tối đa 2 lần)
static void AutoACResumeDownloadsOnce(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    NSArray *saved = [kPrefs arrayForKey:kDLPendingKey];
    [kPrefs removeObjectForKey:kDLPendingKey];
    if (saved.count == 0 || gDownloading) return;
    NSMutableArray<NSDictionary *> *jobs = [NSMutableArray array];
    for (id d in saved) {
        if (![d isKindOfClass:NSDictionary.class] || ![d[@"id"] isKindOfClass:NSString.class] || [d[@"id"] length] == 0) continue;
        NSInteger tries = [d[@"tries"] integerValue] + 1;
        if (tries > 2) continue;
        [jobs addObject:@{@"id": d[@"id"], @"audio": @([d[@"audio"] boolValue]), @"photos": @([d[@"photos"] boolValue]), @"tries": @(tries)}];
    }
    if (jobs.count == 0) return;
    AutoACShowHub(@"arrow.clockwise.circle.fill", UIColor.systemBlueColor, AutoACT(@"Tiếp tục tải video dở"),
                  [NSString stringWithFormat:@"%lu", (unsigned long)jobs.count], 2.8);
    for (NSUInteger n = 0; n < jobs.count; n++) {
        NSDictionary *j = jobs[n];
        NSString *vid = j[@"id"]; BOOL audio = [j[@"audio"] boolValue], photos = [j[@"photos"] boolValue];
        NSInteger tries = [j[@"tries"] integerValue];
        void (^start)(void) = ^{ gToPhotos = photos; gDLResumeTries = tries; AutoACBeginDownloadID(vid, audio); };
        if (n == 0) { start(); continue; }
        if (!gDLQueue) gDLQueue = [NSMutableArray array];
        if (!gDLQueueIDs) gDLQueueIDs = [NSMutableArray array];
        if (!gDLQueueMeta) gDLQueueMeta = [NSMutableArray array];
        [gDLQueue addObject:start]; [gDLQueueIDs addObject:vid]; [gDLQueueMeta addObject:j];
    }
    AutoACPersistDownloads();
}

// Giống menu tải của ytkace: video hỏi nơi lưu (bảng chia sẻ / Ảnh), âm thanh luôn qua bảng chia sẻ
static void AutoACStartDownload(BOOL audioOnly) {
    NSString *videoID = AutoACCurrentVideoID();
    if (videoID.length == 0) {
        AutoACShowHub(@"play.slash.fill", UIColor.systemOrangeColor, AutoACT(@"Hãy mở một video trước"), @"", 2.4);
        return;
    }
    gToPhotos = NO;
    if (audioOnly || ![kPrefs boolForKey:kAskDestKey]) {
        AutoACBeginDownload(audioOnly);
        return;
    }
    AutoACPresentSheet(AutoACT(@"Lưu video vào đâu?"), nil, @[AutoACT(@"Bảng chia sẻ / Tệp"), AutoACT(@"Lưu vào Ảnh")], ^(NSInteger i) {
        gToPhotos = (i == 1);
        AutoACBeginDownload(NO);
    });
}

#pragma mark - Tác vụ nhanh theo ytkace: sao chép thông tin, phát ngoài, lưu ảnh bìa

// Thời điểm đang phát (giây); 0 nếu không đọc được
static double AutoACCurrentTime(void) {
    id player = gPlayerVC;
    if (!player) return 0;
    for (NSString *name in @[@"currentVideoMediaTime", @"currentVideoTime", @"currentMediaTime", @"mediaTime"]) {
        SEL selector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod([player class], selector);
        if (!method) continue;
        char type[16] = {};
        method_getReturnType(method, type, sizeof(type));
        if (strcmp(type, @encode(double)) == 0) return ((double (*)(id, SEL))objc_msgSend)(player, selector);
        if (strcmp(type, @encode(float)) == 0) return ((float (*)(id, SEL))objc_msgSend)(player, selector);
    }
    return 0;
}

static void AutoACPausePlayer(void) {
    id player = gPlayerVC;
    for (NSString *name in @[@"pauseVideo", @"pausePlayback", @"pause"]) {
        SEL selector = NSSelectorFromString(name);
        Method method = player ? class_getInstanceMethod([player class], selector) : NULL;
        if (method && method_getNumberOfArguments(method) == 2) {
            ((void (*)(id, SEL))objc_msgSend)(player, selector);
            return;
        }
    }
}

static void AutoACResumePlayer(void) {
    id player = gPlayerVC;
    for (NSString *name in @[@"playVideo", @"playPlayback", @"play"]) {
        SEL selector = NSSelectorFromString(name);
        Method method = player ? class_getInstanceMethod([player class], selector) : NULL;
        if (method && method_getNumberOfArguments(method) == 2) {
            ((void (*)(id, SEL))objc_msgSend)(player, selector);
            return;
        }
    }
}

// Lấy thông tin video đang phát qua InnerTube rồi gọi `block` trên main queue (json có thể nil)
static void AutoACWithPlayerInfo(void (^block)(NSDictionary *json, NSString *videoID)) {
    NSString *videoID = AutoACCurrentVideoID();
    if (videoID.length == 0) {
        AutoACShowHub(@"play.slash.fill", UIColor.systemOrangeColor, AutoACT(@"Hãy mở một video trước"), @"", 2.4);
        return;
    }
    AutoACShowHub(@"magnifyingglass", UIColor.systemBlueColor, AutoACT(@"Đang lấy thông tin"), @"", 60);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *json = AutoACFetchPlayer(videoID, AutoACFetchVisitor());
        dispatch_async(dispatch_get_main_queue(), ^{
            [gHub removeFromSuperview];
            block(json, videoID);
        });
    });
}

static void AutoACCopyText(NSString *text, NSString *doneMessage) {
    if (text.length == 0) {
        AutoACShowHub(@"exclamationmark.circle.fill", UIColor.systemOrangeColor, AutoACT(@"Không có thông tin"), @"", 2.2);
        return;
    }
    UIPasteboard.generalPasteboard.string = text;
    AutoACShowHub(@"checkmark.circle.fill", UIColor.systemGreenColor, doneMessage, @"", 1.8);
}

static NSString *AutoACEscapeForQuery(NSString *value);
#pragma mark - Phụ đề, bình luận, ảnh bài đăng (theo ytkace)

static NSString *const kCommentToolsKey = @"kCommentTools";     // giữ bình luận để sao chép / dịch
static NSString *const kPostImageKey = @"kPostImageSave";       // nút lưu ảnh trong bài đăng

static NSString *AutoACClock(long ms) {
    long s = ms / 1000;
    if (s >= 3600) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", s / 3600, (s / 60) % 60, s % 60];
    return [NSString stringWithFormat:@"%ld:%02ld", s / 60, s % 60];
}

// Phụ đề json3: events[].segs[].utf8, mốc tStartMs
static NSString *AutoACParseJSON3(NSData *data, BOOL stamps) {
    id obj = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSArray *events = [obj isKindOfClass:NSDictionary.class] ? obj[@"events"] : nil;
    if (![events isKindOfClass:NSArray.class]) return nil;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSDictionary *e in events) {
        if (![e isKindOfClass:NSDictionary.class]) continue;
        NSArray *segs = e[@"segs"];
        if (![segs isKindOfClass:NSArray.class]) continue;
        NSMutableString *t = [NSMutableString string];
        for (NSDictionary *s in segs) {
            NSString *u = [s isKindOfClass:NSDictionary.class] ? s[@"utf8"] : nil;
            if ([u isKindOfClass:NSString.class]) [t appendString:u];
        }
        NSString *line = [[t stringByReplacingOccurrencesOfString:@"\n" withString:@" "]
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (line.length == 0) continue;
        if (stamps) line = [NSString stringWithFormat:@"[%@] %@", AutoACClock([e[@"tStartMs"] longValue]), line];
        [lines addObject:line];
    }
    return lines.count ? [lines componentsJoinedByString:@"\n"] : nil;
}

static void AutoACOfferText(NSString *text, NSString *name) {
    AutoACPresentSheet(name, nil, @[AutoACT(@"Sao chép"), AutoACT(@"Lưu thành tệp .txt")], ^(NSInteger i) {
        if (i == 0) { AutoACCopyText(text, AutoACT(@"Đã sao chép")); return; }
        NSString *file = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [name stringByAppendingString:@".txt"]];
        [text writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
        UIActivityViewController *share = [[UIActivityViewController alloc]
            initWithActivityItems:@[[NSURL fileURLWithPath:file]] applicationActivities:nil];
        UIViewController *top = AutoACTopViewController();
        share.popoverPresentationController.sourceView = top.view;
        share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
        [top presentViewController:share animated:YES completion:nil];
    });
}

static void AutoACFetchSubtitle(NSDictionary *track, BOOL stamps, NSString *tlang) {
    NSString *base = track[@"baseUrl"];
    if (![base isKindOfClass:NSString.class]) return;
    NSString *urlString = [base stringByAppendingString:@"&fmt=json3"];
    if (tlang.length) urlString = [urlString stringByAppendingFormat:@"&tlang=%@", tlang];
    AutoACShowHub(@"captions.bubble.fill", UIColor.systemBlueColor, AutoACT(@"Đang lấy phụ đề"), @"", 60);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSURL *url = [NSURL URLWithString:urlString];
        NSInteger status = 0;
        NSData *data = url ? AutoACHTTP([NSURLRequest requestWithURL:url], &status) : nil;
        NSString *text = status == 200 ? AutoACParseJSON3(data, stamps) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [gHub removeFromSuperview];
            if (text.length == 0) {
                AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor,
                              AutoACT(@"Không lấy được phụ đề"), AutoACT(@"Video có thể không có phụ đề"), 2.8);
                return;
            }
            AutoACOfferText(text, stamps ? AutoACT(@"Phụ đề kèm thời gian") : AutoACT(@"Phụ đề"));
        });
    });
}

static void AutoACCopySubtitles(BOOL stamps, NSString *tlang) {
    AutoACWithPlayerInfo(^(NSDictionary *json, NSString *vid) {
        NSArray *tracks = json[@"captions"][@"playerCaptionsTracklistRenderer"][@"captionTracks"];
        if (![tracks isKindOfClass:NSArray.class] || tracks.count == 0) {
            AutoACShowHub(@"exclamationmark.circle.fill", UIColor.systemOrangeColor,
                          AutoACT(@"Video không có phụ đề"), @"", 2.6);
            return;
        }
        if (tracks.count == 1) { AutoACFetchSubtitle(tracks[0], stamps, tlang); return; }
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSDictionary *t in tracks) {
            NSDictionary *n = t[@"name"];
            NSString *label = [n isKindOfClass:NSDictionary.class] ? (n[@"simpleText"] ?: n[@"runs"][0][@"text"]) : nil;
            [names addObject:[label isKindOfClass:NSString.class] ? label : (t[@"languageCode"] ?: AutoACT(@"Phụ đề"))];
        }
        AutoACPresentSheet(AutoACT(@"Chọn phụ đề"), nil, names, ^(NSInteger i) {
            AutoACFetchSubtitle(tracks[i], stamps, tlang);
        });
    });
}

// Ngôn ngữ đích = ngôn ngữ của thiết bị
static NSString *AutoACDeviceLangCode(void) {
    NSString *pref = NSLocale.preferredLanguages.firstObject ?: @"vi";
    if ([pref hasPrefix:@"zh-Hant"] || [pref hasPrefix:@"zh-TW"] || [pref hasPrefix:@"zh-HK"]) return @"zh-TW";
    if ([pref hasPrefix:@"zh"]) return @"zh-CN";
    NSString *base = [pref componentsSeparatedByString:@"-"].firstObject;
    if ([base isEqualToString:@"nb"] || [base isEqualToString:@"nn"]) return @"no";
    if ([base isEqualToString:@"he"]) return @"iw";
    return base.length ? base : @"vi";
}
static NSString *AutoACDeviceLangName(void) {
    NSString *code = AutoACDeviceLangCode();
    NSString *name = [[NSLocale localeWithLocaleIdentifier:@"vi"] localizedStringForLanguageCode:[code componentsSeparatedByString:@"-"].firstObject];
    return name.length ? name : code;
}

// Dịch bằng Google (gtx), sang ngôn ngữ thiết bị
static void AutoACTranslate(NSString *text, void (^done)(NSString *result)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *q = AutoACEscapeForQuery(text);
        NSURL *url = [NSURL URLWithString:[@"https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&dt=t&tl="
                                           stringByAppendingString:[AutoACDeviceLangCode() stringByAppendingFormat:@"&q=%@", q]]];
        NSInteger status = 0;
        NSData *data = url ? AutoACHTTP([NSURLRequest requestWithURL:url], &status) : nil;
        NSMutableString *out = [NSMutableString string];
        id obj = (status == 200 && data.length) ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSArray *parts = [obj isKindOfClass:NSArray.class] && [obj count] > 0 ? obj[0] : nil;
        if ([parts isKindOfClass:NSArray.class]) {
            for (NSArray *p in parts) {
                if ([p isKindOfClass:NSArray.class] && p.count > 0 && [p[0] isKindOfClass:NSString.class]) [out appendString:p[0]];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(out.length ? [out copy] : nil); });
    });
}

static void AutoACTranslateAndShow(NSString *text, BOOL copyToo) {
    AutoACShowHub(@"character.bubble.fill", UIColor.systemBlueColor, AutoACT(@"Đang dịch"), @"", 60);
    AutoACTranslate(text, ^(NSString *result) {
        [gHub removeFromSuperview];
        if (!result) {
            AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor, AutoACT(@"Không dịch được"), AutoACT(@"Kiểm tra kết nối mạng"), 2.6);
            return;
        }
        if (copyToo) { AutoACCopyText(result, AutoACT(@"Đã dịch và sao chép")); return; }
        AutoACPresentSheet(AutoACT(@"Bản dịch"), result, @[AutoACT(@"Sao chép bản dịch")], ^(NSInteger i) {
            AutoACCopyText(result, AutoACT(@"Đã sao chép bản dịch"));
        });
    });
}

// ── Bình luận: nhấn giữ để sao chép hoặc dịch (như ytkace) ──
static id AutoACNodeValue(id node, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return [node respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(node, selector) : nil;
}
static id AutoACFindExpandable(id node, NSUInteger depth) {
    if (!node || depth > 12) return nil;
    if ([NSStringFromClass([node class]) isEqualToString:@"ELMExpandableTextNode"]) return node;
    for (id child in AutoACNodeValue(node, @"subnodes")) {
        id found = AutoACFindExpandable(child, depth + 1);
        if (found) return found;
    }
    return nil;
}
static NSString *AutoACNodeText(id node, NSUInteger depth) {
    if (!node || depth > 4) return nil;
    NSString *text = [AutoACNodeValue(node, @"attributedText") string];
    if (text.length) return text;
    for (id child in AutoACNodeValue(node, @"subnodes")) {
        text = AutoACNodeText(child, depth + 1);
        if (text.length) return text;
    }
    return nil;
}
static UIView *AutoACCommentCellAt(UIView *window, CGPoint point) {
    UIView *cell = [window hitTest:point withEvent:nil];
    while (cell && ![NSStringFromClass(cell.class) isEqualToString:@"_ASCollectionViewCell"]) cell = cell.superview;
    return cell;
}

static id AutoACFindCommentNode(id node, NSUInteger depth) {
    if (!node || depth > 4) return nil;
    if ([NSStringFromClass([node class]) containsString:@"CommentNode"]) return node;
    for (id child in AutoACNodeValue(node, @"subnodes")) {
        id found = AutoACFindCommentNode(child, depth + 1);
        if (found) return found;
    }
    return nil;
}

static void AutoACShowCommentSheet(NSString *text);

@interface AutoACCommentHandler : NSObject <UIGestureRecognizerDelegate>
@end
@implementation AutoACCommentHandler
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o { return YES; }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (![kPrefs boolForKey:kCommentToolsKey]) return NO;
    UIView *cell = AutoACCommentCellAt(g.view, [g locationInView:g.view]);
    return AutoACFindCommentNode(AutoACNodeValue(cell, @"node"), 0) != nil;
}
- (void)pressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIView *window = g.view;
    CGPoint point = [g locationInView:window];
    UIView *cell = AutoACCommentCellAt(window, point);
    id cellNode = AutoACFindCommentNode(AutoACNodeValue(cell, @"node"), 0);
    if (!cellNode) return;
    id textNode = AutoACFindExpandable(cellNode, 0);   // nhấn giữ bất kỳ đâu trong bình luận (kể cả biểu tượng trả lời) đều dùng được
    NSString *text = AutoACNodeText(textNode, 0);
    if (text.length == 0) return;
    AutoACShowCommentSheet(text);
}
@end

static NSString *AutoACCommentLabelText(id node, NSUInteger depth) {
    if (!node || depth > 12) return nil;
    id ident = AutoACNodeValue(node, @"accessibilityIdentifier");
    if ([ident isKindOfClass:NSString.class] && [ident isEqualToString:@"id.comment.content.label"]) {
        NSString *t = [AutoACNodeValue(node, @"attributedText") string];
        if (t.length) return t;
    }
    for (id child in AutoACNodeValue(node, @"subnodes")) {
        NSString *t = AutoACCommentLabelText(child, depth + 1);
        if (t.length) return t;
    }
    return nil;
}

static CFTimeInterval gCommentSheetAt = 0;
static void AutoACShowCommentSheet(NSString *text) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gCommentSheetAt < 1.0) return;   // hai cơ chế cùng nhận một lần nhấn giữ thì chỉ mở một bảng
    gCommentSheetAt = now;
    [[UIImpactFeedbackGenerator.alloc initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    AutoACTrace("comment long-press");
    AutoACPresentSheet(AutoACT(@"Bình luận"), nil, @[AutoACT(@"Sao chép"), [AutoACT(@"Dịch sang ") stringByAppendingString:AutoACDeviceLangName()], AutoACT(@"Dịch và sao chép")], ^(NSInteger i) {
        if (i == 0) AutoACCopyText(text, AutoACT(@"Đã sao chép bình luận"));
        else AutoACTranslateAndShow(text, i == 2);
    });
}

// Cách của YTLite: gắn cử chỉ ngay vào ô bình luận ("id.ui.comment_cell"), lấy chữ từ nhãn "id.comment.content.label"
@interface AutoACCellPress : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)pressed:(UILongPressGestureRecognizer *)g;
@end
@implementation AutoACCellPress
+ (instancetype)shared { static AutoACCellPress *i; static dispatch_once_t o; dispatch_once(&o, ^{ i = [AutoACCellPress new]; }); return i; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o { return YES; }
- (void)pressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan || ![kPrefs boolForKey:kCommentToolsKey]) return;
    id node = AutoACNodeValue(g.view, @"keepalive_node");
    NSString *text = AutoACCommentLabelText(node, 0);
    if (text.length == 0) text = AutoACNodeText(AutoACFindExpandable(node, 0), 0);
    if (text.length == 0) { AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor, AutoACT(@"Không đọc được bình luận"), @"", 2.0); return; }
    AutoACShowCommentSheet(text);
}
@end

static const char kAutoACCellPressKey = 0;
static void AutoACInstallCommentCellHook(void) {
    AutoACHook(@"_ASDisplayView", @"setKeepalive_node:", NO, "v", ^id(IMP original, SEL selector) {
        return ^void(UIView *self_, id node) {
            if (original) ((void (*)(id, SEL, id))original)(self_, selector, node);
            if (![kPrefs boolForKey:kCommentToolsKey] || objc_getAssociatedObject(self_, &kAutoACCellPressKey)) return;
            if (![NSStringFromClass([node class]) containsString:@"ELMContainerNode"]) return;   // lọc rẻ trước, vì hàm này chạy cho mọi view
            if (![[self_ description] containsString:@"id.ui.comment_cell"]) return;
            UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[AutoACCellPress shared]
                                                                                             action:@selector(pressed:)];
            lp.minimumPressDuration = 0.45;
            lp.delegate = [AutoACCellPress shared];
            [self_ addGestureRecognizer:lp];
            objc_setAssociatedObject(self_, &kAutoACCellPressKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        };
    });
}

static AutoACCommentHandler *gCommentHandler;
static const char kAutoACCommentGestureKey = 0;

static void AutoACAttachCommentGestures(void) {
    if (![kPrefs boolForKey:kCommentToolsKey]) return;
    if (!gCommentHandler) gCommentHandler = [AutoACCommentHandler new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (objc_getAssociatedObject(window, &kAutoACCommentGestureKey)) continue;
            UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
                initWithTarget:gCommentHandler action:@selector(pressed:)];
            press.minimumPressDuration = 0.5;
            press.delegate = gCommentHandler;
            [window addGestureRecognizer:press];
            objc_setAssociatedObject(window, &kAutoACCommentGestureKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

// ── Ảnh bài đăng: nút lưu ở màn xem ảnh ──
static NSURL *AutoACOriginalImageURL(NSURL *url) {
    NSString *text = url.absoluteString;
    NSRange crop = [text rangeOfString:@"c-fcrop"];
    if (crop.location != NSNotFound)
        return [NSURL URLWithString:[[text substringToIndex:crop.location] stringByAppendingString:@"nd-v1"]] ?: url;
    NSRange slash = [text rangeOfString:@"/" options:NSBackwardsSearch];
    if (slash.location == NSNotFound) return url;
    NSRange eq = [text rangeOfString:@"=" options:NSBackwardsSearch range:NSMakeRange(slash.location, text.length - slash.location)];
    if (eq.location == NSNotFound) return url;
    return [NSURL URLWithString:[[text substringToIndex:eq.location] stringByAppendingString:@"=s0"]] ?: url;
}

static __weak id gZoomNode;
static const char kAutoACPostSaveKey = 0;

@interface AutoACPostSaveTarget : NSObject
+ (instancetype)shared;
- (void)saveTapped:(UIButton *)sender;
@end
@implementation AutoACPostSaveTarget
+ (instancetype)shared { static AutoACPostSaveTarget *t; static dispatch_once_t o; dispatch_once(&o, ^{ t = [AutoACPostSaveTarget new]; }); return t; }
- (void)saveTapped:(UIButton *)sender {
    NSURL *url = AutoACNodeValue(gZoomNode, @"URL");
    if (![url isKindOfClass:NSURL.class]) {
        AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor, AutoACT(@"Ảnh chưa tải xong"), @"", 2.2);
        return;
    }
    sender.enabled = NO;
    AutoACShowHub(@"photo", UIColor.systemBlueColor, AutoACT(@"Đang lưu ảnh"), @"", 60);
    NSURL *original = AutoACOriginalImageURL(url);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSInteger status = 0;
        NSData *data = AutoACHTTP([NSURLRequest requestWithURL:original], &status);
        if (status != 200 || data.length < 500) data = AutoACHTTP([NSURLRequest requestWithURL:url], &status);
        dispatch_async(dispatch_get_main_queue(), ^{
            [gHub removeFromSuperview];
            sender.enabled = YES;
            if (data.length < 500) {
                AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemRedColor, AutoACT(@"Không tải được ảnh"), @"", 2.6);
                return;
            }
            AutoACPhotosAdd(^{
                PHAssetCreationRequest *r = [PHAssetCreationRequest creationRequestForAsset];
                [r addResourceWithType:PHAssetResourceTypePhoto data:data options:nil];
            }, ^(BOOL ok) {
                if (ok) AutoACShowHub(@"checkmark.circle.fill", UIColor.systemGreenColor, AutoACT(@"Đã lưu ảnh vào Ảnh"), @"", 2.0);
                else AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor, AutoACT(@"Không lưu được, hãy cấp quyền Ảnh"), @"", 2.8);
            });
        });
    });
}
@end

static void AutoACAttachPostSaveButton(UIView *container) {
    UIButton *existing = objc_getAssociatedObject(container, &kAutoACPostSaveKey);
    if (existing && existing.superview == container) { [container bringSubviewToFront:existing]; return; }
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    [button setImage:[UIImage systemImageNamed:@"square.and.arrow.down" withConfiguration:cfg] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.accessibilityLabel = AutoACT(@"Lưu vào Ảnh");
    button.layer.shadowColor = UIColor.blackColor.CGColor;
    button.layer.shadowOpacity = 0.5f;
    button.layer.shadowRadius = 3;
    button.layer.shadowOffset = CGSizeZero;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:AutoACPostSaveTarget.shared action:@selector(saveTapped:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(container, &kAutoACPostSaveKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [container addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [button.topAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.topAnchor constant:8],
        [button.widthAnchor constraintEqualToConstant:44],
        [button.heightAnchor constraintEqualToConstant:44]]];
}

static void AutoACShowCopyMenu(void) {
    NSString *videoID = AutoACCurrentVideoID();
    if (videoID.length == 0) {
        AutoACShowHub(@"play.slash.fill", UIColor.systemOrangeColor, AutoACT(@"Hãy mở một video trước"), @"", 2.2);
        return;
    }
    double seconds = AutoACCurrentTime();
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:AutoACT(@"Liên kết video")];
    BOOL hasTime = seconds >= 1;
    if (hasTime) [names addObject:AutoACT(@"Liên kết tại thời điểm này")];
    [names addObjectsFromArray:@[AutoACT(@"Tiêu đề"), AutoACT(@"Mô tả"), AutoACT(@"Phụ đề"), AutoACT(@"Phụ đề kèm thời gian"), AutoACT(@"Phụ đề dịch theo ngôn ngữ thiết bị")]];
    AutoACPresentSheet(AutoACT(@"Sao chép"), nil, names, ^(NSInteger i) {
        NSString *name = names[i];
        NSString *link = [@"https://youtu.be/" stringByAppendingString:videoID];
        if ([name isEqualToString:AutoACT(@"Liên kết video")]) {
            AutoACCopyText(link, AutoACT(@"Đã sao chép liên kết"));
        } else if (hasTime && [name isEqualToString:AutoACT(@"Liên kết tại thời điểm này")]) {
            AutoACCopyText([link stringByAppendingFormat:@"?t=%ld", (long)seconds], AutoACT(@"Đã sao chép liên kết"));
        } else if ([name isEqualToString:AutoACT(@"Phụ đề")]) {
            AutoACCopySubtitles(NO, nil);
        } else if ([name isEqualToString:AutoACT(@"Phụ đề kèm thời gian")]) {
            AutoACCopySubtitles(YES, nil);
        } else if ([name isEqualToString:AutoACT(@"Phụ đề dịch theo ngôn ngữ thiết bị")]) {
            {
                NSString *code = AutoACDeviceLangCode();
                if ([code isEqualToString:@"zh-CN"]) code = @"zh-Hans"; else if ([code isEqualToString:@"zh-TW"]) code = @"zh-Hant";
                AutoACCopySubtitles(NO, code);
            }
        } else {
            BOOL wantTitle = [name isEqualToString:AutoACT(@"Tiêu đề")];
            AutoACWithPlayerInfo(^(NSDictionary *json, NSString *vid) {
                NSString *text = wantTitle ? json[@"videoDetails"][@"title"] : json[@"videoDetails"][@"shortDescription"];
                AutoACCopyText([text isKindOfClass:NSString.class] ? text : nil,
                               wantTitle ? AutoACT(@"Đã sao chép tiêu đề") : AutoACT(@"Đã sao chép mô tả"));
            });
        }
    });
}

// Luồng có sẵn âm thanh + hình để mở bằng trình phát ngoài: muxed tốt nhất, không có thì HLS
static NSString *AutoACPlayableURL(NSDictionary *json) {
    NSDictionary *streaming = json[@"streamingData"];
    if (![streaming isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *best = nil;
    for (NSDictionary *f in streaming[@"formats"]) {
        if (![f[@"url"] isKindOfClass:NSString.class]) continue;
        if (!best || [f[@"height"] integerValue] > [best[@"height"] integerValue]) best = f;
    }
    if (best) return best[@"url"];
    NSString *hls = streaming[@"hlsManifestUrl"];
    return [hls isKindOfClass:NSString.class] && hls.length > 0 ? hls : nil;
}

static NSString *AutoACEscapeForQuery(NSString *value) {
    NSMutableCharacterSet *allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [allowed removeCharactersInString:@"&=+?:/#%"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static void AutoACShowExternalMenu(void) {
    double seconds = AutoACCurrentTime();
    AutoACWithPlayerInfo(^(NSDictionary *json, NSString *videoID) {
        NSString *url = AutoACPlayableURL(json);
        if (url.length == 0) {
            AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemRedColor,
                          AutoACT(@"Video này không có luồng để phát ngoài"), @"", 3.0);
            return;
        }
        NSString *title = json[@"videoDetails"][@"title"];
        AutoACPresentSheet(AutoACT(@"Phát bằng"), [title isKindOfClass:NSString.class] ? title : nil,
                           @[AutoACT(@"Trình phát hệ thống"), @"Infuse", @"VLC"], ^(NSInteger i) {
            if (i == 0) {
                AutoACPausePlayer();
                AVPlayer *player = [AVPlayer playerWithURL:[NSURL URLWithString:url]];
                AVPlayerViewController *controller = [AVPlayerViewController new];
                controller.player = player;
                controller.allowsPictureInPicturePlayback = YES;
                if (seconds > 1) {
                    [player seekToTime:CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC)
                       toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
                }
                [AutoACTopViewController() presentViewController:controller animated:YES completion:^{ [player play]; }];
                // Luồng bị từ chối hoặc hỏng thì trình phát chỉ đen màn hình: báo lỗi và đóng lại
                __weak AVPlayerViewController *weakController = controller;
                for (NSNumber *delay in @[@2.5, @7.0]) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        AVPlayerViewController *c = weakController;
                        if (c && c.presentingViewController && player.currentItem.status == AVPlayerItemStatusFailed) {
                            AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemRedColor, AutoACT(@"Không phát được luồng này"), @"", 3.0);
                            [c dismissViewControllerAnimated:YES completion:nil];
                        }
                    });
                }
                return;
            }
            NSString *scheme = (i == 1) ? @"infuse://x-callback-url/play?url=" : @"vlc-x-callback://x-callback-url/stream?url=";
            NSString *link = [scheme stringByAppendingString:AutoACEscapeForQuery(url)];
            if (i == 1 && seconds >= 1) link = [link stringByAppendingFormat:@"&position=%ld", (long)seconds];   // Infuse có tham số position (giây); VLC không có
            NSURL *open = [NSURL URLWithString:link];
            AutoACPausePlayer();
            [UIApplication.sharedApplication openURL:open options:@{} completionHandler:^(BOOL ok) {
                if (!ok) {
                    AutoACResumePlayer();   // không mở được app: trả lại trạng thái đang phát
                    AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor,
                                  i == 1 ? AutoACT(@"Chưa cài Infuse") : AutoACT(@"Chưa cài VLC"), @"", 2.6);
                }
            }];
        });
    });
}

static void AutoACSaveThumbnail(void) {
    NSString *videoID = AutoACCurrentVideoID();
    if (videoID.length == 0) {
        AutoACShowHub(@"play.slash.fill", UIColor.systemOrangeColor, AutoACT(@"Hãy mở một video trước"), @"", 2.4);
        return;
    }
    AutoACShowHub(@"photo", UIColor.systemBlueColor, AutoACT(@"Đang tải ảnh bìa"), @"", 60);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *image = nil;
        for (NSString *name in @[@"maxresdefault", @"sddefault", @"hqdefault"]) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/%@.jpg", videoID, name]];
            NSInteger status = 0;
            NSData *data = AutoACHTTP([NSURLRequest requestWithURL:url], &status);
            if (status == 200 && data.length > 2000) image = [UIImage imageWithData:data];
            if (image) break;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!image) {
                AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemRedColor, AutoACT(@"Không tải được ảnh bìa"), @"", 2.8);
                return;
            }
            AutoACPhotosAdd(^{ [PHAssetChangeRequest creationRequestForAssetFromImage:image]; }, ^(BOOL ok) {
                if (ok) AutoACShowHub(@"checkmark.circle.fill", UIColor.systemGreenColor, AutoACT(@"Đã lưu ảnh bìa vào Ảnh"), @"", 2.0);
                else AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor,
                                   AutoACT(@"Không lưu được, hãy cấp quyền Ảnh"), @"", 2.8);
            });
        });
    });
}


#pragma mark - Tốc độ mở video, tua chạm đúp, mở ở trạng thái tạm dừng (theo ytkace)

// Gửi tốc độ cho đối tượng có setPlaybackRate: / setRate:, đi dần qua eventsDelegate, playbackController...
static BOOL AutoACDeliverRate(id target, NSString *name, double rate) {
    SEL selector = NSSelectorFromString(name);
    if (![target respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 3) return NO;
    switch ([signature getArgumentTypeAtIndex:2][0]) {
        case 'd': ((void (*)(id, SEL, double))objc_msgSend)(target, selector, rate); return YES;
        case 'f': ((void (*)(id, SEL, float))objc_msgSend)(target, selector, (float)rate); return YES;
        default: return NO;
    }
}

static BOOL AutoACApplyRate(id object, double rate, NSInteger depth) {
    if (!object || depth > 2) return NO;
    if (AutoACDeliverRate(object, @"setPlaybackRate:", rate)) return YES;
    if (depth == 0 && AutoACDeliverRate(object, @"setRate:", rate)) return YES;
    for (NSString *name in @[@"eventsDelegate", @"playbackController", @"playerController"]) {
        SEL selector = NSSelectorFromString(name);
        if (![object respondsToSelector:selector]) continue;
        id child = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        if (child != object && AutoACApplyRate(child, rate, depth + 1)) return YES;
    }
    return NO;
}


static NSString *AutoACRateName(double rate) {
    return rate <= 0 ? AutoACT(@"Theo YouTube") : [NSString stringWithFormat:@"%gx", rate];
}

// Một tuỳ chọn số: hiện bảng chọn, lưu vào `key`
static void AutoACPickNumber(NSString *title, NSString *key, NSArray<NSNumber *> *values,
                             NSString *(^nameFor)(double)) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSNumber *v in values) [names addObject:nameFor(v.doubleValue)];
    double current = [kPrefs doubleForKey:key];
    AutoACPresentSheet(title, [AutoACT(@"Hiện tại: ") stringByAppendingString:nameFor(current)], names, ^(NSInteger i) {
        [kPrefs setDouble:values[i].doubleValue forKey:key];
        AutoACShowHub(@"checkmark.circle.fill", UIColor.systemGreenColor, names[i], @"", 1.6);
    });
}

static void AutoACShowPlaybackSettings(void) {
    NSString *rateLine = [AutoACT(@"Tốc độ khi mở video: ") stringByAppendingString:AutoACRateName([kPrefs doubleForKey:kStartRateKey])];
    double tap = [kPrefs doubleForKey:kDoubleTapKey];
    NSString *tapLine = [AutoACT(@"Tua chạm đúp: ") stringByAppendingString:tap > 0 ? [NSString stringWithFormat:AutoACT(@"%g giây"), tap] : AutoACT(@"Theo YouTube")];
    AutoACPresentSheet(AutoACT(@"Tốc độ và tua"), nil, @[rateLine, tapLine], ^(NSInteger i) {
        if (i == 0) {
            AutoACPickNumber(AutoACT(@"Tốc độ khi mở video"), kStartRateKey, @[@0, @0.5, @0.75, @1, @1.25, @1.5, @1.75, @2, @2.5, @3],
                             ^NSString *(double v) { return AutoACRateName(v); });
        } else {
            AutoACPickNumber(AutoACT(@"Tua khi chạm đúp"), kDoubleTapKey, @[@0, @5, @10, @15, @20, @30, @45, @60],
                             ^NSString *(double v) { return v > 0 ? [NSString stringWithFormat:AutoACT(@"%g giây"), v] : AutoACT(@"Theo YouTube"); });
        }
    });
}

#pragma mark - SponsorBlock (theo ytkace): tự bỏ qua đoạn tài trợ, tự quảng bá...

static NSArray<NSDictionary<NSString *, NSString *> *> *AutoACSponsorCategories(void) {
    return @[@{@"id": @"sponsor", @"desc": AutoACT(@"Quảng cáo trả phí trong video"), @"name": AutoACT(@"Tài trợ")},
             @{@"id": @"selfpromo", @"desc": AutoACT(@"Tự giới thiệu hàng, kênh"), @"name": AutoACT(@"Tự quảng bá")},
             @{@"id": @"interaction", @"desc": AutoACT(@"Xin thích, đăng ký, theo dõi"), @"name": AutoACT(@"Nhắc tương tác (like, đăng ký)")},
             @{@"id": @"intro", @"desc": AutoACT(@"Đoạn mở đầu lặp lại"), @"name": AutoACT(@"Đoạn mở đầu")},
             @{@"id": @"outro", @"desc": AutoACT(@"Màn hình kết, credit"), @"name": AutoACT(@"Đoạn kết, credit")},
             @{@"id": @"preview", @"desc": AutoACT(@"Cảnh xem trước, tóm tắt"), @"name": AutoACT(@"Xem trước, tóm tắt")},
             @{@"id": @"music_offtopic", @"desc": AutoACT(@"Đoạn nói trong video nhạc"), @"name": AutoACT(@"Phần không phải nhạc")},
             @{@"id": @"filler", @"desc": AutoACT(@"Đoạn lan man, ít quan trọng"), @"name": AutoACT(@"Đoạn thừa")}];
}

static NSArray<NSString *> *AutoACSponsorEnabled(void) {
    NSArray *stored = [kPrefs arrayForKey:kSponsorCatsKey];
    return stored ?: @[@"sponsor", @"selfpromo", @"interaction", @"intro", @"outro"];
}

static NSString *gSponsorVideo = nil;
static NSArray<NSDictionary *> *gSponsorSegments = nil;
static NSMutableSet<NSString *> *gSponsorSkipped = nil;

static void AutoACSponsorLoad(NSString *videoID) {
    if (![kPrefs boolForKey:kSponsorKey] || videoID.length == 0) return;
    if ([videoID isEqualToString:gSponsorVideo]) return;
    gSponsorVideo = [videoID copy];
    gSponsorSegments = nil;
    gSponsorSkipped = [NSMutableSet set];
    NSArray<NSString *> *cats = AutoACSponsorEnabled();
    if (cats.count == 0) return;
    NSData *catData = [NSJSONSerialization dataWithJSONObject:cats options:0 error:nil];
    NSURLComponents *c = [NSURLComponents componentsWithString:@"https://sponsor.ajay.app/api/skipSegments"];
    c.queryItems = @[[NSURLQueryItem queryItemWithName:@"videoID" value:videoID],
                     [NSURLQueryItem queryItemWithName:@"categories"
                                                 value:[[NSString alloc] initWithData:catData encoding:NSUTF8StringEncoding]]];
    if (!c.URL) return;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:c.URL];
    request.timeoutInterval = 10;
    NSString *requested = [videoID copy];
    [[NSURLSession.sharedSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || ((NSHTTPURLResponse *)response).statusCode != 200 || data.length == 0 || data.length > 1048576) return;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:NSArray.class]) return;
        NSMutableArray *list = [NSMutableArray array];
        for (id item in (NSArray *)json) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            id category = item[@"category"], values = item[@"segment"], action = item[@"actionType"];
            if (![category isKindOfClass:NSString.class] || ![cats containsObject:category]) continue;
            if ([action isKindOfClass:NSString.class] && ![action isEqualToString:@"skip"]) continue;
            if (![values isKindOfClass:NSArray.class] || [values count] != 2) continue;
            double start = [values[0] doubleValue], end = [values[1] doubleValue];
            if (start < 0 || end <= start) continue;
            [list addObject:@{@"start": @(start), @"end": @(end), @"category": category,
                              @"id": [NSString stringWithFormat:@"%.2f-%.2f", start, end]}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([requested isEqualToString:gSponsorVideo]) gSponsorSegments = list;
        });
    }] resume];
}

// Tua tới `seconds` bằng seekToTime: chỉ khi tham số đúng là số thực (double/float). Chữ ký khác (vd CMTime) thì bỏ qua,
// vì truyền sai kiểu qua objc_msgSend làm hỏng đối số hoặc sập app.
static BOOL AutoACSeekSeconds(id player, double seconds) {
    SEL seek = NSSelectorFromString(@"seekToTime:");
    if (!player || ![player respondsToSelector:seek]) return NO;
    Method m = class_getInstanceMethod([player class], seek);
    if (!m) return NO;
    char type[16] = {0};
    method_getArgumentType(m, 2, type, sizeof(type));
    if (type[0] == 'd') ((void (*)(id, SEL, double))objc_msgSend)(player, seek, seconds);
    else if (type[0] == 'f') ((void (*)(id, SEL, float))objc_msgSend)(player, seek, (float)seconds);
    else return NO;
    return YES;
}

static void AutoACSponsorEvaluate(id player, double time) {
    NSArray<NSDictionary *> *segments = gSponsorSegments;
    if (segments.count == 0 || ![kPrefs boolForKey:kSponsorKey]) return;
    for (NSDictionary *seg in segments) {
        double start = [seg[@"start"] doubleValue], end = [seg[@"end"] doubleValue];
        if (time < start || time >= end - 0.4) continue;
        if ([gSponsorSkipped containsObject:seg[@"id"]]) continue;
        [gSponsorSkipped addObject:seg[@"id"]];
        if (!AutoACSeekSeconds(player, end)) return;
        if (![kPrefs boolForKey:kSponsorAlertKey]) return;
        NSString *name = seg[@"category"];
        for (NSDictionary *d in AutoACSponsorCategories()) if ([d[@"id"] isEqualToString:name]) name = d[@"name"];
        dispatch_async(dispatch_get_main_queue(), ^{
            AutoACShowHub(@"forward.end.fill", UIColor.systemGreenColor, AutoACT(@"Đã bỏ qua"), name, 2.0);
        });
        return;
    }
}

static void AutoACShowMenu(CGPoint anchor);
static CGPoint gLastMenuAnchor;
static UILabel *AutoACLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color);

// ── Khung bảng phụ dùng chung (Sponsor block, Tuỳ chỉnh tab): nút quay lại tròn kính, tiêu đề cân giữa,
//    nút Mặc định là icon bên phải đầu khung ──
static void AutoACShowPanel(NSString *titleText, NSString *subText, UIView *content, CGFloat top,
                            NSString *resetTitle, void (^reset)(void)) {
    UIWindow *window = AutoACKeyWindow();
    if (!window || gMenu) return;
    if (CACurrentMediaTime() - gDismissStamp < 0.3) { gNavDir = 1; gNavStamp = CACurrentMediaTime(); }   // mở ngay sau menu: chuyển trang kiểu đẩy

    UIButton *backdrop = [UIButton buttonWithType:UIButtonTypeCustom];
    backdrop.frame = window.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backdrop.backgroundColor = UIColor.clearColor;
    [backdrop addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { AutoACDismissMenu(); }]
       forControlEvents:UIControlEventTouchUpInside];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    AutoACStyleShadow(card, 0.22, 20, CGSizeMake(0, 8));
    UIVisualEffectView *blur = AutoACMakeGlass(28);
    [card addSubview:blur];

    // Thanh tiêu đề
    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    UIVisualEffectView *backGlass = AutoACMakeGlass(19);
    backGlass.translatesAutoresizingMaskIntoConstraints = NO;
    backGlass.layer.cornerRadius = 19;
    backGlass.clipsToBounds = YES;
    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    back.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    [back setImage:[UIImage systemImageNamed:@"chevron.left" withConfiguration:cfg] forState:UIControlStateNormal];
    back.tintColor = UIColor.labelColor;
    back.accessibilityLabel = AutoACT(@"Quay lại menu");
    [back addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        // Quay lại kiểu iOS: bảng trượt sang phải, menu trượt vào từ trái; menu hiện ngay nên không lộ nền YouTube
        UIView *old = gMenu;
        gMenu = nil;
        gNavDir = -1; gNavStamp = CACurrentMediaTime();
        [[UISelectionFeedbackGenerator new] selectionChanged];
        AutoACShowMenu(gLastMenuAnchor);
        old.userInteractionEnabled = NO;
        CGFloat ow = CGRectGetWidth(old.bounds);
        [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:1.0 initialSpringVelocity:0
                            options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            old.alpha = 0;
            for (UIView *v in old.subviews) v.transform = CGAffineTransformMakeScale(0.95, 0.95);
        } completion:^(BOOL finished) { [old removeFromSuperview]; }];
    }] forControlEvents:UIControlEventTouchUpInside];
    [backGlass.contentView addSubview:back];
    UILabel *title = AutoACLabel(titleText, 17, UIFontWeightBold, UIColor.labelColor);
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.textAlignment = NSTextAlignmentCenter;
    UILabel *sub = AutoACLabel(subText, 11.5, UIFontWeightRegular, UIColor.secondaryLabelColor);
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    sub.textAlignment = NSTextAlignmentCenter;
    [header addSubview:backGlass];
    [header addSubview:title];
    [header addSubview:sub];

    content.translatesAutoresizingMaskIntoConstraints = NO;
    [blur.contentView addSubview:header];
    [blur.contentView addSubview:content];
    [backdrop addSubview:card];
    [window addSubview:backdrop];
    gMenu = backdrop;

    AutoACPinCardWidth(card, window);
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:backdrop.centerXAnchor],
        [card.widthAnchor constraintLessThanOrEqualToConstant:kMenuMaxWidth],
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:backdrop.safeAreaLayoutGuide.leadingAnchor constant:16],
        [card.topAnchor constraintEqualToAnchor:backdrop.topAnchor constant:top],
        [card.bottomAnchor constraintLessThanOrEqualToAnchor:backdrop.safeAreaLayoutGuide.bottomAnchor constant:-24],
        [blur.topAnchor constraintEqualToAnchor:card.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [header.topAnchor constraintEqualToAnchor:blur.contentView.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:60],
        [backGlass.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:14],
        [backGlass.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [backGlass.widthAnchor constraintEqualToConstant:38],
        [backGlass.heightAnchor constraintEqualToConstant:38],
        [back.topAnchor constraintEqualToAnchor:backGlass.contentView.topAnchor],
        [back.bottomAnchor constraintEqualToAnchor:backGlass.contentView.bottomAnchor],
        [back.leadingAnchor constraintEqualToAnchor:backGlass.contentView.leadingAnchor],
        [back.trailingAnchor constraintEqualToAnchor:backGlass.contentView.trailingAnchor],
        [title.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor constant:-8],
        [sub.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1],
        [content.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:blur.contentView.bottomAnchor constant:-8],
    ]];

    // Nút Mặc định: icon kính tròn bên phải đầu khung, đối diện nút "<" (chạm ra ngoài khung để đóng)
    if (reset) {
        UIVisualEffectView *resetGlass = AutoACMakeGlass(19);
        resetGlass.translatesAutoresizingMaskIntoConstraints = NO;
        resetGlass.layer.cornerRadius = 19;
        resetGlass.clipsToBounds = YES;
        UIButton *rb = [UIButton buttonWithType:UIButtonTypeSystem];
        rb.translatesAutoresizingMaskIntoConstraints = NO;
        [rb setImage:[UIImage systemImageNamed:@"arrow.counterclockwise" withConfiguration:cfg] forState:UIControlStateNormal];
        rb.tintColor = UIColor.systemRedColor;
        rb.accessibilityLabel = resetTitle ?: AutoACT(@"Mặc định");
        [rb addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { reset(); }]
     forControlEvents:UIControlEventTouchUpInside];
        [resetGlass.contentView addSubview:rb];
        [header addSubview:resetGlass];
        [NSLayoutConstraint activateConstraints:@[
            [resetGlass.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-14],
            [resetGlass.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [resetGlass.widthAnchor constraintEqualToConstant:38],
            [resetGlass.heightAnchor constraintEqualToConstant:38],
            [rb.topAnchor constraintEqualToAnchor:resetGlass.contentView.topAnchor],
            [rb.bottomAnchor constraintEqualToAnchor:resetGlass.contentView.bottomAnchor],
            [rb.leadingAnchor constraintEqualToAnchor:resetGlass.contentView.leadingAnchor],
            [rb.trailingAnchor constraintEqualToAnchor:resetGlass.contentView.trailingAnchor],
        ]];
    }

    [window layoutIfNeeded];
    AutoACPopIn(card, backdrop);
}

static void AutoACShowSponsorCategories(void) {
    UIWindow *window = AutoACKeyWindow();
    if (!window || gMenu) return;

    UIStackView *rows = [[UIStackView alloc] init];
    rows.axis = UILayoutConstraintAxisVertical;
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *enabled = AutoACSponsorEnabled();
    for (NSDictionary *d in AutoACSponsorCategories()) {
        UIView *row = [[UIView alloc] init];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        UILabel *name = AutoACLabel(d[@"name"], 15.5, UIFontWeightMedium, UIColor.labelColor);
        name.translatesAutoresizingMaskIntoConstraints = NO;
        UILabel *note = AutoACLabel(d[@"desc"] ?: @"", 11.5, UIFontWeightRegular, UIColor.secondaryLabelColor);
        note.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:note];
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.translatesAutoresizingMaskIntoConstraints = NO;
        toggle.on = [enabled containsObject:d[@"id"]];
        NSString *cat = d[@"id"];
        [toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
            NSMutableArray *list = [AutoACSponsorEnabled() mutableCopy];
            if (toggle.on) { if (![list containsObject:cat]) [list addObject:cat]; } else [list removeObject:cat];
            [kPrefs setObject:list forKey:kSponsorCatsKey];
            gSponsorVideo = nil;   // tải lại đoạn cho video hiện tại
            AutoACSponsorLoad(AutoACCurrentVideoID());
        }] forControlEvents:UIControlEventValueChanged];
        UIView *line = [[UIView alloc] init];
        line.translatesAutoresizingMaskIntoConstraints = NO;
        line.backgroundColor = [UIColor.separatorColor colorWithAlphaComponent:0.5];
        [row addSubview:name]; [row addSubview:toggle]; [row addSubview:line];
        [NSLayoutConstraint activateConstraints:@[
            [row.heightAnchor constraintEqualToConstant:58],
            [name.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
            [name.bottomAnchor constraintEqualToAnchor:row.centerYAnchor constant:1],
            [name.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-10],
            [note.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
            [note.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:1],
            [note.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-10],
            [toggle.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14],
            [toggle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [line.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
            [line.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [line.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
            [line.heightAnchor constraintEqualToConstant:0.5]]];
        [rows addArrangedSubview:row];
    }
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = NO;
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [scroll addSubview:rows];
    NSLayoutConstraint *fit = [scroll.heightAnchor constraintEqualToAnchor:rows.heightAnchor];
    fit.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        fit,
        [rows.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [rows.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [rows.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [rows.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [rows.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];
    CGFloat top = MIN(MAX(gLastMenuAnchor.y + 24, window.safeAreaInsets.top + 8), CGRectGetHeight(window.bounds) * 0.35);
    AutoACShowPanel(@"Sponsor block", AutoACT(@"Chọn loại đoạn tự bỏ qua"), scroll, top, AutoACT(@"Mặc định"), ^{
        [kPrefs removeObjectForKey:kSponsorCatsKey];
        gSponsorVideo = nil;
        AutoACSponsorLoad(AutoACCurrentVideoID());
        AutoACDismissMenu();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ AutoACShowSponsorCategories(); });
    });
}

#pragma mark - Dữ liệu chức năng cho menu

@interface AutoACItem : NSObject
@property (nonatomic, copy) NSString *category, *title, *sub, *desc, *symbol, *key;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, copy) void (^onChange)(void);
@property (nonatomic, copy) void (^action)(void);
@property (nonatomic, copy) NSString *sortKey;   // khoá xếp thứ tự thay cho tên (khi muốn đặt mục ngay dưới một mục khác)
@property (nonatomic) BOOL inlineRow;   // hành động xếp xen giữa các công tắc của nhóm
@end
@implementation AutoACItem
@end

#define kCatQuick (AutoACT(@"Tác vụ nhanh"))
#define kCatPlayer (AutoACT(@"Trong trình phát"))   // chức năng gắn vào nút AutoAC trên trình phát

static AutoACItem *ACSwitch(NSString *category, NSString *title, NSString *sub, NSString *symbol,
                            UIColor *color, NSString *key, NSString *desc, void (^onChange)(void)) {
    AutoACItem *i = [AutoACItem new];
    i.category = category; i.title = title; i.sub = sub; i.symbol = symbol;
    i.color = color; i.key = key; i.desc = desc; i.onChange = onChange;
    return i;
}

static AutoACItem *ACAction(NSString *title, NSString *sub, NSString *symbol, UIColor *color,
                            NSString *desc, void (^action)(void)) {
    AutoACItem *i = [AutoACItem new];
    i.category = kCatQuick; i.title = title; i.sub = sub; i.symbol = symbol;
    i.color = color; i.desc = desc; i.action = action;
    return i;
}

// Xếp A-Z theo tiếng Việt: Đ đứng ngay sau D; so từng chữ cái không dấu trước, dấu thanh chỉ phân định khi trùng
static NSComparisonResult AutoACCompareVI(NSString *a, NSString *b) {
    NSString *(^base)(NSString *) = ^NSString *(NSString *t) {
        NSString *l = [t lowercaseString];
        l = [l stringByReplacingOccurrencesOfString:@"đ" withString:@"d{"];   // '{' lớn hơn mọi chữ cái: Đ sau D
        return [l stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:nil];
    };
    NSComparisonResult r = [base(a) compare:base(b)];
    if (r != NSOrderedSame) return r;
    return [a compare:b options:NSCaseInsensitiveSearch range:NSMakeRange(0, a.length) locale:[NSLocale localeWithLocaleIdentifier:@"vi_VN"]];
}

static NSArray<AutoACItem *> *AutoACSortedItems(NSArray<AutoACItem *> *items) {
    return [items sortedArrayUsingComparator:^NSComparisonResult(AutoACItem *a, AutoACItem *b) {
        return AutoACCompareVI(a.sortKey ?: a.title, b.sortKey ?: b.title);
    }];
}

static NSArray<NSString *> *AutoACAllPrefKeys(void) {
    NSMutableArray<NSString *> *collapsed = [NSMutableArray array];
    for (NSString *k in kPrefs.dictionaryRepresentation.allKeys) if ([k hasPrefix:@"kCollapsed."]) [collapsed addObject:k];
    return [collapsed arrayByAddingObjectsFromArray:@[kAutoClearCacheKey, kHideShortsKey, kYTXAdsKey, kYTXBackgroundKey, kLoopKey, kAutoplayOffKey, kAskQualityKey, kShareAfterKey,
             kAskDestKey, kHidePromosKey, kHidePaidPromoKey, kShortsFullBleedKey, kGlassTopKey, kGlassSheetKey, kGlassPlayerKey, kZoomFreeKey, kNoLaunchAnimKey, kOpenPausedKey, kStartRateKey, kDoubleTapKey,
             kShortsLikeKey, kShortsCommentKey, kShortsShareKey, kShortsSaveKey, kShortsRemixKey, kShortsSoundKey,
             kShortsPauseCardKey, kHideCommunityKey, kHideMixesKey, kHideGamesKey, kHideShopTagKey, kHideShortsShelfKey, kSponsorKey, kSponsorCatsKey, kSponsorAlertKey,
             kPlayerButtonKey, kCommentToolsKey, kPostImageKey, kPlayerFloatKey, kShortsNoScrollKey, kShortsNoLoopKey, kPlayFixKey, kNoAutoplayKey, kPlayerSpeedBtnKey, kPlayerPiPKey, kPlayerSleepBtnKey, kPlayerExternalKey, kPlayerQualityKey, kPlayerLoopKey, kOverlayTopKey, kOverlayBottomKey]];
}

static void AutoACRestartHint(void) {
    AutoACShowHub(@"arrow.clockwise", UIColor.systemOrangeColor, AutoACT(@"Mở lại app để áp dụng"), @"", 2.2);
}

#pragma mark - Sao lưu và khôi phục cài đặt (giống YTLite: xuất/nhập tệp)

// Chỉ nhận khoá của AutoAC khi khôi phục, để tệp lạ không ghi được cài đặt tuỳ ý
static BOOL AutoACBackupKeyAllowed(NSString *k) {
    return [k hasPrefix:@"ACG.Preference."] || [k hasPrefix:@"kCollapsed."] || [AutoACAllPrefKeys() containsObject:k];
}

static void AutoACExportSettings(void) {
    NSDictionary *all = kPrefs.dictionaryRepresentation;
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSString *k in all.allKeys) if (AutoACBackupKeyAllowed(k)) settings[k] = all[k];
    NSDictionary *root = @{@"AutoACBackup": @1, @"build": kCurrentBuildID ?: @"", @"settings": settings};
    NSError *err = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:root format:NSPropertyListXMLFormat_v1_0 options:0 error:&err];
    // Thư mục và tên tệp không chứa "AutoAC-" để bộ dọn cache không coi là tệp tải xuống bỏ lại
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"AutoACBackup"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"yyyyMMdd_HHmm";
    NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"AutoAC_settings_%@.plist", [f stringFromDate:NSDate.date]]];
    if (!data || ![data writeToFile:path atomically:YES]) {
        AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemRedColor, AutoACT(@"Không tạo được tệp sao lưu"), @"", 2.6);
        return;
    }
    UIViewController *top = AutoACTopViewController();
    if (!top) return;
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    share.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *e) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    };
    share.popoverPresentationController.sourceView = top.view;
    share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMaxY(top.view.bounds) - 1, 1, 1);
    [top presentViewController:share animated:YES completion:nil];
}

@interface AutoACSettingsImporter : NSObject <UIDocumentPickerDelegate>
+ (instancetype)shared;
@end
@implementation AutoACSettingsImporter
+ (instancetype)shared { static AutoACSettingsImporter *i; static dispatch_once_t o; dispatch_once(&o, ^{ i = [AutoACSettingsImporter new]; }); return i; }
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (scoped) [url stopAccessingSecurityScopedResource];
    id root = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil] : nil;
    NSDictionary *settings = [root isKindOfClass:NSDictionary.class] && root[@"AutoACBackup"] ? root[@"settings"] : nil;
    if (![settings isKindOfClass:NSDictionary.class]) {
        AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemRedColor, AutoACT(@"Tệp sao lưu không hợp lệ"), @"", 2.8);
        return;
    }
    NSUInteger applied = 0;
    for (NSString *k in settings) {
        id v = settings[k];
        if (![k isKindOfClass:NSString.class] || !AutoACBackupKeyAllowed(k)) continue;
        if (!([v isKindOfClass:NSNumber.class] || [v isKindOfClass:NSString.class] || [v isKindOfClass:NSArray.class] || [v isKindOfClass:NSDictionary.class])) continue;
        [kPrefs setObject:v forKey:k];
        applied++;
    }
    AutoACShowHub(@"checkmark.circle.fill", UIColor.systemGreenColor, AutoACT(@"Đã khôi phục cài đặt"),
                  [NSString stringWithFormat:@"%lu · %@", (unsigned long)applied, AutoACT(@"Mở lại app để áp dụng")], 3.0);
}
@end

static void AutoACImportSettings(void) {
    UIViewController *top = AutoACTopViewController();
    if (!top) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
    picker.delegate = AutoACSettingsImporter.shared;
    [top presentViewController:picker animated:YES completion:nil];
}

#pragma mark - Thanh tab và Liquid Glass (chuyển từ ytkace, đổi tiền tố YTKACE → ACG)

// ── Phần phụ trợ thay cho các hàm ngoài của ytkace ──
#define ACGDebugLog(tag, ...) do { } while (0)
#define ACGDownloadLog(tag, ...) do { } while (0)
static BOOL ACGDebugLogsEnabled(void) { return NO; }
static BOOL ACGMasterEnabled(void) { return YES; }
static BOOL ACGFeatureEnabled(NSString *key) { return key.length != 0 && [kPrefs boolForKey:key]; }
static id ACGPreferenceObject(NSString *key) { return key.length != 0 ? [kPrefs objectForKey:key] : nil; }
static void ACGSetPreference(NSString *key, BOOL value) { if (key.length) [kPrefs setBool:value forKey:key]; }
static void ACGSetPreferenceObject(NSString *key, id value) {
    if (!key.length) return;
    if (value) [kPrefs setObject:value forKey:key]; else [kPrefs removeObjectForKey:key];
}
static UIImage *ACGAssetImage(NSString *name, NSString *fallbackSymbol) {
    (void)name;
    return fallbackSymbol.length ? [UIImage systemImageNamed:fallbackSymbol] : nil;
}

static NSMutableSet<NSString *> *gACGHookKeys;
static BOOL ACGInstallHook(NSString *className, NSString *selectorName, BOOL classMethod, IMP replacement, IMP *originalStorage) {
    if (className.length == 0 || selectorName.length == 0 || replacement == NULL) return NO;
    Class cls = NSClassFromString(className);
    if (cls == Nil) return NO;
    Class target = classMethod ? object_getClass(cls) : cls;
    if (target == Nil) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(target, selector);
    if (method == NULL) return NO;
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", className, classMethod ? @"+" : @"-", selectorName];
    @synchronized ([NSUserDefaults class]) {
        if (!gACGHookKeys) gACGHookKeys = [NSMutableSet set];
        if ([gACGHookKeys containsObject:key]) return YES;
        IMP original = method_getImplementation(method);
        const char *types = method_getTypeEncoding(method);
        if (!class_addMethod(target, selector, replacement, types)) {
            Method direct = class_getInstanceMethod(target, selector);
            if (direct == NULL) return NO;
            method_setImplementation(direct, replacement);
        }
        if (originalStorage) *originalStorage = original;
        [gACGHookKeys addObject:key];
        return YES;
    }
}
static BOOL ACGInstallInstanceHook(NSString *className, NSString *selectorName, IMP replacement, IMP *originalStorage) {
    return ACGInstallHook(className, selectorName, NO, replacement, originalStorage);
}
static BOOL ACGInstallClassHook(NSString *className, NSString *selectorName, IMP replacement, IMP *originalStorage) {
    return ACGInstallHook(className, selectorName, YES, replacement, originalStorage);
}

static NSInteger gACGTabSeen = -1, gACGTabShown = -1;
static BOOL gACGTabHooked = NO, gACGGlassHooked = NO;


static IMP OriginalSetPivotRenderer;
static IMP OriginalSetFloatingPivotRenderer;
static IMP OriginalPivotItemLayout;
static IMP OriginalPivotItemSetSelected;
static IMP OriginalPivotItemTraitChanged;
static IMP OriginalPivotLabelSetHidden;
static IMP OriginalPivotLabelSetAlpha;
static IMP OriginalPivotButtonLayout;
static IMP OriginalPivotBarLayout;
static IMP OriginalPivotControllerAppear;
static IMP OriginalSetDefaultSelectedPivot;
static BOOL ACGStartupNative;
static IMP OriginalPivotBarStyleColors;
static IMP OriginalPivotBarSetBackgroundStyle;


static const void *ACGDownloadsAssociation = &ACGDownloadsAssociation;
static const void *ACGTabAssociation = &ACGTabAssociation;
static const void *ACGTabSelectedAssociation = &ACGTabSelectedAssociation;
static const void *ACGTabDragOutAssociation = &ACGTabDragOutAssociation;
static BOOL ACGStencilRendering;

static NSInteger const ACGExtraIconTag = 0x59414349;
static NSInteger const ACGExtraLabelTag = 0x5941434A;
static BOOL ACGStartupApplied;
static NSString *ACGFirstVisiblePivot;


static id ACGValue(id receiver, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return receiver != nil && [receiver respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector)
        : nil;
}

static void ACGSetValue(id receiver, NSString *selectorName, id value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (receiver != nil && [receiver respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(receiver, selector, value);
    }
}

static id ACGNew(NSString *className) {
    Class cls = NSClassFromString(className);
    return cls == Nil ? nil : [[cls alloc] init];
}

static id ACGMakeBrowsePivotItem(NSString *browseID,
                                    NSString *title,
                                    NSInteger iconType) {
    Class rendererClass = NSClassFromString(@"YTIPivotBarRenderer");
    SEL factory = NSSelectorFromString(@"pivotSupportedRenderersWithBrowseId:title:iconType:");
    if (rendererClass != Nil && [rendererClass respondsToSelector:factory]) {
        id renderer = ((id (*)(id, SEL, id, id, NSInteger))objc_msgSend)(
            rendererClass, factory, browseID, title, iconType
        );
        id item = ACGValue(renderer, @"pivotBarItemRenderer");
        if (item != nil) {
            ACGSetValue(item, @"setPivotIdentifier:", browseID);
        }
        if (renderer != nil) {
            return renderer;
        }
    }
    id browseEndpoint = ACGNew(@"YTIBrowseEndpoint");
    id command = ACGNew(@"YTICommand");
    id itemRenderer = ACGNew(@"YTIPivotBarItemRenderer");
    id supportedRenderer = ACGNew(@"YTIPivotBarSupportedRenderers");
    Class formattedClass = NSClassFromString(@"YTIFormattedString");
    SEL formattedSelector = NSSelectorFromString(@"formattedStringWithString:");
    if (browseEndpoint == nil || command == nil || itemRenderer == nil ||
        supportedRenderer == nil || formattedClass == Nil ||
        ![formattedClass respondsToSelector:formattedSelector]) {
        return nil;
    }
    ACGSetValue(browseEndpoint, @"setBrowseId:", browseID);
    ACGSetValue(command, @"setBrowseEndpoint:", browseEndpoint);
    ACGSetValue(itemRenderer, @"setPivotIdentifier:", browseID);
    ACGSetValue(itemRenderer, @"setNavigationEndpoint:", command);
    id icon = ACGValue(itemRenderer, @"icon");
    SEL setIconType = NSSelectorFromString(@"setIconType:");
    if ([icon respondsToSelector:setIconType]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(icon, setIconType, iconType);
    }
    id formatted = ((id (*)(id, SEL, id))objc_msgSend)(
        formattedClass, formattedSelector, title
    );
    ACGSetValue(itemRenderer, @"setTitle:", formatted);
    ACGSetValue(supportedRenderer, @"setPivotBarItemRenderer:", itemRenderer);
    return supportedRenderer;
}

static NSInteger ACGInteger(id receiver, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return receiver != nil && [receiver respondsToSelector:selector]
        ? ((NSInteger (*)(id, SEL))objc_msgSend)(receiver, selector)
        : 0;
}

static id ACGTabValue(id receiver, NSArray<NSString *> *selectors) {
    for (NSString *name in selectors) {
        SEL selector = NSSelectorFromString(name);
        if ([receiver respondsToSelector:selector]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
            if (value != nil) {
                return value;
            }
        }
    }
    return nil;
}

static NSString *ACGTabToken(id item) {
    for (NSString *selectorName in @[
        @"pivotIdentifier",
        @"tabIdentifier",
        @"browseId"
    ]) {
        id value = ACGTabValue(item, @[selectorName]);
        if ([value isKindOfClass:NSString.class] && [value length] != 0) {
            return [value lowercaseString];
        }
    }
    NSArray<NSString *> *activeRenderers =
        ACGInteger(item, @"hasPivotBarItemRenderer") != 0
            ? @[@"pivotBarItemRenderer"]
            : (ACGInteger(item, @"hasPivotBarIconOnlyItemRenderer") != 0
                ? @[@"pivotBarIconOnlyItemRenderer"]
                : @[@"pivotBarItemRenderer", @"pivotBarIconOnlyItemRenderer"]);
    for (NSString *rendererName in activeRenderers) {
        id nested = ACGTabValue(item, @[rendererName]);
        if (nested != nil && nested != item) {
            NSString *token = ACGTabToken(nested);
            if (token.length != 0) {
                return token;
            }
        }
    }
    id renderer = ACGTabValue(item, @[@"renderer"]);
    if (renderer != nil && renderer != item) {
        NSString *token = ACGTabToken(renderer);
        if (token.length != 0) {
            return token;
        }
    }
    id endpoint = ACGTabValue(item, @[@"navigationEndpoint", @"endpoint"]);
    id browseEndpoint = ACGTabValue(endpoint, @[@"browseEndpoint"]);
    id browseID = ACGTabValue(browseEndpoint ?: endpoint, @[@"browseId"]);
    if ([browseID isKindOfClass:NSString.class] && [browseID length] != 0) {
        return [browseID lowercaseString];
    }
    id identifier = ACGTabValue(item, @[@"identifier"]);
    return [identifier isKindOfClass:NSString.class]
        ? [identifier lowercaseString]
        : @"";
}

static NSMutableDictionary<NSString *, NSString *> *ACGStartupIdentifiers;

static NSString *ACGRawTabIdentifier(id item, NSUInteger depth) {
    if (item == nil || depth > 3) return nil;
    for (NSString *name in @[@"pivotIdentifier", @"tabIdentifier", @"browseId"]) {
        id value = ACGTabValue(item, @[name]);
        if ([value isKindOfClass:NSString.class] && [value length] != 0) {
            return value;
        }
    }
    for (NSString *name in @[@"pivotBarItemRenderer", @"pivotBarIconOnlyItemRenderer",
                             @"renderer", @"navigationEndpoint", @"endpoint",
                             @"browseEndpoint"]) {
        id nested = ACGTabValue(item, @[name]);
        if (nested == nil || nested == item) continue;
        NSString *found = ACGRawTabIdentifier(nested, depth + 1);
        if (found.length != 0) return found;
    }
    return nil;
}

static void ACGNoteStartupIdentifier(NSString *canonical, id item) {
    if (canonical.length == 0) return;
    NSString *identifier = ACGRawTabIdentifier(item, 0);
    if (identifier.length == 0) return;
    if (ACGStartupIdentifiers == nil) {
        ACGStartupIdentifiers = [NSMutableDictionary dictionary];
    }
    if ([ACGStartupIdentifiers[canonical] isEqualToString:identifier]) return;
    ACGStartupIdentifiers[canonical] = identifier;
    [NSUserDefaults.standardUserDefaults
        setObject:ACGStartupIdentifiers.allKeys
           forKey:@"ACG.Preference.Tabs.Known"];
}

static NSString *ACGHideKeyForToken(NSString *token) {
    if ([token containsString:@"uc-9-kytw8zkzndhqj6fgpwq"] ||
        [token containsString:@"music_home"]) {
        return @"ACG.Preference.Tabs.Hidden.Music";
    }
    if ([token containsString:@"uc4r8dwomoi7cawx8_ljqhig"] ||
        [token containsString:@"trending_live"]) {
        return @"ACG.Preference.Tabs.Hidden.Live";
    }
    if ([token containsString:@"ucopncn46ubxvtpkmrmu4abg"] ||
        [token containsString:@"gaming"]) {
        return @"ACG.Preference.Tabs.Hidden.Gaming";
    }
    if ([token containsString:@"ucyfdidrxb8qhf0nx7iooyw"] ||
        [token containsString:@"news"]) {
        return @"ACG.Preference.Tabs.Hidden.News";
    }
    if ([token containsString:@"fecommunity"] ||
        [token containsString:@"communit"] ||
        [token containsString:@"post"]) {
        return @"ACG.Preference.Tabs.Hidden.Posts";
    }
    if ([token containsString:@"ucegdi0xixxz-qjofpf4jskw"] ||
        [token containsString:@"sports"]) {
        return @"ACG.Preference.Tabs.Hidden.Sports";
    }
    if ([token containsString:@"uctfrv9o2ahqozjjynzrv-xg"] ||
        [token containsString:@"learning"]) {
        return @"ACG.Preference.Tabs.Hidden.Learning";
    }
    if ([token containsString:@"ucrpq4p1ql_hg8rkxikm1moq"] ||
        [token containsString:@"fashion"]) {
        return @"ACG.Preference.Tabs.Hidden.Fashion";
    }
    if ([token containsString:@"feplaylist_aggregation"] ||
        [token containsString:@"playlist_aggregation"]) {
        return @"ACG.Preference.Tabs.Hidden.Playlists";
    }
    if ([token containsString:@"fehistory"] ||
        [token isEqualToString:@"history"]) {
        return @"ACG.Preference.Tabs.Hidden.History";
    }
    if ([token containsString:@"fenotifications_inbox"] ||
        [token containsString:@"notifications_inbox"]) {
        return @"ACG.Preference.Tabs.Hidden.Notifs";
    }
    if ([token isEqualToString:@"vlwl"] ||
        [token containsString:@"watch_later"]) {
        return @"ACG.Preference.Tabs.Hidden.WatchLater";
    }
    if ([token containsString:@"short"]) {
        return @"ACG.Preference.Tabs.Hidden.Shorts";
    }
    if ([token containsString:@"subscription"]) {
        return @"ACG.Preference.Tabs.Hidden.Subscriptions";
    }
    if ([token containsString:@"library"] ||
        [token containsString:@"you_tab"] ||
        [token isEqualToString:@"you"]) {
        return @"ACG.Preference.Tabs.Hidden.Library";
    }
    if ([token containsString:@"create"] ||
        [token containsString:@"upload"] ||
        [token containsString:@"plus"]) {
        return @"ACG.Preference.Tabs.Hidden.Create";
    }
    if ([token containsString:@"home"] ||
        [token containsString:@"what_to_watch"]) {
        return @"ACG.Preference.Tabs.Hidden.Home";
    }
    return nil;
}

static NSString *ACGCanonicalTabToken(NSString *token) {
    if ([token containsString:@"uc-9-kytw8zkzndhqj6fgpwq"] ||
        [token containsString:@"music_home"]) {
        return @"music";
    }
    if ([token containsString:@"uc4r8dwomoi7cawx8_ljqhig"] ||
        [token containsString:@"trending_live"]) {
        return @"live";
    }
    if ([token containsString:@"ucopncn46ubxvtpkmrmu4abg"] ||
        [token containsString:@"gaming"]) {
        return @"gaming";
    }
    if ([token containsString:@"ucyfdidrxb8qhf0nx7iooyw"] ||
        [token containsString:@"news"]) {
        return @"news";
    }
    if ([token containsString:@"fecommunity"] ||
        [token containsString:@"communit"] ||
        [token containsString:@"post"]) {
        return @"posts";
    }
    if ([token containsString:@"ucegdi0xixxz-qjofpf4jskw"] ||
        [token containsString:@"sports"]) {
        return @"sports";
    }
    if ([token containsString:@"uctfrv9o2ahqozjjynzrv-xg"] ||
        [token containsString:@"learning"]) {
        return @"learning";
    }
    if ([token containsString:@"ucrpq4p1ql_hg8rkxikm1moq"] ||
        [token containsString:@"fashion"]) {
        return @"fashion";
    }
    if ([token containsString:@"feplaylist_aggregation"] ||
        [token containsString:@"playlist_aggregation"]) {
        return @"playlists";
    }
    if ([token containsString:@"fehistory"] ||
        [token isEqualToString:@"history"]) {
        return @"history";
    }
    if ([token containsString:@"fenotifications_inbox"] ||
        [token containsString:@"notifications_inbox"]) {
        return @"notifications";
    }
    if ([token isEqualToString:@"vlwl"] ||
        [token containsString:@"watch_later"]) {
        return @"watchlater";
    }
    if ([token containsString:@"short"] || [token containsString:@"reel"]) {
        return @"shorts";
    }
    if ([token containsString:@"subscription"]) {
        return @"subscriptions";
    }
    if ([token containsString:@"library"] ||
        [token containsString:@"you_tab"] ||
        [token isEqualToString:@"you"]) {
        return @"you";
    }
    if ([token containsString:@"create"] ||
        [token containsString:@"upload"] ||
        [token containsString:@"plus"]) {
        return @"create";
    }
    if ([token containsString:@"home"] ||
        [token containsString:@"what_to_watch"]) {
        return @"home";
    }
    return token;
}

static NSArray *ACGTabItems(id renderer, NSString **setterName) {
    NSArray<NSString *> *getters = @[
        @"itemsArray",
        @"items",
        @"pivotBarItemsArray",
        @"pivotBarItems"
    ];
    NSArray<NSString *> *setters = @[
        @"setItemsArray:",
        @"setItems:",
        @"setPivotBarItemsArray:",
        @"setPivotBarItems:"
    ];
    for (NSUInteger index = 0; index < getters.count; index++) {
        id value = ACGTabValue(renderer, @[getters[index]]);
        if ([value isKindOfClass:NSArray.class]) {
            if (setterName != NULL) {
                *setterName = setters[index];
            }
            return value;
        }
    }
    return nil;
}

static NSInteger ACGTabOrderIndex(NSString *token, NSArray *order) {
    NSString *canonical = ACGCanonicalTabToken(token);
    for (NSUInteger index = 0; index < order.count; index++) {
        id value = order[index];
        if (![value isKindOfClass:NSString.class]) continue;
        NSString *entry = [value lowercaseString];
        if ([canonical isEqualToString:entry] ||
            [canonical isEqualToString:ACGCanonicalTabToken(entry)]) {
            return (NSInteger)index;
        }
    }
    for (NSUInteger index = 0; index < order.count; index++) {
        id value = order[index];
        if (![value isKindOfClass:NSString.class]) continue;
        if ([token containsString:[value lowercaseString]]) return (NSInteger)index;
    }
    return NSIntegerMax;
}

static const void *ACGOriginalTitleKey = &ACGOriginalTitleKey;       // tiêu đề gốc của tab, để bỏ tên riêng thì khôi phục ngay
static const void *ACGOriginalItemsKey = &ACGOriginalItemsKey;       // danh sách tab gốc của một renderer, để lọc lại khi đổi cấu hình
static const void *ACGBarRendererKey = &ACGBarRendererKey;           // renderer mà thanh tab đang dùng
static NSString *const ACGTabConfigChangedNote = @"ACGTabConfigDidChange";
static NSHashTable<UIView *> *gACGPivotBars = nil;                   // các thanh tab đang sống (tham chiếu yếu)

static void ACGApplyTabName(id item, NSString *token) {
    NSDictionary *names =
        [NSUserDefaults.standardUserDefaults dictionaryForKey:@"ACG.Preference.Tabs.Names"];
    NSString *replacement = names[token] ?: names[ACGCanonicalTabToken(token)];
    id target = ACGTabValue(item, @[
        @"pivotBarItemRenderer",
        @"pivotBarIconOnlyItemRenderer"
    ]) ?: item;
    SEL titleGetter = NSSelectorFromString(@"title");
    SEL titleSetter = NSSelectorFromString(@"setTitle:");
    if (target != nil && objc_getAssociatedObject(target, ACGOriginalTitleKey) == nil && [target respondsToSelector:titleGetter]) {
        id original = ((id (*)(id, SEL))objc_msgSend)(target, titleGetter);
        objc_setAssociatedObject(target, ACGOriginalTitleKey, original ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![replacement isKindOfClass:NSString.class] || replacement.length == 0) {
        id original = target != nil ? objc_getAssociatedObject(target, ACGOriginalTitleKey) : nil;
        if (original != nil && ![original isKindOfClass:NSNull.class] && [target respondsToSelector:titleSetter]) {
            ((void (*)(id, SEL, id))objc_msgSend)(target, titleSetter, original);
        }
        return;
    }
    Class formattedClass = NSClassFromString(@"YTIFormattedString");
    SEL formattedSelector = NSSelectorFromString(@"formattedStringWithString:");
    id value = replacement;
    if (formattedClass != Nil && [formattedClass respondsToSelector:formattedSelector]) {
        value = ((id (*)(id, SEL, id))objc_msgSend)(
            formattedClass,
            formattedSelector,
            replacement
        );
    }
    SEL selector = NSSelectorFromString(@"setTitle:");
    if ([target respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(target, selector, value);
    }
}

static void ACGSetPivotRenderer(id receiver, SEL selector, id renderer) {
    if (renderer != nil) {
        if ([receiver isKindOfClass:UIView.class]) {
            if (gACGPivotBars == nil) gACGPivotBars = [NSHashTable weakObjectsHashTable];
            [gACGPivotBars addObject:receiver];
            objc_setAssociatedObject(receiver, ACGBarRendererKey, renderer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSString *setterName = nil;
        NSArray *items = ACGTabItems(renderer, &setterName);
        if (items != nil) {
            // Lần đầu: ghi nhớ danh sách tab gốc. Các lần sau (đổi cấu hình khi đang chạy) lọc lại từ danh sách gốc này.
            NSArray *originals = objc_getAssociatedObject(renderer, ACGOriginalItemsKey);
            if (originals == nil) {
                originals = [items copy];
                objc_setAssociatedObject(renderer, ACGOriginalItemsKey, originals, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            NSMutableArray *filtered = [NSMutableArray array];
            for (id item in originals) {
                id candidate = item;
                NSString *token = ACGTabToken(candidate);
                NSString *hideKey = ACGHideKeyForToken(token);
                ACGNoteStartupIdentifier(ACGCanonicalTabToken(token), candidate);
                if (ACGMasterEnabled() && hideKey != nil &&
                    [NSUserDefaults.standardUserDefaults boolForKey:hideKey]) {
                    continue;
                }
                if (ACGMasterEnabled() &&
                    [ACGCanonicalTabToken(token) isEqualToString:@"create"]) {
                    [filtered addObject:candidate];
                    continue;
                }
                if (ACGMasterEnabled()) {
                    ACGApplyTabName(candidate, token);
                }
                [filtered addObject:candidate];
            }

            NSArray<NSDictionary *> *extraTabs = @[
                @{@"token": @"music", @"id": @"UC-9-kyTW8ZkZNDHQJ6FgpwQ",
                  @"title": AutoACT(@"Nhạc"), @"key": @"ACG.Preference.Tabs.Hidden.Music", @"icon": @1001},
                @{@"token": @"live", @"id": @"UC4R8DWoMoI7CAwX8_LjQHig",
                  @"title": AutoACT(@"Trực tiếp"), @"key": @"ACG.Preference.Tabs.Hidden.Live", @"icon": @1002},
                @{@"token": @"gaming", @"id": @"UCOpNcN46UbXVtpKMrmU4Abg",
                  @"title": AutoACT(@"Trò chơi"), @"key": @"ACG.Preference.Tabs.Hidden.Gaming", @"icon": @1003},
                @{@"token": @"news", @"id": @"UCYfdidRxbB8Qhf0Nx7ioOYw",
                  @"title": AutoACT(@"Tin tức"), @"key": @"ACG.Preference.Tabs.Hidden.News", @"icon": @1004},
                @{@"token": @"sports", @"id": @"UCEgdi0XIXXZ-qJOFPf4JSKw",
                  @"title": AutoACT(@"Thể thao"), @"key": @"ACG.Preference.Tabs.Hidden.Sports", @"icon": @1005},
                @{@"token": @"learning", @"id": @"UCtFRv9O2AHqOZjjynzrv-xg",
                  @"title": AutoACT(@"Học tập"), @"key": @"ACG.Preference.Tabs.Hidden.Learning", @"icon": @1006},
                @{@"token": @"fashion", @"id": @"UCrpQ4p1Ql_hG8rKXIKM1MOQ",
                  @"title": AutoACT(@"Thời trang"), @"key": @"ACG.Preference.Tabs.Hidden.Fashion", @"icon": @1007},
                @{@"token": @"playlists", @"id": @"FEplaylist_aggregation",
                  @"title": @"Playlist", @"key": @"ACG.Preference.Tabs.Hidden.Playlists", @"icon": @1008},
                @{@"token": @"history", @"id": @"FEhistory",
                  @"title": AutoACT(@"Lịch sử"), @"key": @"ACG.Preference.Tabs.Hidden.History", @"icon": @1009},
                @{@"token": @"notifications", @"id": @"FEnotifications_inbox",
                  @"title": AutoACT(@"Thông báo"), @"key": @"ACG.Preference.Tabs.Hidden.Notifs", @"icon": @1010},
                @{@"token": @"watchlater", @"id": @"VLWL",
                  @"title": AutoACT(@"Xem sau"), @"key": @"ACG.Preference.Tabs.Hidden.WatchLater", @"icon": @1011},
                @{@"token": @"posts", @"id": @"FEpost_home",
                  @"title": AutoACT(@"Bài đăng"), @"key": @"ACG.Preference.Tabs.Hidden.Posts", @"icon": @1012}
            ];
            NSMutableSet<NSString *> *present = [NSMutableSet set];
            for (id item in filtered) {
                [present addObject:ACGCanonicalTabToken(ACGTabToken(item))];
            }
            NSDictionary *customNames =
                [NSUserDefaults.standardUserDefaults dictionaryForKey:@"ACG.Preference.Tabs.Names"];
            for (NSDictionary *entry in extraTabs) {
                NSString *token = entry[@"token"];
                if ([NSUserDefaults.standardUserDefaults boolForKey:entry[@"key"]] ||
                    [present containsObject:token]) {
                    continue;
                }
                NSString *title = customNames[token] ?: entry[@"title"];
                id item = ACGMakeBrowsePivotItem(entry[@"id"],
                                                     title,
                                                     [entry[@"icon"] integerValue]);
                if (item != nil) {
                    ACGNoteStartupIdentifier(token, item);
                    [filtered addObject:item];
                    [present addObject:token];
                }
            }

            NSArray *order =
                [NSUserDefaults.standardUserDefaults arrayForKey:@"ACG.Preference.Tabs.Order"];
            if (ACGMasterEnabled() && order.count != 0) {
                [filtered sortUsingComparator:^NSComparisonResult(id left, id right) {
                    NSInteger leftIndex =
                        ACGTabOrderIndex(ACGTabToken(left), order);
                    NSInteger rightIndex =
                        ACGTabOrderIndex(ACGTabToken(right), order);
                    if (leftIndex == rightIndex) {
                        return NSOrderedSame;
                    }
                    return leftIndex < rightIndex
                        ? NSOrderedAscending
                        : NSOrderedDescending;
                }];
            }

            gACGTabSeen = (NSInteger)originals.count;
            gACGTabShown = (NSInteger)filtered.count;
            NSString *firstIdentifier = filtered.count != 0 ? ACGRawTabIdentifier(filtered.firstObject, 0) : nil;
            if (firstIdentifier.length != 0) ACGFirstVisiblePivot = [firstIdentifier copy];
            SEL setter = NSSelectorFromString(setterName);
            if ([items isKindOfClass:NSMutableArray.class]) {
                [(NSMutableArray *)items setArray:filtered];
            } else if ([renderer respondsToSelector:setter]) {
                ((void (*)(id, SEL, id))objc_msgSend)(renderer, setter, filtered);
            }
        }
    }

    static Class floatingClass;
    if (floatingClass == Nil) floatingClass = NSClassFromString(@"YTFloatingPivotBarView");
    BOOL floating = floatingClass != Nil && [receiver isKindOfClass:floatingClass];
    if (floating) {
        NSArray *tabs = renderer != nil ? ACGTabItems(renderer, NULL) : nil;
        ACGDebugLog(@"tabbar", @"floating bar renderer tabs=%lu", (unsigned long)tabs.count);
    }
    IMP original = floating ? OriginalSetFloatingPivotRenderer : OriginalSetPivotRenderer;
    if (original != NULL) {
        ((void (*)(id, SEL, id))original)(receiver, selector, renderer);
    }
}

// Áp dụng lại cấu hình tab (ẩn/hiện, thứ tự, tên) lên các thanh tab đang chạy, không cần mở lại app.
// Cách 1: nạp lại renderer đã lưu qua hàm lọc; cách 2: nhờ YouTube dựng lại thanh tab như YTLite (refreshPivotBar).
static void ACGReapplyTabConfig(void) {
    for (UIView *bar in gACGPivotBars.allObjects) {
        id renderer = objc_getAssociatedObject(bar, ACGBarRendererKey);
        if (renderer == nil || bar.window == nil) continue;
        @try { ACGSetPivotRenderer(bar, NSSelectorFromString(@"setRenderer:"), renderer); } @catch (__unused id e) {}
    }
    Class combo = NSClassFromString(@"YTHeaderContentComboViewController");
    SEL refresh = NSSelectorFromString(@"refreshPivotBar");
    if (combo != Nil && [combo instancesRespondToSelector:refresh]) {
        @try {
            id controller = [[combo alloc] init];
            ((void (*)(id, SEL))objc_msgSend)(controller, refresh);
        } @catch (__unused id e) {}
    }
}

static BOOL ACGTabLabelsHidden(UIView *item) {
    BOOL hidden = ACGFeatureEnabled(@"ACG.Preference.Tabs.LabelsHidden");
    static Class floatingClass;
    if (floatingClass == Nil) floatingClass = NSClassFromString(@"YTFloatingPivotBarView");
    SEL getter = NSSelectorFromString(@"hideLabel");
    SEL setter = NSSelectorFromString(@"setHideLabel:");
    if (floatingClass == Nil || ![item respondsToSelector:getter] || ![item respondsToSelector:setter]) return hidden;
    UIView *bar = item.superview;
    while (bar != nil && ![bar isKindOfClass:floatingClass]) bar = bar.superview;
    if (bar == nil) return hidden;
    if (((BOOL (*)(id, SEL))objc_msgSend)(item, getter) != hidden) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(item, setter, hidden);
        [item setNeedsLayout];
    }
    return hidden;
}

static const void *ACGLabelHiddenByUsKey = &ACGLabelHiddenByUsKey;
// Ẩn nhãn: ghi nhớ nhãn nào do AutoAC ẩn. Khi bật lại nhãn chỉ khôi phục đúng các nhãn đó,
// không ép hiện mọi UILabel (tránh lộ nhãn mà YouTube chủ ý ẩn).
static void ACGSetLabelsHidden(UIView *view, BOOL hidden) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:UILabel.class]) {
            BOOL mine = [objc_getAssociatedObject(subview, ACGLabelHiddenByUsKey) boolValue];
            if (hidden) {
                if (!mine) objc_setAssociatedObject(subview, ACGLabelHiddenByUsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                subview.hidden = YES;
                subview.alpha = 0.0;
            } else if (mine) {
                objc_setAssociatedObject(subview, ACGLabelHiddenByUsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                subview.hidden = NO;
                subview.alpha = 1.0;
            }
        }
        ACGSetLabelsHidden(subview, hidden);
    }
}

static BOOL ACGInsidePivotItem(UIView *view) {
    for (UIView *current = view.superview; current != nil; current = current.superview) {
        if ([NSStringFromClass(current.class) containsString:@"PivotBarItemView"]) {
            return YES;
        }
    }
    return NO;
}

static UIView *ACGPivotItemAncestor(UIView *view) {
    for (UIView *current = view.superview; current != nil; current = current.superview) {
        if ([NSStringFromClass(current.class) containsString:@"PivotBarItemView"]) {
            return current;
        }
    }
    return nil;
}

static void ACGPivotLabelSetHidden(UILabel *receiver,
                                      SEL selector,
                                      BOOL hidden) {
    if (ACGFeatureEnabled(@"ACG.Preference.Tabs.LabelsHidden") &&
        ACGInsidePivotItem(receiver)) {
        if (!hidden) objc_setAssociatedObject(receiver, ACGLabelHiddenByUsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // do ta ép ẩn: bật lại nhãn phải khôi phục được
        hidden = YES;
    }
    if (OriginalPivotLabelSetHidden != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalPivotLabelSetHidden)(
            receiver, selector, hidden
        );
    }
}

static void ACGPivotLabelSetAlpha(UILabel *receiver,
                                     SEL selector,
                                     CGFloat alpha) {
    if (ACGFeatureEnabled(@"ACG.Preference.Tabs.LabelsHidden") &&
        ACGInsidePivotItem(receiver)) {
        if (alpha > 0.0) objc_setAssociatedObject(receiver, ACGLabelHiddenByUsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        alpha = 0.0;
    }
    if (OriginalPivotLabelSetAlpha != NULL) {
        ((void (*)(id, SEL, CGFloat))OriginalPivotLabelSetAlpha)(
            receiver, selector, alpha
        );
    }
}

static UIImageView *ACGFindImageView(UIView *view);

static BOOL ACGContainsLabel(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return YES;
    for (UIView *child in view.subviews) {
        if (ACGContainsLabel(child)) return YES;
    }
    return NO;
}

static void ACGCollectIconCandidates(UIView *view,
                                        UIView *root,
                                        NSMutableArray<UIView *> *candidates) {
    if (view != root && ![view isKindOfClass:UILabel.class]) {
        NSString *name = NSStringFromClass(view.class).lowercaseString;
        CGFloat width = CGRectGetWidth(view.bounds);
        CGFloat height = CGRectGetHeight(view.bounds);
        BOOL iconClass = [view isKindOfClass:UIImageView.class] ||
            [name containsString:@"icon"] || [name containsString:@"image"];
        BOOL iconSize = width >= 12.0 && height >= 12.0 &&
            width <= 64.0 && height <= 64.0;
        if ((view.tag == 0x59414345 || view.tag == ACGExtraIconTag ||
             iconClass) && iconSize) {
            [candidates addObject:view];
        }
    }
    for (UIView *child in view.subviews) {
        ACGCollectIconCandidates(child, root, candidates);
    }
}

static UIView *ACGIconContainer(UIView *candidate, UIView *root) {
    UIView *container = candidate;
    while (container.superview != nil && container.superview != root) {
        UIView *parent = container.superview;
        if (ACGContainsLabel(parent) ||
            CGRectGetWidth(parent.bounds) > 80.0 ||
            CGRectGetHeight(parent.bounds) > 80.0) {
            break;
        }
        container = parent;
    }
    return container;
}

static void ACGCenterPivotIcon(UIView *view, BOOL centered) {
    if (!centered) return;
    NSMutableArray<UIView *> *candidates = [NSMutableArray array];
    ACGCollectIconCandidates(view, view, candidates);
    UIView *candidate = nil;
    CGFloat bestScore = CGFLOAT_MAX;
    CGPoint rootCenter = CGPointMake(CGRectGetMidX(view.bounds),
                                     CGRectGetMidY(view.bounds));
    for (UIView *item in candidates) {
        CGPoint center = [item.superview convertPoint:item.center toView:view];
        CGFloat score = fabs(center.x - rootCenter.x) +
            fabs(CGRectGetWidth(item.bounds) - 24.0) * 0.25 +
            (item.hidden ? 100.0 : 0.0);
        if (item.tag == 0x59414345 || item.tag == ACGExtraIconTag) {
            score -= 1000.0;
        }
        if (score < bestScore) {
            bestScore = score;
            candidate = item;
        }
    }
    UIView *iconView = candidate == nil ? nil : ACGIconContainer(candidate, view);
    if (iconView == nil || iconView.superview == nil) return;
    CGPoint target = [view convertPoint:CGPointMake(CGRectGetMidX(view.bounds),
                                                     CGRectGetMidY(view.bounds))
                                toView:iconView.superview];
    iconView.center = target;
}

static UILabel *ACGFindNativeLabel(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        return (view.tag == 0x59414347 || view.tag == ACGExtraLabelTag)
            ? nil : (UILabel *)view;
    }
    for (UIView *subview in view.subviews) {
        UILabel *label = ACGFindNativeLabel(subview);
        if (label != nil) {
            return label;
        }
    }
    return nil;
}

static UIColor *ACGTabForegroundColor(UIView *view, UITraitCollection *traits) {
    for (UIView *current = view.superview; current != nil; current = current.superview) {
        UIColor *color = [current.backgroundColor
            resolvedColorWithTraitCollection:traits];
        CGFloat red = 0.0;
        CGFloat green = 0.0;
        CGFloat blue = 0.0;
        CGFloat alpha = 0.0;
        if ([color getRed:&red green:&green blue:&blue alpha:&alpha] &&
            alpha > 0.2) {
            CGFloat luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722;
            return luminance < 0.5 ? UIColor.whiteColor : UIColor.blackColor;
        }
    }
    return [UIColor.labelColor
        resolvedColorWithTraitCollection:traits];
}

static UIImageView *ACGFindImageView(UIView *view) {
    if ([view isKindOfClass:UIImageView.class]) {
        return (view.tag == 0x59414345 || view.tag == ACGExtraIconTag)
            ? nil : (UIImageView *)view;
    }
    for (UIView *subview in view.subviews) {
        UIImageView *imageView = ACGFindImageView(subview);
        if (imageView != nil) {
            return imageView;
        }
    }
    return nil;
}


static NSDictionary *ACGExtraTabIcon(NSString *token) {
    static NSDictionary *icons;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        icons = @{
            @"music": @[AutoACT(@"nhạc"), @"yt_outline_music_24pt_3x_Normal",
                         @"music_24pt_3x_Normal",
                         @"music.note", @"music.note"],
            @"live": @[AutoACT(@"trực tiếp"), @"live_24pt_3x_Normal", @"ic_youtube_live_3x_Normal",
                        @"dot.radiowaves.left.and.right",
                        @"dot.radiowaves.left.and.right"],
            @"gaming": @[AutoACT(@"trò chơi"), @"gaming_24pt_3x_Normal",
                          @"gaming_24pt_3x_Normal_fill",
                          @"gamecontroller", @"gamecontroller.fill"],
            @"news": @[AutoACT(@"tin tức"), @"news_24pt_3x_Normal", @"news_24pt_3x_Normal",
                        @"newspaper", @"newspaper.fill"],
            @"sports": @[AutoACT(@"thể thao"), @"G_sport", @"G_sport_fill",
                          @"trophy", @"trophy.fill"],
            @"learning": @[AutoACT(@"học tập"), @"G_Learning", @"G_Learning_fill",
                            @"graduationcap", @"graduationcap.fill"],
            @"fashion": @[AutoACT(@"thời trang"), @"fashion_24pt_3x_Normal",
                           @"fashion_24pt_3x_Normal",
                           @"tshirt", @"tshirt.fill"],
            @"playlists": @[@"playlist", @"playlist", @"playlist_fill",
                             @"music.note.list", @"music.note.list"],
            @"history": @[AutoACT(@"lịch sử"), @"history", @"history_fill",
                           @"clock.arrow.circlepath",
                           @"clock.arrow.circlepath"],
            @"notifications": @[AutoACT(@"thông báo"), @"ic_notifications_none_3x_Normal",
                                 @"ic_notifications_3x_Normal",
                                 @"bell", @"bell.fill"],
            @"watchlater": @[@"xem sau", @"clock_24pt_3x_Normal",
                              @"yt_fill_clock_24pt_3x_Normal",
                              @"clock", @"clock.fill"],
            @"posts": @[AutoACT(@"bài đăng"), @"", @"",
                         @"bubble.left.and.bubble.right",
                         @"bubble.left.and.bubble.right.fill"]
        };
    });
    NSArray *values = icons[token];
    return values == nil ? nil : @{
        @"normalAsset": values[1],      // values[0] là tên tab
        @"selectedAsset": values[2],
        @"normalSymbol": values[3],
        @"selectedSymbol": values[4]
    };
}

static BOOL ACGPivotItemSelected(UIView *view) {
    if ([objc_getAssociatedObject(view, ACGTabDragOutAssociation) boolValue]) return NO;
    BOOL selected = [objc_getAssociatedObject(
        view,
        ACGTabSelectedAssociation
    ) boolValue];
    SEL selector = NSSelectorFromString(@"isSelected");
    if ([view respondsToSelector:selector]) {
        selected = selected ||
            ((BOOL (*)(id, SEL))objc_msgSend)(view, selector);
    }
    return selected ||
        ((view.accessibilityTraits & UIAccessibilityTraitSelected) != 0);
}

// Khoá ẩn của từng tab phụ: tab phụ đang ẩn thì không thể có ô nào trên thanh, nên không được vẽ icon thay thế
static NSString *ACGExtraHideKey(NSString *token) {
    static NSDictionary *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @{@"music": @"ACG.Preference.Tabs.Hidden.Music", @"live": @"ACG.Preference.Tabs.Hidden.Live",
                 @"gaming": @"ACG.Preference.Tabs.Hidden.Gaming", @"news": @"ACG.Preference.Tabs.Hidden.News",
                 @"sports": @"ACG.Preference.Tabs.Hidden.Sports", @"learning": @"ACG.Preference.Tabs.Hidden.Learning",
                 @"fashion": @"ACG.Preference.Tabs.Hidden.Fashion", @"playlists": @"ACG.Preference.Tabs.Hidden.Playlists",
                 @"history": @"ACG.Preference.Tabs.Hidden.History", @"notifications": @"ACG.Preference.Tabs.Hidden.Notifs",
                 @"watchlater": @"ACG.Preference.Tabs.Hidden.WatchLater", @"posts": @"ACG.Preference.Tabs.Hidden.Posts"};
    });
    return keys[token];
}

static void ACGCollectPivotItems(UIView *view, NSMutableArray<UIView *> *items);
static NSString *ACGPivotItemIdentifier(UIView *item);

// Màu trung bình (theo độ đục) của một ảnh
static UIColor *ACGAverageImageColor(UIImage *image) {
    if (image.CGImage == NULL) return nil;
    uint8_t px[4 * 16 * 16] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, 16, 16, 8, 16 * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return nil;
    CGContextDrawImage(ctx, CGRectMake(0, 0, 16, 16), image.CGImage);
    CGContextRelease(ctx);
    double r = 0, g = 0, b = 0, a = 0;
    for (int k = 0; k < 16 * 16; k++) { r += px[k * 4]; g += px[k * 4 + 1]; b += px[k * 4 + 2]; a += px[k * 4 + 3]; }
    if (a < 255.0 * 4) return nil;   // gần như trong suốt
    return [UIColor colorWithRed:r / a green:g / a blue:b / a alpha:1];   // đã nhân sẵn alpha nên chia cho tổng alpha
}

static UIView *ACGPivotBarOf(UIView *view) {
    UIView *bar = view;
    while (bar != nil && ![NSStringFromClass(bar.class) isEqualToString:@"YTPivotBarView"]) bar = bar.superview;
    return bar;
}

// Thanh tab đang ở trang Short?
static BOOL ACGBarShowsShorts(UIView *view) {
    UIView *bar = ACGPivotBarOf(view);
    if (bar == nil) return NO;
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    ACGCollectPivotItems(bar, items);
    for (UIView *item in items) {
        if (ACGPivotItemSelected(item) && [ACGPivotItemIdentifier(item) isEqualToString:@"FEshorts"]) return YES;
    }
    return NO;
}

// Chụp màu thật đang hiện của một icon (dùng khi ảnh là vector/không có CGImage nên không đọc màu từ ảnh được)
static UIColor *ACGSnapshotIconColor(UIImageView *iv) {
    if (iv.window == nil || CGRectGetWidth(iv.bounds) < 6.0 || CGRectGetHeight(iv.bounds) < 6.0) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1.0;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(16.0, 16.0) format:format];
    UIImage *snapshot = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [iv drawViewHierarchyInRect:CGRectMake(0.0, 0.0, 16.0, 16.0) afterScreenUpdates:NO];
    }];
    return ACGAverageImageColor(snapshot);
}

static const void *ACGIconColorCacheAssociation = &ACGIconColorCacheAssociation;
static NSString *gACGIconColorDiag;   // hiện trong mục chẩn đoán: màu icon tab thêm lấy từ đâu

static void ACGNoteIconColor(NSString *key, NSString *source, UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    gACGIconColorDiag = [NSString stringWithFormat:@"%@ · %@ · RGB %.0f,%.0f,%.0f", key, source, r * 255, g * 255, b * 255];
}

// Màu icon thường của thanh tab: lấy từ icon gốc của một ô khác đang không được chọn, nên luôn đúng màu hệ thống.
// Nguyên nhân icon đen: khi dựng mặt nạ cho thanh kính, AutoAC lật tạm MỌI ô sang "đã chọn" rồi lật lại; lúc đó không còn ô gốc nào
// ở trạng thái thường để đọc màu nên rơi xuống bước đoán (sáng → đen), và màu đoán đó bị giữ lại. Nay: màu đọc được lần nào được nhớ
// theo từng kiểu (sáng, tối, Short) trên thanh tab và dùng lại khi chưa đọc được hoặc đang dựng mặt nạ; chỉ đoán khi chưa có gì để nhớ.
// Ở Short luôn trắng; màu động của ô gốc được giải theo kiểu sáng/tối dự kiến của cửa sổ chứ không theo trait đang trễ.
static UIColor *ACGNativeSiblingIconColor(UIView *view) {
    UIView *holder = ACGPivotBarOf(view) ?: view.window ?: view;
    NSMutableDictionary<NSString *, id> *cache = objc_getAssociatedObject(holder, ACGIconColorCacheAssociation);
    if (cache == nil) {
        cache = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(holder, ACGIconColorCacheAssociation, cache, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (ACGStencilRendering) {
        UIColor *kept = cache[cache[@"last"] ?: @""];
        if (kept != nil) return kept;
    }
    UIUserInterfaceStyle style = view.window.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithUserInterfaceStyle:style];
    BOOL shorts = !ACGStencilRendering && view.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark && ACGBarShowsShorts(view);   // chỉ khi thanh đang hiển thị tối; AutoAC không còn tự làm tối dock ở Short
    NSString *key = shorts ? @"Short" : (style == UIUserInterfaceStyleDark ? @"tối" : @"sáng");
    UIColor *found = nil;
    NSString *source = nil;
    if (shorts) {
        found = UIColor.whiteColor;
        source = @"Short + thanh tối → trắng";
    } else if (!ACGStencilRendering) {
        NSMutableArray<UIView *> *items = [NSMutableArray array];
        UIView *root = view.superview;
        for (int hop = 0; root && hop < 8; hop++, root = root.superview) {
            [items removeAllObjects];
            ACGCollectPivotItems(root, items);
            if (items.count > 1) break;
        }
        for (UIView *item in items) {
            if (item == view || ACGPivotItemSelected(item)) continue;
            if ([ACGPivotItemIdentifier(item) isEqualToString:@"FElibrary"]) continue;   // ô ảnh đại diện
            UIImageView *iv = ACGFindImageView(item);
            if (!iv || iv.hidden || iv.image == nil) continue;
            if (iv.image.renderingMode == UIImageRenderingModeAlwaysTemplate) {
                found = [iv.tintColor resolvedColorWithTraitCollection:traits];
                source = @"đọc từ tint của ô gốc";
            } else {
                found = ACGAverageImageColor(iv.image);
                source = @"đọc từ ảnh của ô gốc";
            }
            if (found == nil) {
                found = ACGSnapshotIconColor(iv);
                source = @"chụp từ ô gốc";
            }
            if (found != nil) break;
        }
    }
    if (found != nil) {
        cache[key] = found;
        cache[@"last"] = key;
        ACGNoteIconColor(key, source, found);
        return found;
    }
    UIColor *kept = cache[key];
    if (kept != nil) {
        ACGNoteIconColor(key, ACGStencilRendering ? @"giữ màu cũ (đang dựng mặt nạ)" : @"dùng màu đã nhớ", kept);
        return kept;
    }
    UIColor *guess = style == UIUserInterfaceStyleDark ? UIColor.whiteColor : ACGTabForegroundColor(view, traits);
    ACGNoteIconColor(key, @"đoán (chưa có màu nào để nhớ)", guess);
    return guess;
}

static const void *ACGNativeImageHiddenByUsKey = &ACGNativeImageHiddenByUsKey;
static NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *gACGExtraDump;   // "Short"/"thường" → tab → trạng thái lần cuối

static void ACGRecordExtraTab(UIView *view, NSString *token, NSString *note) {
    NSString *page = ACGBarShowsShorts(view) ? @"Short" : @"thường";
    if (gACGExtraDump == nil) gACGExtraDump = [NSMutableDictionary dictionary];
    NSMutableDictionary *bucket = gACGExtraDump[page];
    if (bucket == nil) { bucket = [NSMutableDictionary dictionary]; gACGExtraDump[page] = bucket; }
    UIImageView *icon = (UIImageView *)[view viewWithTag:ACGExtraIconTag];
    NSString *line;
    if (icon != nil) {
        CGFloat r = 0, g = 0, b = 0, a = 0;
        [icon.tintColor getRed:&r green:&g blue:&b alpha:&a];
        UIImageView *nativeImage = ACGFindImageView(view);
        line = [NSString stringWithFormat:@"%@ · icon %.0fx%.0f tại %.0f,%.0f · ẩn %d · mờ %.2f · màu %.0f,%.0f,%.0f · có ảnh %d · nằm trong cửa sổ %d · ô gốc ẩn %d · ô mờ %.2f",
                note ?: @"vẽ icon", icon.bounds.size.width, icon.bounds.size.height, icon.frame.origin.x, icon.frame.origin.y,
                icon.hidden, icon.alpha, r * 255, g * 255, b * 255, icon.image != nil, icon.window != nil,
                nativeImage.hidden, view.alpha];
    } else {
        line = note ?: @"không có icon thay thế";
    }
    bucket[token.length ? token : @"?"] = line;
}

static void ACGApplyExtraTabIcon(UIView *view) {
    NSString *token = ACGCanonicalTabToken(ACGTabToken(view));
    NSDictionary *config = ACGExtraTabIcon(token);
    if (config == nil) {
        UILabel *nativeLabel = ACGFindNativeLabel(view);
        NSString *hint = [[NSString stringWithFormat:@"%@ %@ %@ %@",
            nativeLabel.text ?: @"", view.accessibilityLabel ?: @"",
            view.accessibilityIdentifier ?: @"", view.description ?: @""] lowercaseString];
        NSDictionary *aliases = @{
            @"music": @[@"music"],
            @"live": @[@"live"],
            @"gaming": @[@"gaming"],
            @"news": @[@"news"],
            @"sports": @[@"sports"],
            @"learning": @[@"learning"],
            @"fashion": @[@"fashion"],
            @"playlists": @[@"playlists", @"playlist"],
            @"history": @[@"history"],
            @"notifications": @[@"notifs", @"notifications"],
            @"watchlater": @[@"wlater", @"watch later"],
            @"posts": @[@"posts", @"post"]
        };
        for (NSString *candidate in aliases) {
            for (NSString *alias in aliases[candidate]) {
                if ([hint containsString:alias]) {
                    token = candidate;
                    config = ACGExtraTabIcon(token);
                    break;
                }
            }
            if (config != nil) break;
        }
    }
    NSString *extraHideKey = config != nil ? ACGExtraHideKey(token) : nil;
    NSString *dropReason = nil;
    if (config != nil && (extraHideKey.length == 0 || ACGFeatureEnabled(extraHideKey))) {
        config = nil;   // tab phụ đang ẩn: đây là tab gốc (vd. Tạo) bị nhận nhầm
        dropReason = @"bỏ: khoá ẩn của tab này đang bật (coi là tab gốc)";
    }
    BOOL extraSelected = config != nil && ACGPivotItemSelected(view);
    if (config != nil && ACGAssetImage(config[extraSelected ? @"selectedAsset" : @"normalAsset"],
                                       config[extraSelected ? @"selectedSymbol" : @"normalSymbol"]) == nil) {
        config = nil;   // không có icon thay thế thì giữ icon gốc, không vẽ vòng tròn rỗng
        dropReason = @"bỏ: thiếu ảnh icon thay thế";
    }
    if (config == nil) {
        [[view viewWithTag:ACGExtraIconTag] removeFromSuperview];
        [[view viewWithTag:ACGExtraLabelTag] removeFromSuperview];
        UIImageView *hiddenNative = ACGFindImageView(view);
        if (hiddenNative != nil && [objc_getAssociatedObject(hiddenNative, ACGNativeImageHiddenByUsKey) boolValue]) {
            hiddenNative.hidden = NO;   // đã bỏ icon thay thế thì trả lại icon gốc, không để ô trống
            objc_setAssociatedObject(hiddenNative, ACGNativeImageHiddenByUsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (dropReason != nil) ACGRecordExtraTab(view, token, dropReason);
        return;
    }
    UIImageView *nativeImage = ACGFindImageView(view);
    if (nativeImage != nil) {
        nativeImage.hidden = YES;
        objc_setAssociatedObject(nativeImage, ACGNativeImageHiddenByUsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIImageView *icon = (UIImageView *)[view viewWithTag:ACGExtraIconTag];
    if (icon == nil) {
        icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        icon.tag = ACGExtraIconTag;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.userInteractionEnabled = NO;
        [view addSubview:icon];
    }
    BOOL selected = ACGPivotItemSelected(view);
    NSString *asset = config[selected ? @"selectedAsset" : @"normalAsset"];
    NSString *symbol = config[selected ? @"selectedSymbol" : @"normalSymbol"];
    UIImage *image = ACGAssetImage(asset, symbol);
    if (image == nil) {
        image = [UIImage systemImageNamed:@"circle"];
    }
    icon.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIColor *foreground = ACGNativeSiblingIconColor(view);
    icon.tintColor = foreground;
    icon.hidden = NO;
    icon.alpha = 1.0;
    if (view.subviews.lastObject != icon) [view bringSubviewToFront:icon];
    CGFloat size = 24.0;
    UILabel *titleProbe = ACGFindNativeLabel(view);
    UILabel *ownLabel = (UILabel *)[view viewWithTag:ACGExtraLabelTag];
    // Thanh kính chỉ hiện icon, không có chữ: icon phải nằm giữa ô thay vì sát mép trên
    BOOL hideLabel = ACGTabLabelsHidden(view) || (titleProbe.text.length == 0 && ownLabel.text.length == 0);
    icon.frame = CGRectMake(
        (CGRectGetWidth(view.bounds) - size) * 0.5,
        hideLabel ? (CGRectGetHeight(view.bounds) - size) * 0.5 : 4.0,
        size,
        size
    );
    UILabel *nativeLabel = ACGFindNativeLabel(view);
    UILabel *label = (UILabel *)[view viewWithTag:ACGExtraLabelTag];
    NSString *title = nativeLabel.text.length != 0
        ? nativeLabel.text : label.text;
    UIFont *font = nativeLabel.font ?: label.font;
    if (nativeLabel != nil) {
        nativeLabel.text = @"";
        nativeLabel.hidden = YES;
        nativeLabel.alpha = 0.0;
    }
    if (label == nil) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.tag = ACGExtraLabelTag;
        label.textAlignment = NSTextAlignmentCenter;
        label.userInteractionEnabled = NO;
        [view addSubview:label];
    }
    label.text = title;
    label.font = font ?: [UIFont systemFontOfSize:10.0];
    label.textColor = icon.tintColor;
    label.hidden = hideLabel;
    label.alpha = hideLabel ? 0.0 : 1.0;
    label.frame = CGRectMake(
        0.0,
        MAX(0.0, CGRectGetHeight(view.bounds) - 16.0),
        CGRectGetWidth(view.bounds),
        14.0
    );
    ACGRecordExtraTab(view, token, nil);
}

static NSString *const ACGTintModeKey = @"ACG.Preference.Tabs.SelectedTint";
static NSString *const ACGTintColorKey = @"ACG.Preference.Tabs.SelectedTintColor";
static const void *ACGNativeTextColorAssociation = &ACGNativeTextColorAssociation;
static const void *ACGNativeIconAssociation = &ACGNativeIconAssociation;
static IMP OriginalPivotLabelSetTextColor;
static NSInteger ACGTintMode;
static UIColor *ACGTintColor;

static NSString *ACGPivotItemIdentifier(UIView *item);
static UIImageView *ACGFindPhotoView(UIView *view);

static BOOL ACGRefreshTabTint(void) {
    NSInteger mode = [ACGPreferenceObject(ACGTintModeKey) integerValue];
    id stored = ACGPreferenceObject(ACGTintColorKey);
    NSString *value = [[([stored isKindOfClass:NSString.class] ? stored : @"#0A84FF")
        stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    unsigned int rgb = 0x0A84FF;
    if (value.length == 6) [[NSScanner scannerWithString:value] scanHexInt:&rgb];
    UIColor *color = [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                                     green:((rgb >> 8) & 0xFF) / 255.0
                                      blue:(rgb & 0xFF) / 255.0
                                     alpha:1.0];
    BOOL changed = mode != ACGTintMode || ![color isEqual:ACGTintColor];
    ACGTintMode = mode;
    ACGTintColor = color;
    return changed;
}

static void ACGSetLabelColor(UILabel *label, UIColor *color) {
    if (color == nil || [label.textColor isEqual:color]) return;
    if (OriginalPivotLabelSetTextColor != NULL) {
        ((void (*)(id, SEL, id))OriginalPivotLabelSetTextColor)(label, @selector(setTextColor:), color);
    } else {
        label.textColor = color;
    }
}

static void ACGPivotLabelSetTextColor(UILabel *receiver, SEL selector, UIColor *color) {
    if (ACGTintMode != 0) {
        UIView *item = ACGPivotItemAncestor(receiver);
        if (item != nil) {
            objc_setAssociatedObject(receiver, ACGNativeTextColorAssociation, color,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (ACGPivotItemSelected(item)) color = ACGTintColor;
        }
    }
    if (OriginalPivotLabelSetTextColor != NULL) {
        ((void (*)(id, SEL, id))OriginalPivotLabelSetTextColor)(receiver, selector, color);
    }
}

static void ACGCollectLabels(UIView *view, NSMutableArray<UILabel *> *labels) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:UILabel.class]) [labels addObject:(UILabel *)subview];
        ACGCollectLabels(subview, labels);
    }
}

static void ACGApplyTabTint(UIView *item) {
    BOOL tinted = ACGTintMode != 0 && ACGPivotItemSelected(item);
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    ACGCollectLabels(item, labels);
    for (UILabel *label in labels) {
        if (label.tag == ACGExtraLabelTag) {
            // Nhãn tab phụ do AutoAC tự vẽ: màu theo icon (hoặc màu tab chọn). Trước đây nó bị coi như nhãn gốc nên
            // màu lần đầu (có thể là đen lúc sáng) bị nhớ rồi áp lại mãi, kể cả khi sang Short
            UIImageView *own = (UIImageView *)[item viewWithTag:ACGExtraIconTag];
            UIColor *want = (tinted && ACGTintMode != 0) ? ACGTintColor : own.tintColor;
            if (want != nil && ![label.textColor isEqual:want]) label.textColor = want;
            continue;
        }
        UIColor *native = objc_getAssociatedObject(label, ACGNativeTextColorAssociation);
        if (ACGTintMode == 0) {
            if (native == nil) continue;
            objc_setAssociatedObject(label, ACGNativeTextColorAssociation, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ACGSetLabelColor(label, native);
            continue;
        }
        if (native == nil && label.textColor != nil && ![label.textColor isEqual:ACGTintColor]) {
            native = label.textColor;
            objc_setAssociatedObject(label, ACGNativeTextColorAssociation, native,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        ACGSetLabelColor(label, tinted ? ACGTintColor : native);
    }
    BOOL avatar = [ACGPivotItemIdentifier(item) isEqualToString:@"FElibrary"] &&
        ACGFindPhotoView(item) != nil;
    BOOL tintIcon = tinted && ACGTintMode == 2 && !avatar;
    for (NSNumber *tag in @[@0x59414345, @(ACGExtraIconTag)]) {
        UIView *custom = [item viewWithTag:tag.integerValue];
        if (tintIcon && [custom isKindOfClass:UIImageView.class]) custom.tintColor = ACGTintColor;
    }
    UIImageView *icon = ACGFindImageView(item);
    NSArray *native = icon != nil ? objc_getAssociatedObject(icon, ACGNativeIconAssociation) : nil;
    if (native == nil) return;
    objc_setAssociatedObject(icon, ACGNativeIconAssociation, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (icon.image == native[1]) icon.image = native[0];
    icon.tintColor = native[2];
}

static IMP OriginalIconTintSelected;

static UIColor *ACGIconTintSelected(UIView *receiver, SEL selector) {
    if (ACGTintMode == 2 && ![ACGPivotItemIdentifier(receiver) isEqualToString:@"FElibrary"]) {
        return ACGTintColor;
    }
    return OriginalIconTintSelected == NULL ? nil
        : ((id (*)(id, SEL))OriginalIconTintSelected)(receiver, selector);
}

static void ACGRestyleSelectedTab(UIView *item) {
    SEL setter = NSSelectorFromString(@"setSelected:");
    if (!ACGPivotItemSelected(item) || ![item respondsToSelector:setter]) return;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(item, setter, YES);
}

static void ACGApplyPivotItemPresentation(UIView *view) {
    BOOL hideLabels = ACGTabLabelsHidden(view);
    ACGSetLabelsHidden(view, hideLabels);
    ACGApplyExtraTabIcon(view);
    ACGCenterPivotIcon(view, hideLabels);
    ACGApplyTabTint(view);
}

// Màu icon tab phụ theo các ô gốc, mà YouTube đổi màu ô gốc chậm hơn một nhịp khi vào/ra Short hoặc đổi sáng/tối:
// tính lại ngay rồi tính lại sau 0,12 s và 0,4 s cho mọi tab phụ trên thanh
static const void *ACGRecolorStampAssociation = &ACGRecolorStampAssociation;

static void ACGRecolorExtraTabs(UIView *anyItem) {
    UIView *bar = anyItem;
    while (bar != nil && ![NSStringFromClass(bar.class) isEqualToString:@"YTPivotBarView"]) bar = bar.superview;
    if (bar == nil) return;
    CFTimeInterval now = CACurrentMediaTime();   // mỗi ô đều báo đổi trait: gộp lại, 0,05 s chỉ tính một lần
    if (now - [objc_getAssociatedObject(bar, ACGRecolorStampAssociation) doubleValue] < 0.05) return;
    objc_setAssociatedObject(bar, ACGRecolorStampAssociation, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakBar = bar;
    void (^run)(void) = ^{
        UIView *strong = weakBar;
        if (strong == nil || strong.window == nil) return;
        NSMutableArray<UIView *> *items = [NSMutableArray array];
        ACGCollectPivotItems(strong, items);
        for (UIView *item in items) {
            if ([item viewWithTag:ACGExtraIconTag] != nil) ACGApplyPivotItemPresentation(item);
        }
    };
    run();
    for (NSNumber *delay in @[@0.12, @0.4]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), run);
    }
}

static void ACGPivotButtonLayout(UIView *receiver, SEL selector) {
    if (OriginalPivotButtonLayout != NULL) {
        ((void (*)(id, SEL))OriginalPivotButtonLayout)(receiver, selector);
    }
    if (ACGTintMode != 0) {
        UIView *tintItem = ACGPivotItemAncestor(receiver);
        if (tintItem != nil) ACGApplyTabTint(tintItem);
    }
    UIView *item = ACGPivotItemAncestor(receiver);
    if (item == nil || CGRectIsEmpty(item.bounds) || !ACGTabLabelsHidden(item)) return;
    ACGSetLabelsHidden(receiver, YES);
    UIImageView *icon = nil;
    for (UIView *child in receiver.subviews) {
        if (![child isKindOfClass:UIImageView.class] || child.hidden ||
            CGRectGetWidth(child.bounds) < 12.0 ||
            CGRectGetHeight(child.bounds) < 12.0) {
            continue;
        }
        icon = (UIImageView *)child;
        break;
    }
    if (icon == nil) return;
    CGPoint target = [item convertPoint:CGPointMake(CGRectGetMidX(item.bounds),
                                                    CGRectGetMidY(item.bounds))
                                  toView:receiver];
    icon.center = target;
}

static BOOL ACGContainsCreateText(NSString *value) {
    NSString *text = value.lowercaseString;
    return [text containsString:@"create"] ||
        [text containsString:@"upload"] ||
        [text containsString:@"add video"];
}

static void ACGHideCreateViews(UIView *view) {
    BOOL hideCreate = [NSUserDefaults.standardUserDefaults boolForKey:@"ACG.Preference.Tabs.Hidden.Create"];
    for (UIView *subview in view.subviews) {
        NSString *label = subview.accessibilityLabel;
        NSString *identifier = subview.accessibilityIdentifier;
        NSString *className = NSStringFromClass(subview.class);
        if (hideCreate &&
            (ACGContainsCreateText(label) ||
             ACGContainsCreateText(identifier) ||
             ACGContainsCreateText(className))) {
            subview.hidden = YES;
            subview.userInteractionEnabled = NO;
        }
        ACGHideCreateViews(subview);
    }
}

static NSString * const ACGTabBarGlassModeKey __attribute__((unused)) = @"ACG.Preference.Tabs.GlassMode";

// TẠM TẮT kính lỏng của thanh tab: 0 = tắt hẳn (mọi nhánh kiểu Glass / ép kính YouTube / thu gọn / Shorts tràn đều không chạy,
// thanh tab giữ nguyên giao diện mặc định của YouTube, bỏ qua giá trị đã lưu). Đổi thành 1 để bật lại như trước.
#ifndef ACG_TAB_GLASS_ENABLED
#define ACG_TAB_GLASS_ENABLED 0
#endif

NSInteger ACGTabBarGlassMode(void) {
#if !ACG_TAB_GLASS_ENABLED
    return 0;
#else
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id value = [defaults objectForKey:ACGTabBarGlassModeKey];
    if ([value respondsToSelector:@selector(integerValue)]) return [value integerValue];
    return [defaults boolForKey:@"ACG.Preference.Tabs.Glass"] ? 1 : 0;
#endif
}

BOOL ACGTabBarOwnGlass(void) {
    return ACGTabBarGlassMode() == 1;
}

static IMP ACGOrigYouTubeGlass;
static IMP ACGOrigYouTubeGlassImpl;
static IMP ACGOrigGlassAvailable;
static IMP ACGOrigGlassCompute;
static IMP ACGOrigPivotGlassEffect;
static IMP ACGOrigPivotGlassEffectStyle;

static BOOL ACGForcedYouTubeGlass(IMP original, id receiver, SEL selector) {
    NSInteger mode = ACGTabBarGlassMode();
    BOOL value = original != NULL ? ((BOOL (*)(id, SEL))original)(receiver, selector) : NO;
    ACGDebugLog(@"glass", @"%@ %@ original=%d mode=%ld", NSStringFromClass(object_getClass(receiver)),
                   NSStringFromSelector(selector), value, (long)mode);
    if (mode == 2) return YES;
    if (mode == 1 || mode == 3) return NO;
    return value;
}

static BOOL ACGYouTubeGlass(id receiver, SEL selector) {
    return ACGForcedYouTubeGlass(ACGOrigYouTubeGlass, receiver, selector);
}

static BOOL ACGYouTubeGlassImpl(id receiver, SEL selector) {
    return ACGForcedYouTubeGlass(ACGOrigYouTubeGlassImpl, receiver, selector);
}

static BOOL ACGGlassAvailableValue(IMP original, id receiver, SEL selector) {
    BOOL value = original != NULL ? ((BOOL (*)(id, SEL))original)(receiver, selector) : NO;
    ACGDebugLog(@"glass", @"M3CLiquidGlass %@ original=%d", NSStringFromSelector(selector), value);
    if (ACGTabBarGlassMode() == 2 && NSClassFromString(@"UIGlassEffect") != Nil) return YES;
    return value;
}

static BOOL ACGGlassAvailable(id receiver, SEL selector) {
    return ACGGlassAvailableValue(ACGOrigGlassAvailable, receiver, selector);
}

static BOOL ACGGlassCompute(id receiver, SEL selector) {
    return ACGGlassAvailableValue(ACGOrigGlassCompute, receiver, selector);
}

static id ACGPivotGlassValue(id value, SEL selector) {
    NSInteger mode = ACGTabBarGlassMode();
    ACGDebugLog(@"glass", @"YTPivotBarView %@ effect=%@ mode=%ld", NSStringFromSelector(selector),
                   value != nil ? NSStringFromClass([value class]) : @"nil", (long)mode);
    return mode == 1 || mode == 3 ? nil : value;
}

static id ACGPivotGlassEffect(id receiver, SEL selector) {
    id value = ((id (*)(id, SEL))ACGOrigPivotGlassEffect)(receiver, selector);
    return ACGPivotGlassValue(value, selector);
}

static id ACGPivotGlassEffectStyle(id receiver, SEL selector, NSInteger style) {
    id value = ((id (*)(id, SEL, NSInteger))ACGOrigPivotGlassEffectStyle)(receiver, selector, style);
    return ACGPivotGlassValue(value, selector);
}

static IMP ACGOrigFloatyBars;
static IMP ACGOrigFloatyBarsImpl;
static IMP ACGOrigFloatingStyle;
static IMP ACGOrigFloatingStyleImpl;
static IMP ACGOrigPivotSetFloatingStyle;

static BOOL ACGFloatyValue(IMP original, id receiver, SEL selector) {
    BOOL value = original != NULL ? ((BOOL (*)(id, SEL))original)(receiver, selector) : NO;
    NSInteger mode = ACGTabBarGlassMode();
    ACGDebugLog(@"glass", @"%@ %@ original=%d mode=%ld", NSStringFromClass(object_getClass(receiver)),
                   NSStringFromSelector(selector), value, (long)mode);
    if (mode == 2) return YES;
    if (mode == 1 || mode == 3) return NO;
    return value;
}

static BOOL ACGFloatyBars(id receiver, SEL selector) {
    return ACGFloatyValue(ACGOrigFloatyBars, receiver, selector);
}

static BOOL ACGFloatyBarsImpl(id receiver, SEL selector) {
    return ACGFloatyValue(ACGOrigFloatyBarsImpl, receiver, selector);
}

static long long ACGFloatingStyleValue(IMP original, id receiver, SEL selector) {
    long long value = original != NULL ? ((long long (*)(id, SEL))original)(receiver, selector) : 0;
    NSInteger mode = ACGTabBarGlassMode();
    ACGDebugLog(@"glass", @"%@ %@ original=%lld mode=%ld", NSStringFromClass(object_getClass(receiver)),
                   NSStringFromSelector(selector), value, (long)mode);
    if (mode == 2) return 2;
    if (mode == 1 || mode == 3) return 0;
    return value;
}

static long long ACGFloatingStyle(id receiver, SEL selector) {
    return ACGFloatingStyleValue(ACGOrigFloatingStyle, receiver, selector);
}

static long long ACGFloatingStyleImpl(id receiver, SEL selector) {
    return ACGFloatingStyleValue(ACGOrigFloatingStyleImpl, receiver, selector);
}

static void ACGPivotSetFloatingStyle(id receiver, SEL selector, long long style) {
    NSInteger mode = ACGTabBarGlassMode();
    if ((mode == 1 || mode == 3) && style == 2) style = 0;
    ((void (*)(id, SEL, long long))ACGOrigPivotSetFloatingStyle)(receiver, selector, style);
}

static BOOL ACGMethodTypesMatch(Class cls, NSString *selector, BOOL meta, const char *prefix) {
    Method method = meta ? class_getClassMethod(cls, NSSelectorFromString(selector))
                         : class_getInstanceMethod(cls, NSSelectorFromString(selector));
    const char *types = method != NULL ? method_getTypeEncoding(method) : NULL;
    return types != NULL && strncmp(types, prefix, strlen(prefix)) == 0;
}

static IMP ACGOrigInfoDictionary;
static IMP ACGOrigInfoObject;
static NSString * const ACGDesignCompatibilityKey = @"UIDesignRequiresCompatibility";

static NSDictionary *ACGInfoDictionary(NSBundle *self, SEL _cmd) {
    NSDictionary *info = ((id (*)(id, SEL))ACGOrigInfoDictionary)(self, _cmd);
    if (self != NSBundle.mainBundle || info[ACGDesignCompatibilityKey] == nil) return info;
    NSMutableDictionary *copy = [info mutableCopy];
    [copy removeObjectForKey:ACGDesignCompatibilityKey];
    return copy;
}

static id ACGInfoObject(NSBundle *self, SEL _cmd, NSString *key) {
    if (self == NSBundle.mainBundle && [key isEqualToString:ACGDesignCompatibilityKey]) {
        return nil;
    }
    return ((id (*)(id, SEL, id))ACGOrigInfoObject)(self, _cmd, key);
}

static void ACGInstallLiquidGlassDesign(void) {
    gACGGlassHooked = YES;
    BOOL config = ACGMethodTypesMatch(NSClassFromString(@"YTColdConfig"),
        @"mainAppCoreClientIos27EnableLiquidGlass", NO, "B16") &&
        ACGInstallInstanceHook(@"YTColdConfig", @"mainAppCoreClientIos27EnableLiquidGlass",
            (IMP)ACGYouTubeGlass, &ACGOrigYouTubeGlass);
    BOOL impl = ACGMethodTypesMatch(NSClassFromString(@"YTColdConfigMainAppCoreClientImpl"),
        @"ios27EnableLiquidGlass", NO, "B16") &&
        ACGInstallInstanceHook(@"YTColdConfigMainAppCoreClientImpl", @"ios27EnableLiquidGlass",
            (IMP)ACGYouTubeGlassImpl, &ACGOrigYouTubeGlassImpl);
    BOOL available = ACGMethodTypesMatch(NSClassFromString(@"M3CLiquidGlass"),
        @"isLiquidGlassAvailable", YES, "B16") &&
        ACGInstallClassHook(@"M3CLiquidGlass", @"isLiquidGlassAvailable",
            (IMP)ACGGlassAvailable, &ACGOrigGlassAvailable);
    BOOL compute = ACGMethodTypesMatch(NSClassFromString(@"M3CLiquidGlass"),
        @"computeIsLiquidGlassAvailable", YES, "B16") &&
        ACGInstallClassHook(@"M3CLiquidGlass", @"computeIsLiquidGlassAvailable",
            (IMP)ACGGlassCompute, &ACGOrigGlassCompute);
    BOOL effect = ACGMethodTypesMatch(NSClassFromString(@"YTPivotBarView"), @"liquidGlassEffect", NO, "@16") &&
        ACGInstallInstanceHook(@"YTPivotBarView", @"liquidGlassEffect",
            (IMP)ACGPivotGlassEffect, &ACGOrigPivotGlassEffect);
    BOOL effectStyle = ACGMethodTypesMatch(NSClassFromString(@"YTPivotBarView"),
        @"liquidGlassEffectForPageStyle:", NO, "@24") &&
        ACGInstallInstanceHook(@"YTPivotBarView", @"liquidGlassEffectForPageStyle:",
            (IMP)ACGPivotGlassEffectStyle, &ACGOrigPivotGlassEffectStyle);
    BOOL floaty = ACGMethodTypesMatch(NSClassFromString(@"YTColdConfig"),
        @"mainAppCoreClientIosEnablePositionedFloatyBars", NO, "B16") &&
        ACGInstallInstanceHook(@"YTColdConfig", @"mainAppCoreClientIosEnablePositionedFloatyBars",
            (IMP)ACGFloatyBars, &ACGOrigFloatyBars);
    BOOL floatyImpl = ACGMethodTypesMatch(NSClassFromString(@"YTColdConfigMainAppCoreClientImpl"),
        @"iosEnablePositionedFloatyBars", NO, "B16") &&
        ACGInstallInstanceHook(@"YTColdConfigMainAppCoreClientImpl", @"iosEnablePositionedFloatyBars",
            (IMP)ACGFloatyBarsImpl, &ACGOrigFloatyBarsImpl);
    BOOL floatStyle = ACGMethodTypesMatch(NSClassFromString(@"YTColdConfig"),
        @"mainAppCoreClientIosFloatingBarStyle", NO, "q16") &&
        ACGInstallInstanceHook(@"YTColdConfig", @"mainAppCoreClientIosFloatingBarStyle",
            (IMP)ACGFloatingStyle, &ACGOrigFloatingStyle);
    BOOL floatStyleImpl = ACGMethodTypesMatch(NSClassFromString(@"YTColdConfigMainAppCoreClientImpl"),
        @"iosFloatingBarStyle", NO, "q16") &&
        ACGInstallInstanceHook(@"YTColdConfigMainAppCoreClientImpl", @"iosFloatingBarStyle",
            (IMP)ACGFloatingStyleImpl, &ACGOrigFloatingStyleImpl);
    BOOL pivotStyle = ACGMethodTypesMatch(NSClassFromString(@"YTPivotBarView"), @"setFloatingBarStyle:", NO, "v24") &&
        ACGInstallInstanceHook(@"YTPivotBarView", @"setFloatingBarStyle:",
            (IMP)ACGPivotSetFloatingStyle, &ACGOrigPivotSetFloatingStyle);
    ACGDownloadLog(@"glass", @"youtube glass hooks config=%d impl=%d available=%d compute=%d effect=%d style=%d "
                      "floaty=%d/%d floatStyle=%d/%d pivotStyle=%d mode=%ld",
                      config, impl, available, compute, effect, effectStyle, floaty, floatyImpl, floatStyle,
                      floatStyleImpl, pivotStyle, (long)ACGTabBarGlassMode());
    if (NSClassFromString(@"UIGlassEffect") == Nil) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL any = ACGTabBarGlassMode() == 1 || ACGTabBarGlassMode() == 2;
    for (NSString *key in @[@"ACG.Preference.Glass.TopBar",
                            @"ACG.Preference.Glass.Menus", @"ACG.Preference.Glass.Notices",
                            @"ACG.Preference.Glass.Player"]) {
        if ([defaults boolForKey:key]) any = YES;
    }
    if (!any) return;
    id info = (__bridge id)CFBundleGetInfoDictionary(CFBundleGetMainBundle());
    if ([info respondsToSelector:@selector(removeObjectForKey:)]) {
        @try {
            [info removeObjectForKey:ACGDesignCompatibilityKey];
        } @catch (__unused NSException *exception) {
        }
    }
    ACGInstallInstanceHook(@"NSBundle", @"infoDictionary",
        (IMP)ACGInfoDictionary, &ACGOrigInfoDictionary);
    ACGInstallInstanceHook(@"NSBundle", @"objectForInfoDictionaryKey:",
        (IMP)ACGInfoObject, &ACGOrigInfoObject);
}

static const void *ACGPivotBarSolidAssociation = &ACGPivotBarSolidAssociation;
static const void *ACGPivotBarGlassAssociation = &ACGPivotBarGlassAssociation;
static const void *ACGPivotBarPillAssociation = &ACGPivotBarPillAssociation;
static const void *ACGPivotBarLensAssociation = &ACGPivotBarLensAssociation;
static const void *ACGPivotBarMagnifyAssociation = &ACGPivotBarMagnifyAssociation;
static const void *ACGPivotBarHoleAssociation = &ACGPivotBarHoleAssociation;
static const void *ACGPivotBarPressTimeAssociation = &ACGPivotBarPressTimeAssociation;
static const void *ACGPivotBarFadedAssociation = &ACGPivotBarFadedAssociation;

static BOOL ACGViewContainsPivotItem(UIView *view) {
    static Class itemClass;
    if (itemClass == Nil) itemClass = NSClassFromString(@"YTPivotBarItemView");
    if (itemClass != Nil && [view isKindOfClass:itemClass]) return YES;
    for (UIView *subview in view.subviews) {
        if (ACGViewContainsPivotItem(subview)) return YES;
    }
    return NO;
}

static void ACGCollectPivotItems(UIView *view, NSMutableArray<UIView *> *items) {
    static Class itemClass;
    if (itemClass == Nil) itemClass = NSClassFromString(@"YTPivotBarItemView");
    if (itemClass != Nil && [view isKindOfClass:itemClass]) {
        [items addObject:view];
        return;
    }
    for (UIView *subview in view.subviews) ACGCollectPivotItems(subview, items);
}

static NSHashTable<UIView *> *ACGPivotFadedViews(UIView *bar) {
    NSHashTable *faded = objc_getAssociatedObject(bar, ACGPivotBarFadedAssociation);
    if (faded == nil) {
        faded = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(bar, ACGPivotBarFadedAssociation, faded,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return faded;
}

static UIVisualEffect *ACGMakeGlassEffect(BOOL interactive) {
    Class effectClass = NSClassFromString(@"UIGlassEffect");
    SEL styleSelector = NSSelectorFromString(@"effectWithStyle:");
    UIVisualEffect *effect = [effectClass respondsToSelector:styleSelector]
        ? ((id (*)(id, SEL, NSInteger))objc_msgSend)(effectClass, styleSelector, interactive ? 1 : 0)
        : [effectClass new];
    SEL interactiveSelector = NSSelectorFromString(@"setInteractive:");
    if (interactive && [effect respondsToSelector:interactiveSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, interactiveSelector, YES);
    }
    return effect;
}


static UIView *ACGSelectedPivotItem(UIView *bar) {
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    ACGCollectPivotItems(bar, items);
    for (UIView *item in items) {
        if ([objc_getAssociatedObject(item, ACGTabSelectedAssociation) boolValue]) return item;
    }
    return nil;
}

static NSArray<UIView *> *ACGSortedPivotItems(UIView *bar) {
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    ACGCollectPivotItems(bar, items);
    NSMutableArray<UIView *> *visible = [NSMutableArray array];
    for (UIView *item in items) {
        if (!item.hidden && CGRectGetWidth(item.bounds) > 0.0) [visible addObject:item];
    }
    [visible sortUsingComparator:^NSComparisonResult(UIView *left, UIView *right) {
        CGFloat a = CGRectGetMinX([left convertRect:left.bounds toView:bar]);
        CGFloat b = CGRectGetMinX([right convertRect:right.bounds toView:bar]);
        return a < b ? NSOrderedAscending : (a > b ? NSOrderedDescending : NSOrderedSame);
    }];
    return visible;
}

static void ACGTabGeometry(CGRect glass, NSUInteger count, CGFloat *start, CGFloat *step, CGFloat *overlap) {
    CGFloat spill = count <= 4 ? 8.0 : 16.0;
    CGFloat pitch = count == 0 ? 0.0 : (CGRectGetWidth(glass) - 8.0 - spill) / (CGFloat)count;
    if (start) *start = CGRectGetMinX(glass) + 4.0;
    if (step) *step = pitch;
    if (overlap) *overlap = spill;
}

static CGRect ACGPillFrameForItem(UIView *bar, UIVisualEffectView *glass, UIView *item) {
    NSArray<UIView *> *sorted = ACGSortedPivotItems(bar);
    NSUInteger index = [sorted indexOfObject:item];
    CGRect itemFrame = [item convertRect:item.bounds toView:bar];
    CGFloat inset = 4.0;
    CGFloat left = CGRectGetMinX(itemFrame) + 2.0;
    CGFloat right = CGRectGetMaxX(itemFrame) - 2.0;
    if (index != NSNotFound) {
        CGFloat start = 0.0, step = 0.0, overlap = 0.0;
        ACGTabGeometry(glass.frame, sorted.count, &start, &step, &overlap);
        left = start + step * (CGFloat)index;
        right = left + step + overlap;
    }
    left = MAX(left, CGRectGetMinX(glass.frame) + inset);
    right = MIN(right, CGRectGetMaxX(glass.frame) - inset);
    return CGRectMake(left, CGRectGetMinY(glass.frame) + inset,
                      MAX(right - left, 20.0), CGRectGetHeight(glass.frame) - inset * 2.0);
}

static void ACGLayoutItemsInGlass(UIView *bar, CGRect glassFrame) {
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    ACGCollectPivotItems(bar, items);
    NSMutableArray<UIView *> *visible = [NSMutableArray array];
    for (UIView *item in items) {
        if (!item.hidden && CGRectGetWidth(item.bounds) > 0.0) [visible addObject:item];
    }
    if (visible.count == 0) return;
    [visible sortUsingComparator:^NSComparisonResult(UIView *left, UIView *right) {
        CGFloat a = CGRectGetMinX([left convertRect:left.bounds toView:bar]);
        CGFloat b = CGRectGetMinX([right convertRect:right.bounds toView:bar]);
        return a < b ? NSOrderedAscending : (a > b ? NSOrderedDescending : NSOrderedSame);
    }];
    CGFloat start = 0.0, slot = 0.0, overlap = 0.0;
    ACGTabGeometry(glassFrame, visible.count, &start, &slot, &overlap);
    for (NSUInteger index = 0; index < visible.count; index++) {
        UIView *item = visible[index];
        if (item.superview == nil) continue;
        CGRect current = [item convertRect:item.bounds toView:bar];
        CGRect target = CGRectMake(start + overlap * 0.5 + slot * index,
                                   CGRectGetMidY(glassFrame) - CGRectGetHeight(current) * 0.5,
                                   slot, CGRectGetHeight(current));
        CGRect local = [bar convertRect:target toView:item.superview];
        if (!CGRectEqualToRect(CGRectIntegral(item.frame), CGRectIntegral(local))) {
            item.frame = local;
        }
    }
}

static void ACGSelectPivotItem(UIView *item) {
    id controller = nil;
    id renderer = nil;
    @try {
        controller = [item valueForKey:@"delegate"];
        renderer = [item valueForKey:@"renderer"];
    } @catch (__unused NSException *exception) {
    }
    NSString *identifier = nil;
    @try {
        identifier = [renderer valueForKey:@"pivotIdentifier"];
    } @catch (__unused NSException *exception) {
    }
    SEL tap = NSSelectorFromString(@"didTapItemWithRenderer:");
    if (renderer != nil && [controller respondsToSelector:tap]) {
        ((void (*)(id, SEL, id))objc_msgSend)(controller, tap, renderer);
        return;
    }
    SEL select = NSSelectorFromString(@"selectItemWithPivotIdentifier:");
    if ([identifier isKindOfClass:NSString.class] && identifier.length != 0 &&
        [controller respondsToSelector:select]) {
        ((void (*)(id, SEL, id))objc_msgSend)(controller, select, identifier);
        return;
    }
    SEL buttonSelector = NSSelectorFromString(@"navigationButton");
    UIControl *button = [item respondsToSelector:buttonSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(item, buttonSelector) : nil;
    if ([button isKindOfClass:UIControl.class]) {
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
}

static UIColor *ACGPillColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.0 alpha:0.4]
            : [UIColor colorWithWhite:0.0 alpha:0.08];
    }];
}

static UIView *ACGPivotItemsContainer(UIView *bar) {
    for (UIView *subview in bar.subviews) {
        if (ACGViewContainsPivotItem(subview)) return subview;
    }
    return nil;
}

static void ACGLensSetObject(id lens, NSString *name, id value) {
    SEL selector = NSSelectorFromString(name);
    if ([lens respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(lens, selector, value);
    }
}

static void ACGLensSetInteger(id lens, NSString *name, NSInteger value) {
    SEL selector = NSSelectorFromString(name);
    if ([lens respondsToSelector:selector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(lens, selector, value);
    }
}

static void ACGLensSetBool(id lens, NSString *name, BOOL value) {
    SEL selector = NSSelectorFromString(name);
    if ([lens respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(lens, selector, value);
    }
}

static UIView *ACGMakeSystemLens(UIView *bar) {
    Class lensClass = NSClassFromString(@"_UILiquidLensView");
    SEL initSelector = NSSelectorFromString(@"initWithRestingBackground:");
    if (lensClass == Nil || ![lensClass instancesRespondToSelector:initSelector]) return nil;
    Class selectionClass = NSClassFromString(@"_UITabSelectionView");
    BOOL native = selectionClass != Nil && [selectionClass isSubclassOfClass:UIView.class];
    UIView *resting = native ? [selectionClass new] : [UIView new];
    if (!native) resting.backgroundColor = ACGPillColor();
    UIView *lens = ((id (*)(id, SEL, id))objc_msgSend)([lensClass alloc], initSelector, resting);
    if (![lens isKindOfClass:UIView.class]) return nil;
    ACGLensSetObject(lens, @"setLiftedContainerView:", bar);
    ACGLensSetInteger(lens, @"setLiftedContentMode:", 1);
    ACGLensSetInteger(lens, @"setStyle:", 1);
    ACGLensSetBool(lens, @"setWarpsContentBelow:", YES);
    if (!native) {
        @try {
            [lens setValue:ACGPillColor() forKey:@"restingBackgroundColor"];
        } @catch (__unused NSException *exception) {
        }
    }
    lens.userInteractionEnabled = YES;
    return lens;
}

static BOOL ACGIsSystemLens(UIView *view) {
    Class lensClass = NSClassFromString(@"_UILiquidLensView");
    return lensClass != Nil && [view isKindOfClass:lensClass];
}

static void ACGTrackLens(UIView *lens, CFTimeInterval seconds);
static void ACGLowerWhenArrived(UIView *lens, CGPoint target, id token, dispatch_block_t lower);

static void ACGLensSpring(NSTimeInterval response, CGFloat bounce, CGFloat velocity, dispatch_block_t animations) {
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState |
        UIViewAnimationOptionAllowUserInteraction;
    SEL spring = NSSelectorFromString(@"animateWithSpringDuration:bounce:initialSpringVelocity:delay:options:animations:completion:");
    if ([UIView respondsToSelector:spring]) {
        ((void (*)(id, SEL, NSTimeInterval, CGFloat, CGFloat, NSTimeInterval, UIViewAnimationOptions, id, id))objc_msgSend)(
            UIView.class, spring, response, bounce, velocity, 0.0, options, animations, nil);
    } else {
        [UIView animateWithDuration:response delay:0.0 usingSpringWithDamping:1.0 - bounce
              initialSpringVelocity:velocity options:options animations:animations completion:nil];
    }
}

static const void *ACGPivotBarExpandedAssociation = &ACGPivotBarExpandedAssociation;

static const void *ACGPivotBarMinimizedAssociation = &ACGPivotBarMinimizedAssociation;
static const void *ACGPivotBarMiniAppliedAssociation = &ACGPivotBarMiniAppliedAssociation;
static const void *ACGPivotBarMiniMaskAssociation = &ACGPivotBarMiniMaskAssociation;
static NSString *const ACGMinimizeKey = @"ACG.Preference.Tabs.GlassMinimize";
static __weak UIView *ACGMinimizeBar;
static BOOL ACGMinimizeEnabled;
static CGFloat ACGMinimizeProgress;

static BOOL ACGBarMinimized(UIView *bar) {
    return bar != nil && [objc_getAssociatedObject(bar, ACGPivotBarMinimizedAssociation) boolValue];
}


static NSString *ACGPivotItemIdentifier(UIView *item);

static void ACGBarSpring(NSTimeInterval response, CGFloat damping, NSTimeInterval delay,
                            dispatch_block_t animations, void (^completion)(BOOL)) {
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState |
        UIViewAnimationOptionAllowUserInteraction;
    SEL spring = NSSelectorFromString(@"animateWithSpringDuration:bounce:initialSpringVelocity:delay:options:animations:completion:");
    if ([UIView respondsToSelector:spring]) {
        ((void (*)(id, SEL, NSTimeInterval, CGFloat, CGFloat, NSTimeInterval, UIViewAnimationOptions, id, id))objc_msgSend)(
            UIView.class, spring, response, 1.0 - damping, 0.0, delay, options, animations, completion);
    } else {
        [UIView animateWithDuration:response * 1.5 delay:delay usingSpringWithDamping:damping
              initialSpringVelocity:0.0 options:options animations:animations completion:completion];
    }
}

static void ACGSetBarScale(UIView *bar, CGFloat scale, NSTimeInterval response, CGFloat damping) {
    UIView *glass = objc_getAssociatedObject(bar, ACGPivotBarGlassAssociation);
    CATransform3D transform = CATransform3DIdentity;
    if (glass != nil && fabs(scale - 1.0) > 0.0001) {
        CGFloat dx = CGRectGetMidX(glass.frame) - CGRectGetMidX(bar.bounds);
        CGFloat dy = CGRectGetMidY(glass.frame) - CGRectGetMidY(bar.bounds);
        transform = CATransform3DTranslate(transform, dx, dy, 0.0);
        transform = CATransform3DScale(transform, scale, scale, 1.0);
        transform = CATransform3DTranslate(transform, -dx, -dy, 0.0);
    }
    CALayer *layer = bar.layer;
    if (CATransform3DEqualToTransform(layer.sublayerTransform, transform)) return;
    CALayer *shown = layer.presentationLayer ?: layer;
    CATransform3D from = shown.sublayerTransform;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.sublayerTransform = transform;
    [CATransaction commit];
    if (response <= 0.0) {
        [layer removeAnimationForKey:@"acg.scale"];
        return;
    }
    CASpringAnimation *animation = [CASpringAnimation animationWithKeyPath:@"sublayerTransform"];
    animation.mass = 1.0;
    animation.stiffness = pow(2.0 * M_PI / response, 2.0);
    animation.damping = 4.0 * M_PI * damping / response;
    animation.fromValue = [NSValue valueWithCATransform3D:from];
    animation.toValue = [NSValue valueWithCATransform3D:transform];
    animation.duration = animation.settlingDuration;
    [layer addAnimation:animation forKey:@"acg.scale"];
}

static const void *ACGPivotBarMiniIconAssociation = &ACGPivotBarMiniIconAssociation;
static const void *ACGPivotBarMiniIconRectAssociation = &ACGPivotBarMiniIconRectAssociation;
static NSTimeInterval ACGMiniMaskResponse;
static CGFloat ACGMiniMaskDamping;

static void ACGSpringLayer(CALayer *layer, NSString *key, id from, id to, NSTimeInterval response, CGFloat damping) {
    CASpringAnimation *animation = [CASpringAnimation animationWithKeyPath:key];
    animation.mass = 1.0;
    animation.stiffness = pow(2.0 * M_PI / response, 2.0);
    animation.damping = 4.0 * M_PI * damping / response;
    animation.fromValue = from;
    animation.toValue = to;
    animation.duration = animation.settlingDuration;
    [layer addAnimation:animation forKey:[@"acg." stringByAppendingString:key]];
}

static void ACGInstallMiniMask(UIView *bar) {
    UIView *container = ACGPivotItemsContainer(bar);
    UIView *glass = objc_getAssociatedObject(bar, ACGPivotBarGlassAssociation);
    if (container == nil || glass == nil) return;
    CALayer *mask = objc_getAssociatedObject(bar, ACGPivotBarMiniMaskAssociation);
    if (mask == nil) {
        mask = [CALayer layer];
        mask.backgroundColor = UIColor.blackColor.CGColor;
        mask.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(bar, ACGPivotBarMiniMaskAssociation, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (container.layer.mask == mask) return;
    CGRect frame = [bar convertRect:glass.frame toView:container];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [mask removeAllAnimations];
    mask.bounds = CGRectMake(0, 0, CGRectGetWidth(frame), CGRectGetHeight(frame));
    mask.position = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    mask.cornerRadius = CGRectGetHeight(frame) * 0.5;
    container.layer.mask = mask;
    [CATransaction commit];
}

static void ACGUpdateMiniMask(UIView *bar, CGRect glassFrame) {
    CALayer *mask = objc_getAssociatedObject(bar, ACGPivotBarMiniMaskAssociation);
    UIView *container = ACGPivotItemsContainer(bar);
    if (mask == nil || container == nil || container.layer.mask != mask) return;
    CGRect frame = [bar convertRect:glassFrame toView:container];
    CGRect bounds = CGRectMake(0, 0, CGRectGetWidth(frame), CGRectGetHeight(frame));
    CGPoint position = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    CGFloat radius = CGRectGetHeight(frame) * 0.5;
    if (CGRectEqualToRect(mask.bounds, bounds) && CGPointEqualToPoint(mask.position, position)) return;
    CALayer *shown = mask.presentationLayer ?: mask;
    CGRect fromBounds = shown.bounds;
    CGPoint fromPosition = shown.position;
    CGFloat fromRadius = shown.cornerRadius;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.bounds = bounds;
    mask.position = position;
    mask.cornerRadius = radius;
    [CATransaction commit];
    if (ACGMiniMaskResponse <= 0.0) return;
    ACGSpringLayer(mask, @"bounds", [NSValue valueWithCGRect:fromBounds], [NSValue valueWithCGRect:bounds],
                      ACGMiniMaskResponse, ACGMiniMaskDamping);
    ACGSpringLayer(mask, @"position", [NSValue valueWithCGPoint:fromPosition], [NSValue valueWithCGPoint:position],
                      ACGMiniMaskResponse, ACGMiniMaskDamping);
    ACGSpringLayer(mask, @"cornerRadius", @(fromRadius), @(radius), ACGMiniMaskResponse, ACGMiniMaskDamping);
}

static void ACGRemoveMiniMask(UIView *bar) {
    CALayer *mask = objc_getAssociatedObject(bar, ACGPivotBarMiniMaskAssociation);
    UIView *container = ACGPivotItemsContainer(bar);
    if (mask != nil && container.layer.mask == mask) container.layer.mask = nil;
}

static UIImage *ACGRenderItemIcon(UIView *item, CGRect *iconRect) {
    CGSize size = item.bounds.size;
    CGFloat scale = item.window.screen.scale ?: 3.0;
    size_t width = (size_t)ceil(size.width * scale);
    size_t height = (size_t)ceil(size.height * scale);
    if (width == 0 || height == 0) return nil;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (context == NULL) return nil;
    CGContextTranslateCTM(context, 0.0, (CGFloat)height);
    CGContextScaleCTM(context, scale, -scale);
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    ACGCollectLabels(item, labels);
    NSMutableArray<NSNumber *> *opacity = [NSMutableArray array];
    for (UILabel *label in labels) {
        [opacity addObject:@(label.layer.opacity)];
        label.layer.opacity = 0.0;
    }
    CGFloat alpha = item.alpha;
    item.layer.opacity = 1.0;
    [item.layer renderInContext:context];
    item.layer.opacity = (float)alpha;
    for (NSUInteger index = 0; index < labels.count; index++) {
        labels[index].layer.opacity = opacity[index].floatValue;
    }
    uint8_t *pixels = (uint8_t *)CGBitmapContextGetData(context);
    size_t minX = width, minY = height, maxX = 0, maxY = 0;
    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            if (pixels[(y * width + x) * 4 + 3] < 24) continue;
            minX = MIN(minX, x); maxX = MAX(maxX, x);
            minY = MIN(minY, y); maxY = MAX(maxY, y);
        }
    }
    CGImageRef full = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (full == NULL || maxX < minX || maxY < minY) {
        if (full != NULL) CGImageRelease(full);
        return nil;
    }
    CGRect pixelsRect = CGRectMake(minX, minY, maxX - minX + 1, maxY - minY + 1);
    CGImageRef cropped = CGImageCreateWithImageInRect(full, pixelsRect);
    CGImageRelease(full);
    if (cropped == NULL) return nil;
    UIImage *image = [UIImage imageWithCGImage:cropped scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    if (iconRect != NULL) {
        *iconRect = CGRectMake(pixelsRect.origin.x / scale, pixelsRect.origin.y / scale,
                               pixelsRect.size.width / scale, pixelsRect.size.height / scale);
    }
    return image;
}

static UIImageView *ACGMiniIcon(UIView *bar) {
    UIImageView *icon = objc_getAssociatedObject(bar, ACGPivotBarMiniIconAssociation);
    if (icon == nil) {
        icon = [UIImageView new];
        icon.userInteractionEnabled = NO;
        icon.hidden = YES;
        objc_setAssociatedObject(bar, ACGPivotBarMiniIconAssociation, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return icon;
}

static CGPoint ACGMiniIconHome(UIView *bar, UIView *glass, UIView *selected) {
    NSValue *stored = objc_getAssociatedObject(bar, ACGPivotBarMiniIconRectAssociation);
    CGRect rect = stored != nil ? stored.CGRectValue : selected.bounds;
    CGRect inBar = [selected convertRect:rect toView:bar];
    return CGPointMake(CGRectGetMidX(inBar) - CGRectGetMinX(glass.frame),
                       CGRectGetMidY(inBar) - CGRectGetMinY(glass.frame));
}

static void ACGApplyMiniAlpha(UIView *bar, BOOL minimized) {
    BOOL applied = [objc_getAssociatedObject(bar, ACGPivotBarMiniAppliedAssociation) boolValue];
    if (applied == minimized) return;
    objc_setAssociatedObject(bar, ACGPivotBarMiniAppliedAssociation, minimized ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *selected = ACGSelectedPivotItem(bar);
    UIView *pill = objc_getAssociatedObject(bar, ACGPivotBarPillAssociation);
    pill.alpha = minimized ? 0.0 : 1.0;
    for (UIView *item in ACGSortedPivotItems(bar)) {
        if (item != selected) item.alpha = minimized ? 0.0 : 1.0;
    }
}

static void ACGRestoreMiniIcon(UIView *bar) {
    UIImageView *icon = objc_getAssociatedObject(bar, ACGPivotBarMiniIconAssociation);
    if (icon != nil) icon.hidden = YES;
    for (UIView *item in ACGSortedPivotItems(bar)) item.alpha = 1.0;
}

static void ACGSetBarMinimized(UIView *bar, BOOL minimized) {
    if (bar == nil || ACGBarMinimized(bar) == minimized) return;
    UIView *selected = ACGSelectedPivotItem(bar);
    UIView *glass = objc_getAssociatedObject(bar, ACGPivotBarGlassAssociation);
    if (minimized && (selected == nil || glass == nil ||
                      [ACGPivotItemIdentifier(selected) isEqualToString:@"FEshorts"])) return;
    if (minimized) {
        CGRect rect = CGRectZero;
        UIImage *image = ACGRenderItemIcon(selected, &rect);
        if (image == nil) return;
        objc_setAssociatedObject(bar, ACGPivotBarMiniIconRectAssociation, [NSValue valueWithCGRect:rect],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIImageView *icon = ACGMiniIcon(bar);
        UIView *host = ((UIVisualEffectView *)glass).contentView;
        if (icon.superview != host) [host addSubview:icon];
        [host bringSubviewToFront:icon];
        [UIView performWithoutAnimation:^{
            icon.image = image;
            icon.bounds = CGRectMake(0, 0, CGRectGetWidth(rect), CGRectGetHeight(rect));
            icon.center = ACGMiniIconHome(bar, glass, selected);
            icon.alpha = 1.0;
            icon.hidden = NO;
            selected.alpha = 0.0;
        }];
    }
    objc_setAssociatedObject(bar, ACGPivotBarMinimizedAssociation, minimized ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ACGMinimizeProgress = minimized ? 1.0 : 0.0;
    ACGSetBarScale(bar, 1.0, 0.3, 0.8);
    ACGInstallMiniMask(bar);
    __weak UIView *weakBar = bar;
    NSTimeInterval response = minimized ? 0.36 : 0.3;
    ACGMiniMaskResponse = response;
    ACGMiniMaskDamping = 0.72;
    ACGBarSpring(response, 0.72, 0.0, ^{
        [bar setNeedsLayout];
        [bar layoutIfNeeded];
    }, ^(__unused BOOL finished) {
        UIView *strongBar = weakBar;
        if (strongBar != nil && !ACGBarMinimized(strongBar)) ACGRestoreMiniIcon(strongBar);
    });
    ACGMiniMaskResponse = 0.0;
    UIImageView *miniIcon = objc_getAssociatedObject(bar, ACGPivotBarMiniIconAssociation);
    ACGBarSpring(minimized ? 0.42 : 0.36, minimized ? 0.76 : 0.72, 0.05, ^{
        ACGApplyMiniAlpha(bar, minimized);
        if (!minimized) {
            selected.alpha = 1.0;
            miniIcon.alpha = 0.0;
        }
    }, ^(__unused BOOL finished) {
        UIView *strongBar = weakBar;
        if (strongBar != nil && !ACGBarMinimized(strongBar)) ACGRemoveMiniMask(strongBar);
    });
}

static void ACGSetBarExpanded(UIView *bar, BOOL expanded) {
    if (bar == nil || [objc_getAssociatedObject(bar, ACGPivotBarExpandedAssociation) boolValue] == expanded) return;
    objc_setAssociatedObject(bar, ACGPivotBarExpandedAssociation, expanded ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *lens = objc_getAssociatedObject(bar, ACGPivotBarPillAssociation);
    if (lens != nil) ACGTrackLens(lens, 0.7);
    ACGLensSpring(0.4, expanded ? 0.5 : 0.25, 0.0, ^{
        [bar setNeedsLayout];
        [bar layoutIfNeeded];
    });
}

static void ACGSetSystemLensLifted(UIView *lens, BOOL lifted, __unused NSString *tag,
                                      dispatch_block_t animations, dispatch_block_t done) {
    ACGTrackLens(lens, 0.8);
    SEL selector = NSSelectorFromString(@"setLifted:animated:alongsideAnimations:completion:");
    if (![lens respondsToSelector:selector]) {
        [UIView animateWithDuration:0.3 animations:animations completion:^(__unused BOOL finished) {
            if (done != nil) done();
        }];
        return;
    }
    void (^completion)(BOOL) = ^(__unused BOOL finished) {
        if (done != nil) done();
    };
    ((void (*)(id, SEL, BOOL, BOOL, id, id))objc_msgSend)(lens, selector, lifted, YES,
        animations, completion);
}

static void ACGUpdateGlassPill(UIView *bar, UIVisualEffectView *glass) {
    UIView *pill = objc_getAssociatedObject(bar, ACGPivotBarPillAssociation);
    if (pill == nil) {
        pill = ACGMakeSystemLens(bar);
        if (pill == nil) {
            pill = [UIView new];
            pill.userInteractionEnabled = NO;
            pill.layer.cornerCurve = kCACornerCurveContinuous;
            pill.backgroundColor = ACGPillColor();
        }
        objc_setAssociatedObject(bar, ACGPivotBarPillAssociation, pill,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL dragging = objc_getAssociatedObject(pill, ACGPivotBarFadedAssociation) != nil;
    if (dragging) return;
    if (ACGIsSystemLens(pill)) {
        UIView *host = glass.contentView;
        if (pill.superview != host) {
            [pill removeFromSuperview];
            host.clipsToBounds = NO;
            [host addSubview:pill];
            ACGLensSetObject(pill, @"setLiftedContainerView:", host);
            for (UIView *subview in bar.subviews.copy) {
                if ([NSStringFromClass(subview.class) containsString:@"DestOutView"]) [subview removeFromSuperview];
            }
        }
    } else if (pill.superview != bar) {
        [pill removeFromSuperview];
        [bar insertSubview:pill aboveSubview:glass];
    } else {
        [bar insertSubview:pill aboveSubview:glass];
    }
    UIView *selected = ACGSelectedPivotItem(bar);
    if (selected == nil) {
        pill.hidden = YES;
        return;
    }
    CGRect target = ACGPillFrameForItem(bar, glass, selected);
    BOOL systemLens = ACGIsSystemLens(pill);
    if (systemLens) target = [bar convertRect:target toView:pill.superview];
    CGRect current = pill.frame;
    if (systemLens) {
        current = CGRectMake(pill.center.x - CGRectGetWidth(pill.bounds) * 0.5,
                             pill.center.y - CGRectGetHeight(pill.bounds) * 0.5,
                             CGRectGetWidth(pill.bounds), CGRectGetHeight(pill.bounds));
    }
    BOOL moved = fabs(CGRectGetMidX(current) - CGRectGetMidX(target)) > 1.0 ||
        fabs(CGRectGetMidY(current) - CGRectGetMidY(target)) > 1.0 ||
        fabs(CGRectGetWidth(current) - CGRectGetWidth(target)) > 1.0 ||
        fabs(CGRectGetHeight(current) - CGRectGetHeight(target)) > 1.0;
    BOOL animate = !pill.hidden && !CGRectIsEmpty(current) && moved;
    pill.hidden = NO;
    if (!systemLens) pill.layer.cornerRadius = CGRectGetHeight(target) * 0.5;
    if (systemLens && !moved) return;
    if (systemLens && (!animate || fabs(CGRectGetMidX(current) - CGRectGetMidX(target)) < 12.0)) {
        [UIView performWithoutAnimation:^{
            pill.bounds = CGRectMake(0, 0, CGRectGetWidth(target), CGRectGetHeight(target));
            pill.center = CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target));
        }];
    } else if (animate && systemLens) {
        id token = [NSObject new];
        objc_setAssociatedObject(pill, ACGPivotBarFadedAssociation, token,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGPoint center = CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target));
        CGRect lifted = CGRectMake(0, 0, CGRectGetWidth(target) + 16.0, CGRectGetHeight(target) + 16.0);
        __weak UIView *weakPill = pill;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *settled = weakPill;
            if (settled != nil && objc_getAssociatedObject(settled, ACGPivotBarFadedAssociation) == token) {
                objc_setAssociatedObject(settled, ACGPivotBarFadedAssociation, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        });
        CGPoint start = pill.center;
        ACGSetSystemLensLifted(pill, YES, @"tap", ^{
            pill.bounds = lifted;
            pill.center = start;
        }, nil);
        ACGLensSpring(0.4, 0.15, 0.0, ^{ pill.center = center; });
        ACGLowerWhenArrived(pill, center, token, ^{
            UIView *strongPill = weakPill;
            if (strongPill == nil ||
                objc_getAssociatedObject(strongPill, ACGPivotBarFadedAssociation) != token) return;
            ACGSetSystemLensLifted(strongPill, NO, @"tap", ^{
                strongPill.bounds = CGRectMake(0, 0, CGRectGetWidth(target), CGRectGetHeight(target));
                strongPill.center = center;
            }, ^{
                UIView *lens = weakPill;
                if (lens != nil && objc_getAssociatedObject(lens, ACGPivotBarFadedAssociation) == token) {
                    objc_setAssociatedObject(lens, ACGPivotBarFadedAssociation, nil,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            });
        });
    } else if (animate) {
        [UIView animateWithDuration:0.35 delay:0.0 usingSpringWithDamping:0.8
              initialSpringVelocity:0.3 options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ pill.frame = target; } completion:nil];
    } else {
        pill.frame = target;
    }
}

@interface ACGGlassSlideHandler : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) BOOL lifted;
@property (nonatomic, assign) CGPoint startPoint;
@property (nonatomic, assign) CGFloat restingWidth;
@property (nonatomic, assign) CFTimeInterval pressStart;
@property (nonatomic, assign) CFTimeInterval lastMove;
@property (nonatomic, assign) CGFloat lastX;
@property (nonatomic, assign) CGFloat velocityX;
@property (nonatomic, assign) CGFloat anchorX;
@property (nonatomic, weak) UIView *touchedItem;
@property (nonatomic, weak) UIControl *heldButton;
@property (nonatomic, assign) NSUInteger pressID;
+ (instancetype)sharedHandler;
- (void)handlePress:(UILongPressGestureRecognizer *)gesture;
- (void)attachMagnifierToLens:(UIView *)lens bar:(UIView *)bar;
@end

static NSString *ACGPivotItemIdentifier(UIView *item) {
    id renderer = nil;
    @try {
        renderer = [item valueForKey:@"renderer"];
    } @catch (__unused NSException *exception) {
    }
    id identifier = nil;
    @try {
        identifier = [renderer valueForKey:@"pivotIdentifier"];
    } @catch (__unused NSException *exception) {
    }
    return [identifier isKindOfClass:NSString.class] && [identifier length] != 0 ? identifier : nil;
}

static UIImageView *ACGFindPhotoView(UIView *view) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:UIImageView.class] && !subview.hidden) {
            UIImage *image = ((UIImageView *)subview).image;
            if (image != nil && image.renderingMode != UIImageRenderingModeAlwaysTemplate &&
                CGRectGetWidth(subview.bounds) >= 12.0) {
                return (UIImageView *)subview;
            }
        }
        UIImageView *found = ACGFindPhotoView(subview);
        if (found != nil) return found;
    }
    return nil;
}

static UIImageView *ACGAvatarView(UIView *bar) {
    for (UIView *item in ACGSortedPivotItems(bar)) {
        id renderer = nil;
        @try {
            renderer = [item valueForKey:@"renderer"];
        } @catch (__unused NSException *exception) {
        }
        id identifier = nil;
        @try {
            identifier = [renderer valueForKey:@"pivotIdentifier"];
        } @catch (__unused NSException *exception) {
        }
        if ([identifier isEqual:@"FElibrary"]) return ACGFindPhotoView(item);
    }
    return nil;
}

static const void *ACGStencilSlicesAssociation = &ACGStencilSlicesAssociation;

static UIView *ACGItemContaining(UIView *view, UIView *bar) {
    for (UIView *item in ACGSortedPivotItems(bar)) {
        if ([view isDescendantOfView:item]) return item;
    }
    return nil;
}

static void ACGSyncStencilSlices(UIView *copy) {
    NSMapTable<UIView *, UIView *> *slices = objc_getAssociatedObject(copy, ACGStencilSlicesAssociation);
    if (slices.count == 0) return;
    [UIView performWithoutAnimation:^{
        for (UIView *item in slices) {
            UIView *slice = [slices objectForKey:item];
            if (item.superview == nil) continue;
            CALayer *shown = item.layer.presentationLayer ?: item.layer;
            CGRect frame = [item.superview convertRect:shown.frame toView:copy];
            slice.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        }
    }];
}

static void ACGSyncLensMask(UIView *lens) {
    UIView *copy = objc_getAssociatedObject(lens, ACGPivotBarMagnifyAssociation);
    if (copy == nil || lens.superview == nil) return;
    ACGSyncStencilSlices(copy);
    UIView *mask = copy.maskView;
    if (mask == nil) {
        mask = [UIView new];
        mask.backgroundColor = UIColor.blackColor;
        mask.layer.cornerCurve = kCACornerCurveContinuous;
        copy.maskView = mask;
    }
    CALayer *shown = lens.layer.presentationLayer ?: lens.layer;
    CGRect lensFrame = shown.frame;
    CGRect frame = [lens.superview convertRect:lensFrame toView:copy];
    mask.frame = frame;
    mask.layer.cornerRadius = CGRectGetHeight(frame) * 0.5;
    UIView *items = objc_getAssociatedObject(lens, ACGPivotBarHoleAssociation);
    if (items == nil) return;
    CAShapeLayer *hole = [items.layer.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)items.layer.mask : nil;
    if (hole == nil) {
        hole = [CAShapeLayer layer];
        hole.fillRule = kCAFillRuleEvenOdd;
        items.layer.mask = hole;
    }
    CGRect lensRect = CGRectInset([lens.superview convertRect:lensFrame toView:items], 4.0, 4.0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectInset(items.bounds, -200.0, -200.0)];
    [path appendPath:[UIBezierPath bezierPathWithRoundedRect:lensRect cornerRadius:CGRectGetHeight(lensRect) * 0.5]];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    hole.frame = items.bounds;
    hole.path = path.CGPath;
    [CATransaction commit];
}

@interface ACGLensTracker : NSObject
@property(nonatomic, weak) UIView *lens;
@property(nonatomic, strong) CADisplayLink *link;
@property(nonatomic, assign) CFTimeInterval until;
@property(nonatomic, copy) dispatch_block_t pendingLower;
@property(nonatomic, assign) CGPoint lowerTarget;
@property(nonatomic, weak) id lowerToken;
@end

@implementation ACGLensTracker

- (void)tick {
    UIView *lens = self.lens;
    if (lens == nil || CACurrentMediaTime() > self.until) {
        [self.link invalidate];
        self.link = nil;
        if (lens != nil) ACGSyncLensMask(lens);
        return;
    }
    ACGSyncLensMask(lens);
    [self checkArrival];
}

- (void)checkArrival {
    UIView *lens = self.lens;
    if (lens == nil || self.pendingLower == nil) return;
    CGPoint shown = (lens.layer.presentationLayer ?: lens.layer).position;
    if (fabs(shown.x - self.lowerTarget.x) >= 8.0) return;
    dispatch_block_t lower = self.pendingLower;
    self.pendingLower = nil;
    if (objc_getAssociatedObject(lens, ACGPivotBarFadedAssociation) == self.lowerToken) lower();
}

@end

static const void *ACGLensTrackerAssociation = &ACGLensTrackerAssociation;

static void ACGTrackLens(UIView *lens, CFTimeInterval seconds) {
    if (lens == nil) return;
    ACGLensTracker *tracker = objc_getAssociatedObject(lens, ACGLensTrackerAssociation);
    if (tracker == nil) {
        tracker = [ACGLensTracker new];
        tracker.lens = lens;
        objc_setAssociatedObject(lens, ACGLensTrackerAssociation, tracker, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    tracker.until = MAX(tracker.until, CACurrentMediaTime() + seconds);
    if (tracker.link == nil) {
        tracker.link = [CADisplayLink displayLinkWithTarget:tracker selector:@selector(tick)];
        [tracker.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

static void ACGLowerWhenArrived(UIView *lens, CGPoint target, id token, dispatch_block_t lower) {
    if (lens == nil) return;
    ACGTrackLens(lens, 1.0);
    ACGLensTracker *tracker = objc_getAssociatedObject(lens, ACGLensTrackerAssociation);
    tracker.pendingLower = lower;
    tracker.lowerTarget = target;
    tracker.lowerToken = token;
    __weak ACGLensTracker *weakTracker = tracker;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ACGLensTracker *strongTracker = weakTracker;
        if (strongTracker.pendingLower == nil || strongTracker.pendingLower != lower) return;
        strongTracker.pendingLower = nil;
        UIView *strongLens = strongTracker.lens;
        if (strongLens != nil && objc_getAssociatedObject(strongLens, ACGPivotBarFadedAssociation) == token) lower();
    });
}

static void ACGClearLensHole(UIView *lens) {
    UIView *items = objc_getAssociatedObject(lens, ACGPivotBarHoleAssociation);
    items.layer.mask = nil;
    objc_setAssociatedObject(lens, ACGPivotBarHoleAssociation, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *ACGScrubTarget(UIView *bar, CGPoint point, UIEvent *event);
static UIView *ACGInlinePlayerBar(UIView *bar);

@implementation ACGGlassSlideHandler

+ (instancetype)sharedHandler {
    static ACGGlassSlideHandler *handler;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ handler = [ACGGlassSlideHandler new]; });
    return handler;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    UIView *bar = gesture.view;
    UIView *glass = objc_getAssociatedObject(bar, ACGPivotBarGlassAssociation);
    if (glass == nil) return NO;
    if (ACGBarMinimized(bar)) {
        ACGSetBarMinimized(bar, NO);
        return NO;
    }
    CGPoint point = [gesture locationInView:bar];
    if (!CGRectContainsPoint(glass.frame, point)) return NO;
    UIView *scrub = ACGScrubTarget(bar, point, nil);
    if (scrub != nil && scrub != ACGInlinePlayerBar(bar)) return NO;
    UIView *touched = [self pivotItemNearX:point.x inView:bar bar:bar];
    if (touched != nil && ACGPivotItemIdentifier(touched) == nil) return NO;
    gesture.cancelsTouchesInView = touched == nil || touched != ACGSelectedPivotItem(bar);
    return YES;
}


- (UIVisualEffectView *)lensForBar:(UIView *)bar {
    UIVisualEffectView *lens = objc_getAssociatedObject(bar, ACGPivotBarLensAssociation);
    if (lens == nil) {
        lens = [[UIVisualEffectView alloc] initWithEffect:ACGMakeGlassEffect(YES)];
        lens.userInteractionEnabled = NO;
        lens.layer.cornerCurve = kCACornerCurveContinuous;
        lens.clipsToBounds = YES;
        objc_setAssociatedObject(bar, ACGPivotBarLensAssociation, lens,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (lens.superview != bar) [bar addSubview:lens];
    [bar bringSubviewToFront:lens];
    return lens;
}

- (UIView *)pivotItemNearX:(CGFloat)x inView:(UIView *)view bar:(UIView *)bar {
    NSArray<UIView *> *sorted = ACGSortedPivotItems(bar);
    UIView *glass = objc_getAssociatedObject(bar, ACGPivotBarGlassAssociation);
    if (sorted.count == 0 || glass == nil) return nil;
    CGFloat barX = [view convertPoint:CGPointMake(x, 0.0) toView:bar].x;
    CGFloat start = 0.0, slot = 0.0, overlap = 0.0;
    ACGTabGeometry(glass.frame, sorted.count, &start, &slot, &overlap);
    NSInteger index = slot > 0.0 ? (NSInteger)floor((barX - start - overlap * 0.5) / slot) : 0;
    index = MAX(0, MIN((NSInteger)sorted.count - 1, index));
    return sorted[(NSUInteger)index];
}

- (UIControl *)buttonForItem:(UIView *)item {
    SEL buttonSelector = NSSelectorFromString(@"navigationButton");
    if (![item respondsToSelector:buttonSelector]) return nil;
    UIControl *button = ((id (*)(id, SEL))objc_msgSend)(item, buttonSelector);
    return [button isKindOfClass:UIControl.class] ? button : nil;
}

- (UIView *)stencilForItems:(UIView *)items {
    CGSize size = items.bounds.size;
    CGFloat scale = items.window.screen.scale ?: 3.0;
    size_t width = (size_t)ceil(size.width * scale);
    size_t height = (size_t)ceil(size.height * scale);
    if (width == 0 || height == 0) return nil;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (context == NULL) return nil;
    CGContextTranslateCTM(context, 0.0, (CGFloat)height);
    CGContextScaleCTM(context, scale, -scale);
    NSMutableArray<UIView *> *flipped = [NSMutableArray array];
    SEL setSelected = NSSelectorFromString(@"setSelected:");
    ACGStencilRendering = YES;
    UIView *bar = items.superview;
    UIImageView *avatar = ACGAvatarView(bar);
    BOOL avatarHidden = avatar.hidden;
    avatar.hidden = YES;
    NSMutableArray<UIView *> *draggedOut = [NSMutableArray array];
    for (UIView *item in ACGSortedPivotItems(bar)) {
        if ([objc_getAssociatedObject(item, ACGTabDragOutAssociation) boolValue]) {
            objc_setAssociatedObject(item, ACGTabDragOutAssociation, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [draggedOut addObject:item];
        }
    }
    for (UIView *item in ACGSortedPivotItems(bar)) {
        if (ACGPivotItemSelected(item) || ![item respondsToSelector:setSelected]) continue;
        ((void (*)(id, SEL, BOOL))objc_msgSend)(item, setSelected, YES);
        [item layoutIfNeeded];
        [flipped addObject:item];
    }
    CALayer *hole = items.layer.mask;
    items.layer.mask = nil;
    [items.layer renderInContext:context];
    items.layer.mask = hole;
    for (UIView *item in flipped) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(item, setSelected, NO);
        [item layoutIfNeeded];
    }
    for (UIView *item in draggedOut) {
        objc_setAssociatedObject(item, ACGTabDragOutAssociation, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    avatar.hidden = avatarHidden;
    ACGStencilRendering = NO;
    uint8_t *pixels = (uint8_t *)CGBitmapContextGetData(context);
    double total = 0.0;
    double weight = 0.0;
    for (size_t index = 0; index < width * height; index++) {
        uint8_t *pixel = pixels + index * 4;
        if (pixel[3] < 128) continue;
        uint8_t peak = MAX(pixel[0], MAX(pixel[1], pixel[2]));
        total += (double)peak / (double)pixel[3];
        weight += 1.0;
    }
    BOOL brightIcons = weight == 0.0 || total / weight > 0.5;
    BOOL keepColor = ACGTintMode != 0;
    for (size_t index = 0; !keepColor && index < width * height; index++) {
        uint8_t *pixel = pixels + index * 4;
        uint8_t alpha = pixel[3];
        uint8_t level = 0;
        if (alpha > 0) {
            CGFloat color = (CGFloat)MAX(pixel[0], MAX(pixel[1], pixel[2])) / (CGFloat)alpha;
            CGFloat contrast = brightIcons ? color : 1.0 - color;
            CGFloat ratio = MAX(0.0, MIN(1.0, (contrast - 0.5) / 0.35));
            level = (uint8_t)(ratio * (CGFloat)alpha);
        }
        pixel[0] = level;
        pixel[1] = level;
        pixel[2] = level;
        pixel[3] = level;
    }
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (image == NULL) return nil;
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, size.width, size.height)];
    UIColor *tint = brightIcons ? UIColor.whiteColor : UIColor.blackColor;
    NSMapTable<UIView *, UIView *> *slices = [NSMapTable weakToStrongObjectsMapTable];
    CGRect whole = CGRectMake(0.0, 0.0, size.width, size.height);
    for (UIView *item in ACGSortedPivotItems(bar)) {
        CGRect frame = CGRectIntersection([item convertRect:item.bounds toView:items], whole);
        if (CGRectIsNull(frame) || CGRectIsEmpty(frame)) continue;
        CGRect pixels = CGRectMake(floor(frame.origin.x * scale), floor(frame.origin.y * scale),
                                   ceil(frame.size.width * scale), ceil(frame.size.height * scale));
        CGImageRef piece = CGImageCreateWithImageInRect(image, pixels);
        if (piece == NULL) continue;
        UIImageView *slice = [[UIImageView alloc] initWithImage:
            [[UIImage imageWithCGImage:piece scale:scale orientation:UIImageOrientationUp]
                imageWithRenderingMode:keepColor ? UIImageRenderingModeAlwaysOriginal
                                                 : UIImageRenderingModeAlwaysTemplate]];
        CGImageRelease(piece);
        slice.frame = CGRectMake(pixels.origin.x / scale, pixels.origin.y / scale,
                                 pixels.size.width / scale, pixels.size.height / scale);
        slice.tintColor = tint;
        [view addSubview:slice];
        [slices setObject:slice forKey:item];
    }
    CGImageRelease(image);
    if (avatar != nil && !avatarHidden && avatar.image != nil && avatar.window != nil) {
        CGRect face = [avatar convertRect:avatar.bounds toView:items];
        CGFloat radius = MIN(avatar.layer.cornerRadius, MIN(face.size.width, face.size.height) * 0.5);
        if (radius <= 0.0) radius = MIN(face.size.width, face.size.height) * 0.5;
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
        format.scale = scale;
        UIImage *photo = [[[UIGraphicsImageRenderer alloc] initWithSize:face.size format:format]
            imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
            CGRect bounds = CGRectMake(0.0, 0.0, face.size.width, face.size.height);
            [[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:radius] addClip];
            CGSize source = avatar.image.size;
            CGFloat fill = source.width > 0.0 && source.height > 0.0
                ? MAX(bounds.size.width / source.width, bounds.size.height / source.height) : 1.0;
            CGSize drawn = CGSizeMake(source.width * fill, source.height * fill);
            [avatar.image drawInRect:CGRectMake((bounds.size.width - drawn.width) * 0.5,
                                                (bounds.size.height - drawn.height) * 0.5,
                                                drawn.width, drawn.height)];
        }];
        UIImageView *photoSlice = [[UIImageView alloc] initWithImage:photo];
        photoSlice.frame = face;
        [view addSubview:photoSlice];
        UIView *owner = ACGItemContaining(avatar, bar);
        if (owner != nil) {
            UIView *holder = [slices objectForKey:owner];
            if (holder != nil) {
                photoSlice.frame = [view convertRect:face toView:holder];
                [holder addSubview:photoSlice];
            }
        }
    }
    objc_setAssociatedObject(view, ACGStencilSlicesAssociation, slices, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return view;
}

- (void)attachMagnifierToLens:(UIView *)lens bar:(UIView *)bar {
    UIView *old = objc_getAssociatedObject(lens, ACGPivotBarMagnifyAssociation);
    [old removeFromSuperview];
    UIView *items = ACGPivotItemsContainer(bar);
    UIView *copy = [self stencilForItems:items];
    if (copy == nil || lens.superview == nil) return;
    copy.userInteractionEnabled = NO;
    copy.frame = [items convertRect:items.bounds toView:lens.superview];
    [lens.superview insertSubview:copy atIndex:0];
    ACGLensSetObject(lens, @"setLiftedContentView:", copy);
    objc_setAssociatedObject(lens, ACGPivotBarMagnifyAssociation, copy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(lens, ACGPivotBarHoleAssociation, items, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ACGSyncLensMask(lens);
}

- (void)liftLens:(UIView *)lens bar:(UIView *)bar size:(CGSize)size center:(CGPoint)center {
    ACGSetBarExpanded(bar, YES);
    NSUInteger pressID = self.pressID;
    __weak UIView *weakLens = lens;
    __weak UIView *weakBar = bar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *strongLens = weakLens;
        if (strongLens == nil || weakBar == nil || !self.lifted || self.pressID != pressID) return;
        [self attachMagnifierToLens:strongLens bar:weakBar];
    });
    UIView *old = objc_getAssociatedObject(lens, ACGPivotBarMagnifyAssociation);
    [old removeFromSuperview];
    UIView *items = ACGPivotItemsContainer(bar);
    UIView *copy = [self stencilForItems:items];
    if (copy != nil && lens.superview != nil) {
        copy.userInteractionEnabled = NO;
        copy.frame = [items convertRect:items.bounds toView:lens.superview];
        [lens.superview insertSubview:copy atIndex:0];
        ACGLensSetObject(lens, @"setLiftedContentView:", copy);
        objc_setAssociatedObject(lens, ACGPivotBarMagnifyAssociation, copy,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(lens, ACGPivotBarHoleAssociation, items,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ACGSyncLensMask(lens);
    }
    self.lifted = YES;
    ACGSetSystemLensLifted(lens, YES, @"press", ^{
        lens.bounds = CGRectMake(0, 0, size.width, size.height);
        ACGSyncLensMask(lens);
    }, nil);
    ACGLensSpring(0.4, 0.15, 0.0, ^{ lens.center = center; });
}

- (void)handleSystemLens:(UIView *)lens gesture:(UILongPressGestureRecognizer *)gesture
                     bar:(UIView *)bar glass:(UIView *)glass {
    UIView *host = lens.superview ?: bar;
    CGPoint point = [gesture locationInView:bar];
    UIView *selectedNow = ACGSelectedPivotItem(bar);
    CGRect restingFrame = selectedNow != nil
        ? [bar convertRect:ACGPillFrameForItem(bar, (UIVisualEffectView *)glass, selectedNow) toView:host]
        : lens.frame;
    CGFloat lensWidth = self.lifted ? self.restingWidth : CGRectGetWidth(restingFrame);
    CGFloat width = lensWidth + 16.0;
    CGFloat height = CGRectGetHeight(restingFrame) + 16.0;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIView *grabbed = [self pivotItemNearX:point.x inView:bar bar:bar];
        CGRect slot = grabbed != nil ? ACGPillFrameForItem(bar, (UIVisualEffectView *)glass, grabbed) : CGRectNull;
        self.anchorX = CGRectIsNull(slot) || CGRectGetWidth(slot) <= 0.0
            ? 0.5 : MAX(0.0, MIN(1.0, (point.x - CGRectGetMinX(slot)) / CGRectGetWidth(slot)));
    }
    CGFloat anchor = self.anchorX;
    CGFloat clamped = MAX(CGRectGetMinX(glass.frame) + lensWidth * anchor,
                          MIN(point.x, CGRectGetMaxX(glass.frame) - lensWidth * (1.0 - anchor)));
    CGFloat centerX = clamped - lensWidth * anchor + lensWidth * 0.5;
    CGPoint center = [bar convertPoint:CGPointMake(centerX, CGRectGetMidY(glass.frame)) toView:host];
    CFTimeInterval now = CACurrentMediaTime();
    if (gesture.state == UIGestureRecognizerStateBegan) {
        objc_setAssociatedObject(lens, ACGPivotBarFadedAssociation, [NSObject new],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        self.pressStart = now;
        self.lastMove = now;
        self.lastX = point.x;
        self.velocityX = 0.0;
        self.startPoint = point;
        self.dragging = NO;
        self.lifted = NO;
        self.restingWidth = CGRectGetWidth(restingFrame);
        self.touchedItem = [self pivotItemNearX:point.x inView:bar bar:bar];
        self.heldButton = nil;
        self.pressID += 1;
        UIView *selected = ACGSelectedPivotItem(bar);
        BOOL same = self.touchedItem == selected;
        for (UIView *subview in bar.subviews.copy) {
            if ([NSStringFromClass(subview.class) containsString:@"DestOutView"]) [subview removeFromSuperview];
        }
        (void)same;
        if (self.touchedItem != nil) {
            [self liftLens:lens bar:bar size:CGSizeMake(width, height) center:center];
        }
        return;
    }
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CFTimeInterval step = now - self.lastMove;
        if (step > 0.001) {
            CGFloat instant = (point.x - self.lastX) / step;
            self.velocityX = instant * 0.6 + self.velocityX * 0.4;
            self.lastX = point.x;
            self.lastMove = now;
        }
        if (!self.dragging && fabs(point.x - self.startPoint.x) > 4.0) {
            self.dragging = YES;
            if (!gesture.cancelsTouchesInView) {
                self.heldButton = [self buttonForItem:self.touchedItem];
            }
            if (!self.lifted) {
                [self liftLens:lens bar:bar size:CGSizeMake(width, height) center:center];
                return;
            }
        }
        if (!self.lifted) return;
        ACGLensSpring(0.2, 0.15, 0.0, ^{ lens.center = center; });
        ACGTrackLens(lens, 0.4);
        return;
    }
    if (gesture.state != UIGestureRecognizerStateEnded &&
        gesture.state != UIGestureRecognizerStateCancelled) {
        return;
    }
    BOOL dragging = self.dragging;
    self.pressID += 1;
    ACGSetBarExpanded(bar, NO);
    UIView *draggedFrom = self.touchedItem;
    if ([objc_getAssociatedObject(draggedFrom, ACGTabDragOutAssociation) boolValue]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            objc_setAssociatedObject(draggedFrom, ACGTabDragOutAssociation, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ACGApplyPivotItemPresentation(draggedFrom);
        });
    }
    UIControl *heldButton = self.heldButton;
    self.heldButton = nil;
    if (!self.lifted) {
        BOOL bump = !dragging && gesture.state == UIGestureRecognizerStateEnded &&
            self.touchedItem != nil && self.touchedItem == ACGSelectedPivotItem(bar);
        if (!bump) {
            objc_setAssociatedObject(lens, ACGPivotBarFadedAssociation, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIView *tapped = self.touchedItem;
            if (gesture.state == UIGestureRecognizerStateEnded && tapped != nil &&
                ACGPivotItemIdentifier(tapped) != nil && tapped != ACGSelectedPivotItem(bar)) {
                ACGSelectPivotItem(tapped);
            }
            return;
        }
        id bumpToken = [NSObject new];
        objc_setAssociatedObject(lens, ACGPivotBarFadedAssociation, bumpToken,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGRect resting = restingFrame;
        CGPoint middle = CGPointMake(CGRectGetMidX(resting), CGRectGetMidY(resting));
        __weak UIView *weakBump = lens;
        ACGSetSystemLensLifted(lens, YES, @"bump", ^{
            lens.bounds = CGRectMake(0, 0, CGRectGetWidth(resting) + 14.0, CGRectGetHeight(resting) + 10.0);
            lens.center = middle;
        }, nil);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *bumped = weakBump;
            if (bumped == nil || objc_getAssociatedObject(bumped, ACGPivotBarFadedAssociation) != bumpToken) return;
            ACGSetSystemLensLifted(bumped, NO, @"bump", ^{
                bumped.bounds = CGRectMake(0, 0, CGRectGetWidth(resting), CGRectGetHeight(resting));
                bumped.center = middle;
            }, nil);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *bumped = weakBump;
            if (bumped != nil && objc_getAssociatedObject(bumped, ACGPivotBarFadedAssociation) == bumpToken) {
                objc_setAssociatedObject(bumped, ACGPivotBarFadedAssociation, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        });
        return;
    }
    self.lifted = NO;
    id token = [NSObject new];
    objc_setAssociatedObject(lens, ACGPivotBarFadedAssociation, token,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *nearest = dragging ? [self pivotItemNearX:point.x inView:bar bar:bar] : self.touchedItem;
    if (gesture.state == UIGestureRecognizerStateCancelled) nearest = ACGSelectedPivotItem(bar);
    if (nearest != nil && ACGPivotItemIdentifier(nearest) == nil) nearest = ACGSelectedPivotItem(bar);
    CGRect target = nearest != nil
        ? [bar convertRect:ACGPillFrameForItem(bar, (UIVisualEffectView *)glass, nearest) toView:host]
        : lens.frame;
    __weak UIView *weakLens = lens;
    CGPoint slide = CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target));
    ACGLensSpring(0.4, 0.15, 0.0, ^{
        lens.center = slide;
        ACGSyncLensMask(lens);
    });
    ACGLowerWhenArrived(lens, slide, token, ^{
        UIView *lowering = weakLens;
        if (lowering == nil || objc_getAssociatedObject(lowering, ACGPivotBarFadedAssociation) != token) return;
        UIView *copy = objc_getAssociatedObject(lowering, ACGPivotBarMagnifyAssociation);
        copy.hidden = YES;
        ACGClearLensHole(lowering);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *settled = weakLens;
            if (settled != nil && objc_getAssociatedObject(settled, ACGPivotBarFadedAssociation) == token) {
                objc_setAssociatedObject(settled, ACGPivotBarFadedAssociation, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        });
        ACGSetSystemLensLifted(lowering, NO, @"up", ^{
            lowering.bounds = CGRectMake(0, 0, target.size.width, target.size.height);
            lowering.center = slide;
            ACGSyncLensMask(lowering);
        }, ^{
            UIView *strongLens = weakLens;
            if (strongLens != nil && objc_getAssociatedObject(strongLens, ACGPivotBarFadedAssociation) == token) {
                objc_setAssociatedObject(strongLens, ACGPivotBarFadedAssociation, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        });
    });
    if (gesture.state == UIGestureRecognizerStateEnded && nearest != nil &&
        nearest != ACGSelectedPivotItem(bar)) {
        if (heldButton != nil) {
            __weak UIView *weakNearest = nearest;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                UIView *pick = weakNearest;
                if (pick != nil && pick != ACGSelectedPivotItem(bar)) ACGSelectPivotItem(pick);
            });
        } else {
            ACGSelectPivotItem(nearest);
        }
    }
}

- (CGFloat)lensCenterForPoint:(CGPoint)point bar:(UIView *)bar glass:(UIView *)glass width:(CGFloat)width {
    return MAX(CGRectGetMinX(glass.frame) + width * 0.35,
               MIN(point.x, CGRectGetMaxX(glass.frame) - width * 0.35));
}

- (void)handlePress:(UILongPressGestureRecognizer *)gesture {
    UIView *bar = gesture.view;
    UIView *glass = objc_getAssociatedObject(bar, ACGPivotBarGlassAssociation);
    UIView *pill = objc_getAssociatedObject(bar, ACGPivotBarPillAssociation);
    if (glass == nil || pill == nil) return;
    if (ACGIsSystemLens(pill)) {
        [self handleSystemLens:pill gesture:gesture bar:bar glass:glass];
        return;
    }
    UIVisualEffectView *lens = [self lensForBar:bar];
    CGPoint point = [gesture locationInView:bar];
    CGFloat width = MAX(CGRectGetWidth(pill.frame), 80.0) + 26.0;
    CGFloat height = CGRectGetHeight(glass.frame) + 18.0;
    CGFloat centerX = [self lensCenterForPoint:point bar:bar glass:glass width:width];
    CGPoint center = CGPointMake(centerX, CGRectGetMidY(glass.frame));
    if (gesture.state == UIGestureRecognizerStateBegan) {
        objc_setAssociatedObject(pill, ACGPivotBarFadedAssociation, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        lens.bounds = pill.bounds.size.width > 0 ? pill.bounds : CGRectMake(0, 0, width, height);
        lens.center = pill.frame.size.width > 0
            ? CGPointMake(CGRectGetMidX(pill.frame), CGRectGetMidY(pill.frame)) : center;
        lens.layer.cornerRadius = CGRectGetHeight(lens.bounds) * 0.5;
        lens.alpha = 0.0;
        lens.hidden = NO;
        [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.7
              initialSpringVelocity:0.5 options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            lens.alpha = 1.0;
            lens.bounds = CGRectMake(0, 0, width, height);
            lens.layer.cornerRadius = height * 0.5;
            lens.center = center;
            pill.alpha = 0.0;
        } completion:nil];
        return;
    }
    if (gesture.state == UIGestureRecognizerStateChanged) {
        [UIView animateWithDuration:0.12 delay:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionCurveEaseOut
                         animations:^{ lens.center = center; } completion:nil];
        return;
    }
    if (gesture.state != UIGestureRecognizerStateEnded &&
        gesture.state != UIGestureRecognizerStateCancelled) {
        return;
    }
    objc_setAssociatedObject(pill, ACGPivotBarFadedAssociation, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    ACGCollectPivotItems(bar, items);
    UIView *nearest = nil;
    CGFloat best = CGFLOAT_MAX;
    for (UIView *item in items) {
        if (item.hidden || CGRectGetWidth(item.bounds) <= 0.0) continue;
        CGFloat distance = fabs(CGRectGetMidX([item convertRect:item.bounds toView:bar]) - lens.center.x);
        if (distance < best) {
            best = distance;
            nearest = item;
        }
    }
    CGRect target = nearest != nil
        ? ACGPillFrameForItem(bar, (UIVisualEffectView *)glass, nearest) : pill.frame;
    pill.frame = target;
    pill.layer.cornerRadius = CGRectGetHeight(target) * 0.5;
    [UIView animateWithDuration:0.32 delay:0.0 usingSpringWithDamping:0.8
          initialSpringVelocity:0.3 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        lens.bounds = CGRectMake(0, 0, target.size.width, target.size.height);
        lens.layer.cornerRadius = target.size.height * 0.5;
        lens.center = CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target));
        lens.alpha = 0.0;
        pill.alpha = 1.0;
    } completion:^(BOOL finished) {
        if (finished) lens.hidden = YES;
    }];
    if (gesture.state == UIGestureRecognizerStateEnded && nearest != nil &&
        nearest != ACGSelectedPivotItem(bar)) {
        ACGSelectPivotItem(nearest);
    }
}

@end

static void ACGInstallGlassSlide(UIView *bar) {
    for (UIGestureRecognizer *recognizer in bar.gestureRecognizers) {
        if (recognizer.delegate == [ACGGlassSlideHandler sharedHandler]) return;
    }
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[ACGGlassSlideHandler sharedHandler] action:@selector(handlePress:)];
    press.minimumPressDuration = 0.0;
    press.allowableMovement = CGFLOAT_MAX;
    press.cancelsTouchesInView = NO;
    press.delaysTouchesEnded = NO;
    press.delegate = [ACGGlassSlideHandler sharedHandler];
    [bar addGestureRecognizer:press];
}

BOOL ACGLiquidGlassAvailable(void) {
    return NSClassFromString(@"UIGlassEffect") != Nil;
}

static BOOL ACGViewLooksLikeScrubber(UIView *view, NSUInteger depth) {
    NSString *name = NSStringFromClass(view.class).lowercaseString;
    for (NSString *word in @[@"scrub", @"progress", @"playerbar", @"slider", @"seek", @"timebar"]) {
        if ([name containsString:word]) return YES;
    }
    if (depth == 0) return NO;
    for (UIView *subview in view.subviews) {
        if (ACGViewLooksLikeScrubber(subview, depth - 1)) return YES;
    }
    return NO;
}

static UIView *ACGInlinePlayerBar(UIView *bar) {
    Class playerBarClass = NSClassFromString(@"YTInlinePlayerBarContainerView");
    if (playerBarClass == Nil || objc_getAssociatedObject(bar, ACGPivotBarGlassAssociation) == nil) return nil;
    for (UIView *child in bar.subviews) {
        if ([child isKindOfClass:playerBarClass] && !child.hidden && child.alpha > 0.01 &&
            child.userInteractionEnabled && child.window != nil) {
            return child;
        }
    }
    return nil;
}

static UIView *ACGScrubTarget(UIView *bar, CGPoint point, UIEvent *event) {
    UIView *playerBar = ACGInlinePlayerBar(bar);
    if (playerBar == nil) return nil;
    CGPoint local = [bar convertPoint:point toView:playerBar];
    if (CGRectContainsPoint(playerBar.bounds, local)) return [playerBar hitTest:local withEvent:event];
    UIView *glass = objc_getAssociatedObject(bar, ACGPivotBarGlassAssociation);
    if (point.y >= CGRectGetMinY(glass.frame) + 12.0) return nil;
    Class gestureClass = NSClassFromString(@"YTInlineScrubGestureView");
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:playerBar];
    while (queue.count != 0) {
        UIView *node = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (gestureClass != Nil && [node isKindOfClass:gestureClass] && !node.hidden && node.userInteractionEnabled) {
            CGPoint inside = [bar convertPoint:point toView:node];
            return CGRectContainsPoint(node.bounds, inside) ? node : nil;
        }
        [queue addObjectsFromArray:node.subviews];
    }
    return nil;
}

static IMP OriginalPivotBarPointInside;
static IMP OriginalPivotBarHitTest;

static BOOL ACGPivotBarPointInside(UIView *receiver, SEL selector, CGPoint point, UIEvent *event) {
    BOOL inside = OriginalPivotBarPointInside != NULL &&
        ((BOOL (*)(id, SEL, CGPoint, id))OriginalPivotBarPointInside)(receiver, selector, point, event);
    if (ACGBarMinimized(receiver)) {
        UIView *glass = objc_getAssociatedObject(receiver, ACGPivotBarGlassAssociation);
        return glass != nil && CGRectContainsPoint(CGRectInset(glass.frame, -6.0, -6.0), point);
    }
    if (inside) return YES;
    UIView *playerBar = ACGInlinePlayerBar(receiver);
    return playerBar != nil && CGRectContainsPoint(playerBar.frame, point);
}

static UIView *ACGPivotBarHitTest(UIView *receiver, SEL selector, CGPoint point, UIEvent *event) {
    if (ACGBarMinimized(receiver)) {
        UIView *glass = objc_getAssociatedObject(receiver, ACGPivotBarGlassAssociation);
        return glass != nil && CGRectContainsPoint(CGRectInset(glass.frame, -6.0, -6.0), point) ? receiver : nil;
    }
    UIView *scrub = ACGScrubTarget(receiver, point, event);
    if (scrub != nil && scrub != ACGInlinePlayerBar(receiver)) return scrub;
    if (!CGRectContainsPoint(receiver.bounds, point)) return nil;
    return OriginalPivotBarHitTest == NULL ? nil
        : ((id (*)(id, SEL, CGPoint, id))OriginalPivotBarHitTest)(receiver, selector, point, event);
}

static CGFloat const ACGMinimizeDistance = 64.0;
static BOOL ACGMinimizeActive;
static __weak UIScrollView *ACGMinimizeScroll;
static CGFloat ACGMinimizeLastOffset;
static const void *ACGMinimizePanAssociation = &ACGMinimizePanAssociation;

static BOOL ACGMinimizeEligible(UIScrollView *scrollView, UIView *bar) {
    UIWindow *window = bar.window;
    if (window == nil || scrollView.window != window || bar.hidden || bar.alpha < 0.01) return NO;
    if (CGRectGetHeight(scrollView.bounds) < CGRectGetHeight(window.bounds) * 0.4) return NO;
    CGFloat range = scrollView.contentSize.height + scrollView.adjustedContentInset.top +
        scrollView.adjustedContentInset.bottom - CGRectGetHeight(scrollView.bounds);
    if (range < ACGMinimizeDistance * 1.5) return NO;
    if (!CGRectIntersectsRect([bar convertRect:bar.bounds toView:window], window.bounds)) return NO;
    UIView *selected = ACGSelectedPivotItem(bar);
    return selected != nil && ![ACGPivotItemIdentifier(selected) isEqualToString:@"FEshorts"];
}

static void ACGApplyMinimizeProgress(UIView *bar, CGFloat progress, BOOL tracking) {
    ACGMinimizeProgress = progress;
    CGFloat scale = (progress <= 0.0 || progress >= 1.0) ? 1.0 : 1.0 - progress * 0.05;
    if (tracking) ACGSetBarScale(bar, scale, 0.1, 0.8);
    else ACGSetBarScale(bar, scale, 0.3, 0.8);
}

@interface ACGMinimizePanTracker : NSObject
@end

@implementation ACGMinimizePanTracker

- (void)pan:(UIPanGestureRecognizer *)pan {
    UIScrollView *scrollView = (UIScrollView *)pan.view;
    UIView *bar = ACGMinimizeBar;
    if (!ACGMinimizeEnabled || bar == nil || ![scrollView isKindOfClass:UIScrollView.class]) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        if (!ACGMinimizeEligible(scrollView, bar)) return;
        ACGMinimizeActive = YES;
        ACGMinimizeScroll = scrollView;
        ACGMinimizeLastOffset = scrollView.contentOffset.y;
        return;
    }
    if (pan.state != UIGestureRecognizerStateEnded && pan.state != UIGestureRecognizerStateCancelled &&
        pan.state != UIGestureRecognizerStateFailed) return;
    if (!ACGMinimizeActive || ACGMinimizeScroll != scrollView) return;
    ACGMinimizeActive = NO;
    BOOL minimized = ACGBarMinimized(bar);
    CGFloat progress = ACGMinimizeProgress;
    CGFloat velocity = -[pan velocityInView:scrollView].y;
    if (pan.state == UIGestureRecognizerStateEnded && fabs(velocity) > 50.0) {
        CGFloat rate = scrollView.decelerationRate;
        CGFloat travel = velocity / 1000.0 * rate / MAX(0.0001, 1.0 - rate);
        CGFloat minY = -scrollView.adjustedContentInset.top;
        CGFloat maxY = MAX(minY, scrollView.contentSize.height + scrollView.adjustedContentInset.bottom -
                                 CGRectGetHeight(scrollView.bounds));
        CGFloat target = MAX(minY, MIN(maxY, scrollView.contentOffset.y + travel));
        progress += (target - scrollView.contentOffset.y) / ACGMinimizeDistance;
        if (target <= minY + 0.5) progress = 0.0;
    }
    if (progress >= 1.0) {
        if (minimized) ACGApplyMinimizeProgress(bar, 1.0, NO);
        else ACGSetBarMinimized(bar, YES);
    } else if (minimized) {
        ACGSetBarMinimized(bar, NO);
    } else {
        ACGApplyMinimizeProgress(bar, 0.0, NO);
    }
}

@end

static IMP OriginalScrollSetContentOffset;

static NSUInteger ACGShortsClipGeneration;

static NSArray<UIView *> *ACGShortsClipViews(UIScrollView *pager) {
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:pager];
    for (UIView *view = pager.superview.superview.superview; view != nil && views.count < 3; view = view.superview) {
        if ([view isKindOfClass:NSClassFromString(@"YTAppView")]) break;
        if (view.clipsToBounds) [views addObject:view];
    }
    return views;
}

static const void *ACGShortsClipViewsAssociation = &ACGShortsClipViewsAssociation;
static const void *ACGShortsCoverAssociation = &ACGShortsCoverAssociation;

static UIView *ACGShortsCover(UIScrollView *pager, NSArray<UIView *> *views, BOOL create) {
    UIView *cover = objc_getAssociatedObject(pager, ACGShortsCoverAssociation);
    if (cover != nil || !create) return cover;
    UIView *outer = views.lastObject;
    if (outer == nil || outer.window == nil) return nil;
    CGRect frame = [outer convertRect:outer.bounds toView:nil];
    CGFloat below = CGRectGetHeight(outer.window.bounds) - CGRectGetMaxY(frame);
    if (below <= 0.5) return nil;
    cover = [[UIView alloc] initWithFrame:CGRectMake(0.0, CGRectGetHeight(outer.bounds), CGRectGetWidth(outer.bounds), below)];
    cover.backgroundColor = UIColor.blackColor;
    cover.userInteractionEnabled = NO;
    cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [outer addSubview:cover];
    UIView *backing = [[UIView alloc] initWithFrame:[outer.superview convertRect:cover.frame fromView:outer]];
    backing.backgroundColor = UIColor.blackColor;
    backing.userInteractionEnabled = NO;
    backing.autoresizingMask = cover.autoresizingMask;
    [outer.superview insertSubview:backing belowSubview:outer];
    objc_setAssociatedObject(cover, ACGShortsCoverAssociation, backing, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(pager, ACGShortsCoverAssociation, cover, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return cover;
}

static void ACGFadeShortsCover(UIView *cover, CGFloat alpha, void (^completion)(BOOL finished)) {
    [UIView animateWithDuration:0.2 delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ cover.alpha = alpha; }
                     completion:completion];
}

static void ACGSetShortsClipping(UIScrollView *pager, BOOL clips) {
    NSArray<UIView *> *views = objc_getAssociatedObject(pager, ACGShortsClipViewsAssociation);
    if (!clips) {
        if (views == nil) {
            views = ACGShortsClipViews(pager);
            objc_setAssociatedObject(pager, ACGShortsClipViewsAssociation, views, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIView *cover = ACGShortsCover(pager, views, YES);
        cover.alpha = 1.0;
        for (UIView *view in views) view.clipsToBounds = NO;
        if (cover != nil) ACGFadeShortsCover(cover, 0.0, nil);
        return;
    }
    UIView *cover = ACGShortsCover(pager, views, NO);
    void (^reclip)(void) = ^{
        for (UIView *view in views) view.clipsToBounds = YES;
        [(UIView *)objc_getAssociatedObject(cover, ACGShortsCoverAssociation) removeFromSuperview];
        [cover removeFromSuperview];
        objc_setAssociatedObject(pager, ACGShortsCoverAssociation, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(pager, ACGShortsClipViewsAssociation, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    };
    if (cover == nil) {
        reclip();
        return;
    }
    NSUInteger generation = ACGShortsClipGeneration;
    __weak UIScrollView *weakPager = pager;
    ACGFadeShortsCover(cover, 1.0, ^(__unused BOOL finished) {
        UIScrollView *strongPager = weakPager;
        if (strongPager == nil || generation != ACGShortsClipGeneration ||
            strongPager.isDragging || strongPager.isDecelerating) return;
        reclip();
    });
}

static void ACGScheduleShortsReclip(UIScrollView *pager, NSUInteger generation) {
    __weak UIScrollView *weakPager = pager;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIScrollView *strongPager = weakPager;
        if (strongPager == nil || generation != ACGShortsClipGeneration) return;
        if (strongPager.isDragging || strongPager.isDecelerating) {
            ACGScheduleShortsReclip(strongPager, generation);
            return;
        }
        ACGSetShortsClipping(strongPager, YES);
    });
}

static void ACGShortsSeeThrough(UIScrollView *receiver) {
    static Class pagerClass;
    static Class rootClass;
    if (pagerClass == Nil) {
        pagerClass = NSClassFromString(@"YTAsyncCollectionView");
        rootClass = NSClassFromString(@"YTReelWatchRootView");
    }
    if (pagerClass == Nil || rootClass == Nil || [receiver class] != pagerClass) return;
    if (![receiver.superview.superview isKindOfClass:rootClass]) return;
    if (!receiver.isDragging && !receiver.isDecelerating) return;
    UIView *cover = objc_getAssociatedObject(receiver, ACGShortsCoverAssociation);
    if (cover != nil && cover.layer.presentationLayer.opacity > 0.01 && cover.alpha > 0.0) {
        ACGFadeShortsCover(cover, 0.0, nil);
    }
    if (objc_getAssociatedObject(receiver, ACGShortsClipViewsAssociation) == nil) {
        ACGSetShortsClipping(receiver, NO);
        static BOOL logged;
        if (!logged) {
            logged = YES;
            NSMutableArray *names = [NSMutableArray array];
            for (UIView *view in objc_getAssociatedObject(receiver, ACGShortsClipViewsAssociation))
                [names addObject:[NSString stringWithFormat:@"%@%@", NSStringFromClass(view.class),
                                  NSStringFromCGRect([view convertRect:view.bounds toView:nil])]];
            ACGDownloadLog(@"glass", @"shorts unclip %@", [names componentsJoinedByString:@" < "]);
        }
    }
    ACGScheduleShortsReclip(receiver, ++ACGShortsClipGeneration);
}

static void ACGScrollSetContentOffset(UIScrollView *receiver, SEL selector, CGPoint offset) {
    if (OriginalScrollSetContentOffset != NULL) {
        ((void (*)(id, SEL, CGPoint))OriginalScrollSetContentOffset)(receiver, selector, offset);
    }
    ACGShortsSeeThrough(receiver);
    if (!ACGMinimizeEnabled) return;
    UIView *bar = ACGMinimizeBar;
    if (bar == nil) return;
    if (objc_getAssociatedObject(receiver, ACGMinimizePanAssociation) == nil && receiver.isTracking) {
        static ACGMinimizePanTracker *tracker;
        if (tracker == nil) tracker = [ACGMinimizePanTracker new];
        objc_setAssociatedObject(receiver, ACGMinimizePanAssociation, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [receiver.panGestureRecognizer addTarget:tracker action:@selector(pan:)];
        if (ACGMinimizeEligible(receiver, bar)) {
            ACGMinimizeActive = YES;
            ACGMinimizeScroll = receiver;
            ACGMinimizeLastOffset = receiver.contentOffset.y;
        }
        return;
    }
    if (receiver != ACGMinimizeScroll) return;
    CGFloat y = receiver.contentOffset.y;
    BOOL minimized = ACGBarMinimized(bar);
    if (y <= -receiver.adjustedContentInset.top + 0.5) {
        ACGMinimizeLastOffset = y;
        if (minimized) ACGSetBarMinimized(bar, NO);
        else if (ACGMinimizeProgress > 0.0) ACGApplyMinimizeProgress(bar, 0.0, receiver.isTracking);
        return;
    }
    if (!ACGMinimizeActive || !receiver.isTracking) return;
    CGFloat delta = y - ACGMinimizeLastOffset;
    ACGMinimizeLastOffset = y;
    if (fabs(delta) < 0.01) return;
    CGFloat progress = ACGMinimizeProgress + delta / ACGMinimizeDistance;
    progress = MAX(minimized ? 0.01 : 0.0, MIN(1.0, progress));
    if (!minimized && progress >= 1.0) {
        ACGMinimizeActive = NO;
        ACGSetBarMinimized(bar, YES);
        return;
    }
    ACGApplyMinimizeProgress(bar, progress, YES);
}

static IMP OriginalHidePivotBarOnScroll;
static IMP OriginalUpdatePivotBarVisibility;

static BOOL ACGHidePivotBarOnScroll(id receiver, SEL selector) {
    if (ACGMinimizeEnabled) return NO;
    return OriginalHidePivotBarOnScroll != NULL &&
        ((BOOL (*)(id, SEL))OriginalHidePivotBarOnScroll)(receiver, selector);
}

static void ACGUpdatePivotBarVisibility(id receiver, SEL selector, UIScrollView *scrollView,
                                           CGFloat offsetY, BOOL atBottom) {
    if (ACGMinimizeEnabled) return;
    if (OriginalUpdatePivotBarVisibility != NULL) {
        ((void (*)(id, SEL, id, CGFloat, BOOL))OriginalUpdatePivotBarVisibility)(
            receiver, selector, scrollView, offsetY, atBottom);
    }
}

static const void *ACGShortsBackdropAssociation = &ACGShortsBackdropAssociation;
static NSString *gACGShortsDockDiag;   // nền và kiểu giao diện của dock lần gần nhất ở tab Short (dòng [Dock Short] trong Chẩn đoán)

// Ở tab Short: nền của khung chứa thanh tab (host) để TRONG SUỐT thay vì trắng/đen, trả lại nền cũ khi rời tab
static void ACGApplyShortsBackdrop(UIView *bar, BOOL shorts) {
    UIView *host = bar.superview;
    if (host == nil) return;
    id saved = objc_getAssociatedObject(host, ACGShortsBackdropAssociation);
    if (shorts) {
        if (saved == nil) {
            objc_setAssociatedObject(host, ACGShortsBackdropAssociation, host.backgroundColor ?: (id)NSNull.null,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        host.backgroundColor = UIColor.clearColor;
    } else if (saved != nil) {
        host.backgroundColor = saved == NSNull.null ? nil : saved;
        objc_setAssociatedObject(host, ACGShortsBackdropAssociation, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Video Short kéo xuống tận thanh tab: trang Short YouTube dừng ngay trên thanh tab nên bên dưới còn một dải (trắng khi sáng, đen khi tối).
// Kéo dài khung của lớp gốc Short và đường từ danh sách cuộn tới lớp gốc thêm đúng bằng dải đó; lớp nút bên cạnh không bị đụng tới.
static BOOL gACGShortsTabSelected = NO;
static __weak UIView *gACGReelRoot = nil;
static NSHashTable<UIView *> *gACGExtendedViews;
static NSString *gACGShortsExtendDiag;
static const void *ACGExtendedHeightAssociation = &ACGExtendedHeightAssociation;
static const void *ACGExtendedGapAssociation = &ACGExtendedGapAssociation;

static void ACGRestoreShortsExtension(void) {
    for (UIView *view in gACGExtendedViews.allObjects) {
        NSNumber *height = objc_getAssociatedObject(view, ACGExtendedHeightAssociation);
        NSNumber *gap = objc_getAssociatedObject(view, ACGExtendedGapAssociation);
        objc_setAssociatedObject(view, ACGExtendedHeightAssociation, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, ACGExtendedGapAssociation, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (height && gap && fabs(CGRectGetHeight(view.frame) - height.doubleValue) < 0.5) {   // YouTube đã tự đặt lại khung thì không trừ nữa
            CGRect frame = view.frame;
            frame.size.height -= gap.doubleValue;
            view.frame = frame;
        }
    }
    [gACGExtendedViews removeAllObjects];
}

static UIView *ACGFindPager(UIView *view, int depth) {
    if ([view isKindOfClass:NSClassFromString(@"YTAsyncCollectionView")]) return view;
    if (depth <= 0) return nil;
    for (UIView *sub in view.subviews) {
        UIView *found = ACGFindPager(sub, depth - 1);
        if (found) return found;
    }
    return nil;
}

static void ACGExtendShortsRoot(UIView *root) {
    if (!root || !gACGShortsTabSelected || ![kPrefs boolForKey:kShortsFullBleedKey]) return;
    UIWindow *window = root.window;
    if (!window) return;
    CGFloat windowHeight = CGRectGetHeight(window.bounds);
    CGRect rect = [root convertRect:root.bounds toView:nil];
    CGFloat gap = windowHeight - CGRectGetMaxY(rect);
    if (gap < 0.5 || gap > 160.0) return;   // đã tới đáy rồi, hoặc khung lạ: không đụng
    UIView *pager = ACGFindPager(root, 3);
    NSMutableArray<UIView *> *chain = [NSMutableArray array];
    UIView *appView = nil;
    for (UIView *view = root; view != nil && view != window && chain.count < 6; view = view.superview) {   // từ lớp gốc lên trên
        if ([view isKindOfClass:NSClassFromString(@"YTAppView")]) { appView = view; break; }
        CGRect r = [view convertRect:view.bounds toView:nil];
        if (fabs(CGRectGetMaxY(r) - CGRectGetMaxY(rect)) > 1.5) break;
        [chain addObject:view];
    }
    for (UIView *view = pager; view != nil && view != root; view = view.superview) {   // từ danh sách cuộn lên tới lớp gốc
        CGRect r = [view convertRect:view.bounds toView:nil];
        if (fabs(CGRectGetMaxY(r) - CGRectGetMaxY(rect)) > 1.5) break;
        if (![chain containsObject:view]) [chain addObject:view];
    }
    if (!gACGExtendedViews) gACGExtendedViews = [NSHashTable weakObjectsHashTable];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UIView *view in chain) {
        CGRect frame = view.frame;
        frame.size.height += gap;
        view.frame = frame;
        objc_setAssociatedObject(view, ACGExtendedHeightAssociation, @(CGRectGetHeight(frame)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, ACGExtendedGapAssociation, @(gap), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gACGExtendedViews addObject:view];
        [names addObject:NSStringFromClass(view.class)];
    }
    gACGShortsExtendDiag = [NSString stringWithFormat:@"+%.0fpt cho %lu lớp: %@ · danh sách %@ · cửa sổ cao %.0f",
        gap, (unsigned long)chain.count, [names componentsJoinedByString:@" < "], pager ? @"có" : @"không thấy", windowHeight];
    (void)appView;
}

static BOOL ACGApplyPivotBarGlass(UIView *receiver, UIView *blur) {
    UIVisualEffectView *glass = objc_getAssociatedObject(receiver, ACGPivotBarGlassAssociation);
    BOOL wanted = ACGTabBarOwnGlass() &&
        ACGLiquidGlassAvailable();
    if (!wanted) {
        if (glass != nil) {
            [glass removeFromSuperview];
            [(UIView *)objc_getAssociatedObject(receiver, ACGPivotBarPillAssociation) removeFromSuperview];
            [(UIView *)objc_getAssociatedObject(receiver, ACGPivotBarLensAssociation) removeFromSuperview];
            objc_setAssociatedObject(receiver, ACGPivotBarLensAssociation, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(receiver, ACGPivotBarPillAssociation, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(receiver, ACGPivotBarGlassAssociation, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            blur.hidden = NO;
            for (UIView *view in ACGPivotFadedViews(receiver).allObjects) view.alpha = 1.0;
            [ACGPivotFadedViews(receiver) removeAllObjects];
        }
        return NO;
    }
    if (glass == nil) {
        glass = [[UIVisualEffectView alloc] initWithEffect:ACGMakeGlassEffect(NO)];
        glass.userInteractionEnabled = NO;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.clipsToBounds = NO;
        objc_setAssociatedObject(receiver, ACGPivotBarGlassAssociation, glass,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    blur.hidden = YES;
    NSHashTable<UIView *> *faded = ACGPivotFadedViews(receiver);
    UIView *ownPill = objc_getAssociatedObject(receiver, ACGPivotBarPillAssociation);
    UIView *ownLens = objc_getAssociatedObject(receiver, ACGPivotBarLensAssociation);
    for (UIView *sibling in receiver.subviews) {
        if (sibling == glass || sibling == ownPill || sibling == ownLens) continue;
        if (ACGViewContainsPivotItem(sibling)) {
            sibling.opaque = NO;
            sibling.backgroundColor = UIColor.clearColor;
        } else if (sibling.alpha > 0.0 && !ACGViewLooksLikeScrubber(sibling, 3) &&
                   (CGRectGetHeight(sibling.frame) >= CGRectGetHeight(receiver.bounds) * 0.6 ||
                    CGRectGetHeight(sibling.frame) <= 1.5)) {
            sibling.alpha = 0.0;
            [faded addObject:sibling];
        }
    }
    receiver.backgroundColor = UIColor.clearColor;
    receiver.layer.backgroundColor = UIColor.clearColor.CGColor;
    receiver.opaque = NO;
    if (glass.superview != receiver) {
        [glass removeFromSuperview];
        [receiver insertSubview:glass atIndex:0];
    } else {
        [receiver sendSubviewToBack:glass];
    }
    CGFloat itemHeight = CGRectGetHeight(receiver.bounds) - receiver.safeAreaInsets.bottom;
    CGFloat extra = 7.0;
    CGFloat glassHeight = MAX(itemHeight, 44.0) + extra * 2.0;
    CGFloat glassTop = MIN(0.0, CGRectGetHeight(receiver.bounds) - glassHeight - 4.0);
    BOOL expanded = [objc_getAssociatedObject(receiver, ACGPivotBarExpandedAssociation) boolValue];
    NSUInteger tabs = 0;
    for (UIView *item in ACGSortedPivotItems(receiver)) {
        if (!item.hidden && CGRectGetWidth(item.bounds) > 0.0) tabs += 1;
    }
    CGFloat barWidth = CGRectGetWidth(receiver.bounds);
    CGFloat margin = expanded ? 14.0 : 21.0;
    CGFloat glassWidth = barWidth - margin * 2.0;
    CGRect screen = (receiver.window.screen ?: UIScreen.mainScreen).bounds;
    CGFloat shortSide = MIN(CGRectGetWidth(screen), CGRectGetHeight(screen));
    if (shortSide > 0.0) glassWidth = MIN(glassWidth, shortSide - margin * 2.0);
    if (tabs > 0 && tabs <= 4) {
        glassWidth = MIN(glassWidth, 86.0 * (CGFloat)tabs + 16.0);
    }
    CGRect frame = CGRectMake((barWidth - glassWidth) * 0.5, glassTop, glassWidth, glassHeight);
    UIView *current = ACGSelectedPivotItem(receiver);
    BOOL onShorts = current != nil && [ACGPivotItemIdentifier(current) isEqualToString:@"FEshorts"];
    ACGMinimizeEnabled = ACGFeatureEnabled(ACGMinimizeKey);
    ACGMinimizeBar = receiver;
    BOOL minimized = ACGBarMinimized(receiver);
    if (minimized && (!ACGMinimizeEnabled || onShorts || current == nil)) {
        objc_setAssociatedObject(receiver, ACGPivotBarMinimizedAssociation, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        minimized = NO;
        ACGApplyMiniAlpha(receiver, NO);
        ACGRestoreMiniIcon(receiver);
        ACGRemoveMiniMask(receiver);
    }
    if (!ACGMinimizeEnabled || onShorts) {
        ACGMinimizeProgress = 0.0;
        ACGSetBarScale(receiver, 1.0, 0.0, 1.0);
    }
    CGRect fullFrame = frame;
    CGFloat circle = MIN(48.0, glassHeight);
    if (minimized) {
        frame = CGRectMake(28.0, CGRectGetMidY(frame) - circle * 0.5, circle, circle);
    }
    receiver.clipsToBounds = NO;
    receiver.layer.masksToBounds = NO;
    glass.frame = frame;
    glass.layer.cornerRadius = CGRectGetHeight(frame) * 0.5;
    ACGUpdateMiniMask(receiver, frame);
    gACGShortsTabSelected = onShorts;
    BOOL fullBleed = onShorts && [kPrefs boolForKey:kShortsFullBleedKey];
    ACGApplyShortsBackdrop(receiver, fullBleed);   // dock Short trong suốt (không trắng/đen); rời tab thì trả lại nền cũ
    if (fullBleed) ACGExtendShortsRoot(gACGReelRoot);
    else if (gACGExtendedViews.count) ACGRestoreShortsExtension();
    if (onShorts) {
        UIView *host = receiver.superview;
        CGFloat hr = 0, hg = 0, hb = 0, ha = 0;
        [host.backgroundColor getRed:&hr green:&hg blue:&hb alpha:&ha];
        gACGShortsDockDiag = [NSString stringWithFormat:@"nền %@ rgba(%.2f,%.2f,%.2f,%.2f) · giao diện thanh %ld · cửa sổ %ld",
            host ? NSStringFromClass(host.class) : @"-", hr, hg, hb, ha,
            (long)receiver.traitCollection.userInterfaceStyle, (long)receiver.window.traitCollection.userInterfaceStyle];
    }
    UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;   // dock đồng bộ với các tab khác
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleUnspecified) {
        glass.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    }
    if (!ACGStencilRendering && current != nil && receiver.overrideUserInterfaceStyle != style) {
        receiver.overrideUserInterfaceStyle = style;
        for (UIView *item in ACGSortedPivotItems(receiver)) ACGApplyPivotItemPresentation(item);
        ACGRecolorExtraTabs(receiver);
    }
    glass.alpha = 1.0;
    ACGLayoutItemsInGlass(receiver, fullFrame);
    UIImageView *miniIcon = objc_getAssociatedObject(receiver, ACGPivotBarMiniIconAssociation);
    if (miniIcon != nil && !miniIcon.hidden && current != nil) {
        miniIcon.center = minimized ? CGPointMake(CGRectGetWidth(frame) * 0.5, CGRectGetHeight(frame) * 0.5)
                                    : ACGMiniIconHome(receiver, glass, current);
    }
    if (!minimized) ACGUpdateGlassPill(receiver, glass);
    ACGInstallGlassSlide(receiver);
    return YES;
}

static IMP OriginalSearchOptOutFrostedPivot;

static BOOL ACGSearchOptOutFrostedPivot(__unused id receiver, __unused SEL selector) {
    return NO;
}

NSInteger ACGFrostedTabBarMode(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:@"ACG.Preference.Tabs.Frosted"];
    if ([stored respondsToSelector:@selector(integerValue)]) return MAX(0, MIN(2, [stored integerValue]));
    return ACGFeatureEnabled(@"ACG.Preference.Tabs.FrostedHidden") ? 2 : 0;
}

static IMP OriginalFrostedPermitted;

static BOOL ACGFrostedPermitted(id receiver, SEL selector) {
    NSInteger mode = ACGMasterEnabled() ? ACGFrostedTabBarMode() : 0;
    if (ACGLiquidGlassAvailable() && ACGTabBarOwnGlass()) return YES;
    if (mode == 1) return YES;
    if (mode == 2) return NO;
    return OriginalFrostedPermitted != NULL && ((BOOL (*)(id, SEL))OriginalFrostedPermitted)(receiver, selector);
}

static NSString *ACGColorText(UIColor *color) {
    if (color == nil) return @"nil";
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) return @"?";
    return [NSString stringWithFormat:@"%.2f,%.2f,%.2f,%.2f", red, green, blue, alpha];
}

static NSString *ACGPivotItemColors(UIView *item) {
    if (item == nil) return @"-";
    UIImageView *icon = ACGFindImageView(item);
    UILabel *label = ACGFindNativeLabel(item);
    return [NSString stringWithFormat:@"%@ icon=%@ label=%@", ACGPivotItemIdentifier(item) ?: @"?",
            ACGColorText(icon.tintColor), ACGColorText(label.textColor)];
}

static void ACGLogPivotState(UIView *receiver) {
    if (receiver.window == nil || !ACGDebugLogsEnabled()) return;
    UIView *selected = ACGSelectedPivotItem(receiver);
    UIView *other = nil;
    for (UIView *item in ACGSortedPivotItems(receiver)) {
        if (item != selected && !item.hidden) {
            other = item;
            break;
        }
    }
    UIVisualEffectView *glass = objc_getAssociatedObject(receiver, ACGPivotBarGlassAssociation);
    NSString *selectedID = ACGPivotItemIdentifier(selected);
    NSString *state = [NSString stringWithFormat:
        @"tab=%@ shorts=%d glass=%d glassFrame=%@ minimized=%d alpha=%.2f hidden=%d bg=%@ style=%ld trait=%ld "
        @"backdrop=%@ pill=%@ selected[%@] other[%@]",
        selectedID ?: @"none", [selectedID isEqualToString:@"FEshorts"], glass.superview == receiver,
        glass.superview == receiver ? NSStringFromCGRect(glass.frame) : @"-", ACGBarMinimized(receiver),
        receiver.alpha, receiver.hidden, ACGColorText(receiver.backgroundColor),
        (long)receiver.overrideUserInterfaceStyle, (long)receiver.traitCollection.userInterfaceStyle,
        ACGColorText(receiver.superview.backgroundColor), ACGColorText(ACGPillColor()),
        ACGPivotItemColors(selected), ACGPivotItemColors(other)];
    static NSString *lastState;
    if ([state isEqualToString:lastState]) return;
    lastState = state;
    ACGDebugLog(@"tabbar", @"%@", state);
}

static void ACGApplyPivotBarBackgroundInner(UIView *receiver);

static void ACGApplyPivotBarBackground(UIView *receiver) {
    ACGApplyPivotBarBackgroundInner(receiver);
    ACGLogPivotState(receiver);
}

static void ACGApplyPivotBarBackgroundInner(UIView *receiver) {
    if (ACGRefreshTabTint()) {
        for (UIView *item in ACGSortedPivotItems(receiver)) {
            ACGRestyleSelectedTab(item);
            ACGApplyPivotItemPresentation(item);
        }
    }
    SEL blurSelector = NSSelectorFromString(@"blurView");
    UIView *blur = [receiver respondsToSelector:blurSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(receiver, blurSelector)
        : nil;
    if (ACGApplyPivotBarGlass(receiver, blur)) return;
    BOOL applied = [objc_getAssociatedObject(
        receiver, ACGPivotBarSolidAssociation) boolValue];
    if (!ACGMasterEnabled() || ACGFrostedTabBarMode() != 2) {
        if (!applied) return;
        blur.hidden = NO;
        receiver.backgroundColor = UIColor.clearColor;
        receiver.opaque = NO;
        objc_setAssociatedObject(receiver, ACGPivotBarSolidAssociation,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    UIUserInterfaceStyle style = receiver.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) {
        style = receiver.window.traitCollection.userInterfaceStyle;
    }
    UIColor *solid = style == UIUserInterfaceStyleDark
        ? UIColor.blackColor
        : UIColor.whiteColor;
    blur.hidden = YES;
    for (UIView *sibling in receiver.subviews) {
        if (sibling != blur && [sibling isKindOfClass:UIVisualEffectView.class]) {
            sibling.hidden = YES;
        }
    }
    receiver.backgroundColor = solid;
    receiver.opaque = YES;
    objc_setAssociatedObject(receiver, ACGPivotBarSolidAssociation,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ACGRefreshPivotBarsInView(UIView *view) {
    if ([NSStringFromClass(view.class) isEqualToString:@"YTPivotBarView"]) {
        ACGApplyPivotBarBackground(view);
        return;
    }
    for (UIView *subview in view.subviews) {
        ACGRefreshPivotBarsInView(subview);
    }
}

void ACGRefreshPivotBarBackground(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.hidden) ACGRefreshPivotBarsInView(window);
        }
    }
}

static void ACGPivotBarStyleColors(UIView *receiver, SEL selector) {
    if (OriginalPivotBarStyleColors != NULL) {
        ((void (*)(id, SEL))OriginalPivotBarStyleColors)(receiver, selector);
    }
    ACGApplyPivotBarBackground(receiver);
}

static void ACGPivotBarSetBackgroundStyle(UIView *receiver, SEL selector,
                                             int style) {
    if (OriginalPivotBarSetBackgroundStyle != NULL) {
        ((void (*)(id, SEL, int))OriginalPivotBarSetBackgroundStyle)(
            receiver, selector, style);
    }
    ACGApplyPivotBarBackground(receiver);
}

static NSString *ACGStartupTabToken(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id stored = [defaults objectForKey:@"ACG.Preference.Tabs.Startup"];
    if ([stored isKindOfClass:NSString.class]) return stored;
    NSArray<NSString *> *legacy = @[@"", @"explore", @"subscriptions",
                                    @"shorts", @"library"];
    NSInteger index = [stored respondsToSelector:@selector(integerValue)]
        ? [stored integerValue] : 0;
    NSString *token = (index > 0 && index < (NSInteger)legacy.count)
        ? legacy[(NSUInteger)index] : @"";
    [defaults setObject:token forKey:@"ACG.Preference.Tabs.Startup"];
    return token;
}

static NSString *ACGStartupPivotIdentifier(NSString *token) {
    if (token.length == 0) return nil;
    NSDictionary<NSString *, NSString *> *known = @{
        @"home": @"FEwhat_to_watch",
        @"explore": @"FEexplore",
        @"subscriptions": @"FEsubscriptions",
        @"shorts": @"FEshorts",
        @"library": @"FElibrary",
        @"you": @"FElibrary"
    };
    NSString *identifier = known[token];
    if (identifier.length != 0) return identifier;
    return ACGStartupIdentifiers[token];
}

static NSString *ACGWantedStartupPivot(void) {
    NSString *identifier = ACGStartupPivotIdentifier(ACGStartupTabToken());
    if (identifier.length != 0) return identifier;
    if (ACGMasterEnabled() &&
        [NSUserDefaults.standardUserDefaults boolForKey:@"ACG.Preference.Tabs.Hidden.Home"] &&
        ACGFirstVisiblePivot.length != 0 && ![ACGFirstVisiblePivot isEqualToString:@"FEwhat_to_watch"]) {
        return ACGFirstVisiblePivot;
    }
    return nil;
}

static __weak id ACGPivotBarControllerRef;

static id ACGPivotControllerForView(UIView *view) {
    if (ACGPivotBarControllerRef != nil) return ACGPivotBarControllerRef;
    SEL lookup = NSSelectorFromString(@"pivotBarItemForIdentifier:");
    UIResponder *responder = view;
    while (responder != nil) {
        if ([responder respondsToSelector:lookup]) {
            ACGPivotBarControllerRef = responder;
            return responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

static BOOL ACGNavigateToPivot(id controller, NSString *identifier) {
    if (controller == nil || identifier.length == 0) return NO;
    SEL lookup = NSSelectorFromString(@"pivotBarItemForIdentifier:");
    SEL tap = NSSelectorFromString(@"didTapItemWithRenderer:");
    if (![controller respondsToSelector:lookup] ||
        ![controller respondsToSelector:tap]) {
        return NO;
    }
    id item = ((id (*)(id, SEL, id))objc_msgSend)(controller, lookup, identifier);
    if (item == nil) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(controller, tap, item);
    return YES;
}

static void ACGApplyStartupTab(UIView *receiver) {
    if (ACGStartupApplied) return;
    NSString *identifier = ACGWantedStartupPivot();
    if (identifier.length == 0) {
        if (ACGFirstVisiblePivot.length != 0) ACGStartupApplied = YES;
        return;
    }
    static NSTimeInterval firstSeen = 0.0;
    const NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (firstSeen == 0.0) firstSeen = now;
    if (now - firstSeen > 8.0) {
        ACGStartupApplied = YES;
        return;
    }

    id controller = ACGPivotControllerForView(receiver);

    id target = controller ?: receiver;
    SEL current = NSSelectorFromString(@"selectedPivotIdentifier");
    if ([target respondsToSelector:current]) {
        id selected = ((id (*)(id, SEL))objc_msgSend)(target, current);
        if ([selected isKindOfClass:NSString.class] &&
            [selected caseInsensitiveCompare:identifier] == NSOrderedSame &&
            [NSUserDefaults.standardUserDefaults boolForKey:@"ACG.Preference.Tabs.Hidden.Home"]) {
            SEL selectItem = NSSelectorFromString(@"selectItemWithPivotIdentifier:");
            SEL setSelected = NSSelectorFromString(@"setSelectedPivotIdentifier:");
            if ([controller respondsToSelector:selectItem])
                ((void (*)(id, SEL, id))objc_msgSend)(controller, selectItem, @"FEwhat_to_watch");
            if ([controller respondsToSelector:setSelected])
                ((void (*)(id, SEL, id))objc_msgSend)(controller, setSelected, @"FEwhat_to_watch");
            @try {
                [controller setValue:@"FEwhat_to_watch" forKey:@"_pivotIdentifier"];
            } @catch (__unused NSException *exception) {
            }
            ACGNavigateToPivot(controller, identifier);
            ACGStartupApplied = YES;
            return;
        }
        if ([selected isKindOfClass:NSString.class] &&
            [selected caseInsensitiveCompare:identifier] == NSOrderedSame) {
            ACGStartupApplied = YES;
            return;
        }
    }

    if (ACGNavigateToPivot(controller, identifier)) return;

    SEL select = NSSelectorFromString(@"selectItemWithPivotIdentifier:");
    if ([target respondsToSelector:select]) {
        ((void (*)(id, SEL, id))objc_msgSend)(target, select, identifier);
    }
}

static void ACGSetDefaultSelectedPivot(id receiver, SEL selector, id identifier) {
    NSString *wanted = ACGStartupPivotIdentifier(ACGStartupTabToken());
    if (wanted.length != 0 && !ACGStartupApplied) {
        ACGStartupNative = YES;
        identifier = wanted;
    }
    if (OriginalSetDefaultSelectedPivot != NULL) {
        ((void (*)(id, SEL, id))OriginalSetDefaultSelectedPivot)(receiver, selector,
                                                                identifier);
    }
}

static void ACGScheduleStartupTab(id controller) {
    if (ACGStartupApplied) return;
    if (ACGWantedStartupPivot().length == 0 && ACGFirstVisiblePivot.length != 0) {
        ACGStartupApplied = YES;
        return;
    }
    static BOOL scheduled = NO;
    if (scheduled) return;
    scheduled = YES;
    const double delay = ACGStartupNative ? 0.0 : 0.35;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        scheduled = NO;
        SEL pivotView = NSSelectorFromString(@"pivotBarView");
        UIView *view = [controller respondsToSelector:pivotView]
            ? ((id (*)(id, SEL))objc_msgSend)(controller, pivotView)
            : nil;
        ACGApplyStartupTab(view);
        if (!ACGStartupApplied) ACGScheduleStartupTab(controller);
    });
}

static void ACGPivotControllerAppear(id receiver, SEL selector, BOOL animated) {
    if (OriginalPivotControllerAppear != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalPivotControllerAppear)(receiver, selector,
                                                                animated);
    }
    ACGPivotBarControllerRef = receiver;
    ACGScheduleStartupTab(receiver);
}

static void ACGPivotBarLayout(UIView *receiver, SEL selector) {
    if (OriginalPivotBarLayout != NULL) {
        ((void (*)(id, SEL))OriginalPivotBarLayout)(receiver, selector);
    }
    ACGHideCreateViews(receiver);
    ACGApplyPivotBarBackground(receiver);
}

static void ACGPivotItemLayout(UIView *receiver, SEL selector) {
    if (OriginalPivotItemLayout != NULL) {
        ((void (*)(id, SEL))OriginalPivotItemLayout)(receiver, selector);
    }
    ACGApplyPivotItemPresentation(receiver);
}

static void ACGPivotItemSetSelected(UIView *receiver,
                                       SEL selector,
                                       BOOL selected) {
    BOOL wasSelected = [objc_getAssociatedObject(receiver, ACGTabSelectedAssociation) boolValue];
    if (selected && !wasSelected) {
        // Đổi tab: chốt phạm vi lọc danh sách ngay, không chờ lần quét 0,5 giây. YouTube nạp phần tử của tab mới ngay khi bấm;
        // nếu cờ còn là "Trang chủ" thì hàng Short/bài đăng của tab Đăng ký bị bỏ và để lại ô trống.
        NSString *picked = ACGPivotItemIdentifier(receiver);
        gListTabIdent = picked;
        gListFilterAllowed = [picked isEqualToString:@"FEwhat_to_watch"];
        gListScopeLockUntil = CACurrentMediaTime() + 0.8;
    }
    if (OriginalPivotItemSetSelected != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalPivotItemSetSelected)(
            receiver, selector, selected
        );
    }
    objc_setAssociatedObject(receiver,
                             ACGTabSelectedAssociation,
                             @(selected),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ACGApplyPivotItemPresentation(receiver);
    if (ACGStencilRendering) return;
    if (selected && !wasSelected) ACGRecolorExtraTabs(receiver);
    if (selected) {
        UIView *bar = receiver.superview;
        while (bar != nil && ![NSStringFromClass(bar.class) isEqualToString:@"YTPivotBarView"]) {
            bar = bar.superview;
        }
        if (!wasSelected) ACGSetBarMinimized(bar, NO);
        [bar setNeedsLayout];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        ACGApplyPivotItemPresentation(receiver);
    });
}

static void ACGPivotItemTraitChanged(UIView *receiver,
                                        SEL selector,
                                        UITraitCollection *previous) {
    if (OriginalPivotItemTraitChanged != NULL) {
        ((void (*)(id, SEL, id))OriginalPivotItemTraitChanged)(
            receiver, selector, previous
        );
    }
    ACGApplyPivotItemPresentation(receiver);
    dispatch_async(dispatch_get_main_queue(), ^{
        ACGApplyPivotItemPresentation(receiver);
    });
    ACGRecolorExtraTabs(receiver);
}

void ACGInstallTabBarHooks(void) {
    gACGTabHooked = YES;
    static dispatch_once_t tabObserverOnce;
    dispatch_once(&tabObserverOnce, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:ACGTabConfigChangedNote object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ACGReapplyTabConfig();
                ACGRefreshPivotBarBackground();
            });
        }];
    });
    ACGRefreshTabTint();
    ACGInstallInstanceHook(@"YTPivotBarItemView",
                              @"iconTintColorSelected",
                              (IMP)ACGIconTintSelected,
                              &OriginalIconTintSelected);
    ACGInstallInstanceHook(@"UILabel",
                              @"setTextColor:",
                              (IMP)ACGPivotLabelSetTextColor,
                              &OriginalPivotLabelSetTextColor);
    ACGInstallInstanceHook(@"UILabel",
                              @"setHidden:",
                              (IMP)ACGPivotLabelSetHidden,
                              &OriginalPivotLabelSetHidden);
    ACGInstallInstanceHook(@"UILabel",
                              @"setAlpha:",
                              (IMP)ACGPivotLabelSetAlpha,
                              &OriginalPivotLabelSetAlpha);
    ACGInstallInstanceHook(@"YTQTMButton",
                              @"layoutSubviews",
                              (IMP)ACGPivotButtonLayout,
                              &OriginalPivotButtonLayout);
    ACGInstallInstanceHook(@"YTPivotBarView",
                              @"setRenderer:",
                              (IMP)ACGSetPivotRenderer,
                              &OriginalSetPivotRenderer);
    Method floatingSetter = class_getInstanceMethod(NSClassFromString(@"YTFloatingPivotBarView"),
                                                    @selector(setRenderer:));
    const char *floatingTypes = floatingSetter != NULL ? method_getTypeEncoding(floatingSetter) : NULL;
    BOOL floatingHooked = floatingTypes != NULL && strncmp(floatingTypes, "v24@0:8@16", 10) == 0 &&
        ACGInstallInstanceHook(@"YTFloatingPivotBarView", @"setRenderer:",
                                  (IMP)ACGSetPivotRenderer, &OriginalSetFloatingPivotRenderer);
    ACGDownloadLog(@"tabbar", @"floating bar hook=%d types=%s", floatingHooked, floatingTypes ?: "-");
    ACGInstallInstanceHook(@"YTPivotBarItemView",
                              @"layoutSubviews",
                              (IMP)ACGPivotItemLayout,
                              &OriginalPivotItemLayout);
    ACGInstallInstanceHook(@"YTPivotBarItemView",
                              @"setSelected:",
                              (IMP)ACGPivotItemSetSelected,
                              &OriginalPivotItemSetSelected);
    ACGInstallInstanceHook(@"YTPivotBarItemView",
                              @"traitCollectionDidChange:",
                              (IMP)ACGPivotItemTraitChanged,
                              &OriginalPivotItemTraitChanged);
    ACGInstallInstanceHook(@"YTPivotBarView",
                              @"layoutSubviews",
                              (IMP)ACGPivotBarLayout,
                              &OriginalPivotBarLayout);
    ACGInstallInstanceHook(@"YTPivotBarView",
                              @"pointInside:withEvent:",
                              (IMP)ACGPivotBarPointInside,
                              &OriginalPivotBarPointInside);
    if (ACGTabBarOwnGlass() && ACGLiquidGlassAvailable()) {
        ACGInstallInstanceHook(@"UIScrollView",
                                  @"setContentOffset:",
                                  (IMP)ACGScrollSetContentOffset,
                                  &OriginalScrollSetContentOffset);
        ACGInstallInstanceHook(@"YTScrollableNavigationController",
                                  @"hidePivotBarOnScroll",
                                  (IMP)ACGHidePivotBarOnScroll,
                                  &OriginalHidePivotBarOnScroll);
        ACGInstallInstanceHook(@"YTScrollableNavigationController",
                                  @"updatePivotBarVisibilityForScrollView:contentOffsetY:isAtBottom:",
                                  (IMP)ACGUpdatePivotBarVisibility,
                                  &OriginalUpdatePivotBarVisibility);
        ACGInstallInstanceHook(@"YTSearchResultsViewController",
                                  @"optOutOfFrostedPivotBar",
                                  (IMP)ACGSearchOptOutFrostedPivot,
                                  &OriginalSearchOptOutFrostedPivot);
    }
    ACGInstallInstanceHook(@"YTPivotBarViewController",
                              @"isFrostedPivotBarPermitted",
                              (IMP)ACGFrostedPermitted,
                              &OriginalFrostedPermitted);
    ACGInstallInstanceHook(@"YTPivotBarView",
                              @"hitTest:withEvent:",
                              (IMP)ACGPivotBarHitTest,
                              &OriginalPivotBarHitTest);
    ACGInstallInstanceHook(@"YTPivotBarViewController",
                              @"viewDidAppear:",
                              (IMP)ACGPivotControllerAppear,
                              &OriginalPivotControllerAppear);
    ACGInstallInstanceHook(@"YTAppPivotBarController",
                              @"setDefaultSelectedPivotIdentifier:",
                              (IMP)ACGSetDefaultSelectedPivot,
                              &OriginalSetDefaultSelectedPivot);
    ACGInstallInstanceHook(@"YTPivotBarView",
                              @"styleBackgroundColors",
                              (IMP)ACGPivotBarStyleColors,
                              &OriginalPivotBarStyleColors);
    ACGInstallInstanceHook(@"YTPivotBarView",
                              @"setBackgroundStyle:",
                              (IMP)ACGPivotBarSetBackgroundStyle,
                              &OriginalPivotBarSetBackgroundStyle);
}


#pragma mark - Bảng "Thanh tab" (theo YTKACETabEditorController)

static const void *ACGTabSwitchKey = &ACGTabSwitchKey;

static void ACGStartupDestinations(NSArray<NSString *> **outTitles, NSArray<NSString *> **outValues) {
    NSArray<NSArray<NSString *> *> *destinations = @[
        @[@"", AutoACT(@"Mặc định"), @""],
        @[@"home", AutoACT(@"Trang chủ"), @"ACG.Preference.Tabs.Hidden.Home"],
        @[@"explore", AutoACT(@"Khám phá"), @""],
        @[@"subscriptions", AutoACT(@"Kênh đăng ký"), @"ACG.Preference.Tabs.Hidden.Subscriptions"],
        @[@"shorts", @"Shorts", @"ACG.Preference.Tabs.Hidden.Shorts"],
        @[@"library", AutoACT(@"Bạn"), @"ACG.Preference.Tabs.Hidden.Library"],
        @[@"create", AutoACT(@"Tạo"), @"ACG.Preference.Tabs.Hidden.Create"],
        @[@"music", AutoACT(@"Nhạc"), @"ACG.Preference.Tabs.Hidden.Music"],
        @[@"live", AutoACT(@"Trực tiếp"), @"ACG.Preference.Tabs.Hidden.Live"],
        @[@"gaming", AutoACT(@"Trò chơi"), @"ACG.Preference.Tabs.Hidden.Gaming"],
        @[@"news", AutoACT(@"Tin tức"), @"ACG.Preference.Tabs.Hidden.News"],
        @[@"posts", AutoACT(@"Bài đăng"), @"ACG.Preference.Tabs.Hidden.Posts"],
        @[@"sports", AutoACT(@"Thể thao"), @"ACG.Preference.Tabs.Hidden.Sports"],
        @[@"learning", AutoACT(@"Học tập"), @"ACG.Preference.Tabs.Hidden.Learning"],
        @[@"fashion", AutoACT(@"Thời trang"), @"ACG.Preference.Tabs.Hidden.Fashion"],
        @[@"playlists", @"Playlist", @"ACG.Preference.Tabs.Hidden.Playlists"],
        @[@"history", AutoACT(@"Lịch sử"), @"ACG.Preference.Tabs.Hidden.History"],
        @[@"notifications", AutoACT(@"Thông báo"), @"ACG.Preference.Tabs.Hidden.Notifs"],
        @[@"watchlater", AutoACT(@"Xem sau"), @"ACG.Preference.Tabs.Hidden.WatchLater"]
    ];
    NSString *selected = [kPrefs stringForKey:@"ACG.Preference.Tabs.Startup"];
    NSArray<NSString *> *known = [kPrefs arrayForKey:@"ACG.Preference.Tabs.Known"];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSArray<NSString *> *entry in destinations) {
        NSString *token = entry[0];
        NSString *hideKey = entry[2];
        BOOL hidden = hideKey.length != 0 && [kPrefs boolForKey:hideKey];
        NSString *canonical = [token isEqualToString:@"library"] ? @"you" : token;
        if (token.length != 0 && known.count != 0 && ![known containsObject:canonical] && ![token isEqualToString:selected]) continue;
        if (hidden && ![token isEqualToString:selected]) continue;
        [titles addObject:entry[1]];
        [values addObject:token];
    }
    if (outTitles) *outTitles = titles;
    if (outValues) *outValues = values;
}

static NSUInteger ACGTintIndex(void) {
    NSInteger mode = [ACGPreferenceObject(@"ACG.Preference.Tabs.SelectedTint") integerValue];
    return (NSUInteger)MAX(0, MIN(2, mode));
}
static NSString *ACGTintHex(void) {
    id stored = ACGPreferenceObject(@"ACG.Preference.Tabs.SelectedTintColor");
    return [stored isKindOfClass:NSString.class] ? stored : @"#0A84FF";
}
static UIColor *ACGTintSwatchColor(void) {
    NSString *value = [[ACGTintHex() stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    unsigned int rgb = 0x0A84FF;
    if (value.length == 6) [[NSScanner scannerWithString:value] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}
static NSString *ACGTintHexFromColor(UIColor *color) {
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) return @"#0A84FF";
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(red * 255.0), (int)lround(green * 255.0), (int)lround(blue * 255.0)];
}

// Áp lại nhãn/màu cho mọi ô tab đang hiện. AutoACRelayoutPivotBars chỉ khớp đúng tên lớp "YTPivotBarView"
// nên bỏ sót thanh kính (YTFloatingPivotBarView) và nhãn không đổi cho tới khi thanh tự bố trí lại.
static void ACGRefreshPivotTree(UIView *root) {
    NSString *name = NSStringFromClass(root.class);
    if ([name containsString:@"PivotBarItemView"]) {
        ACGApplyPivotItemPresentation(root);
        [root setNeedsLayout];
        [root layoutIfNeeded];
        if (!ACGTabLabelsHidden(root)) ACGApplyPivotItemPresentation(root);   // sau khi YouTube xếp lại nhãn và icon
        return;
    }
    for (UIView *sub in root.subviews) ACGRefreshPivotTree(sub);
    if ([name containsString:@"PivotBarView"]) {
        [root setNeedsLayout];
        [root layoutIfNeeded];
    }
}

static void ACGRefreshPivotLabelsOnce(void) {
    // Thanh kính nổi có thể nằm ở cửa sổ khác cửa sổ chính, nên duyệt mọi cửa sổ của mọi scene
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    UIWindow *key = AutoACKeyWindow();
    if (key && ![windows containsObject:key]) [windows addObject:key];
    for (UIWindow *w in windows) ACGRefreshPivotTree(w);
}

static void ACGRefreshPivotLabels(void) {
    ACGRefreshPivotLabelsOnce();
    // YouTube xếp lại nhãn sau vài nhịp bố trí; áp lại vài lần để trạng thái mới không bị ghi đè
    for (NSNumber *delay in @[@0.12, @0.4, @0.9]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ ACGRefreshPivotLabelsOnce(); });
    }
}

// Hộp chọn dạng thả xuống: chạm vào hộp mở danh sách để chọn; chạm ngoài hộp không có phản hồi
// Hộp chọn kính lỏng: chạm vào hộp mở danh sách nổi lên giữa màn hình; mục đang chọn tô màu xanh (không dùng dấu ✓)
static UIView *ACGValueMenu(NSString *text, NSArray<NSString *> *titles, NSUInteger selected, void (^pick)(NSUInteger)) {
    UIVisualEffectView *glass = AutoACMakeGlass(14);
    glass.frame = CGRectMake(0, 0, 80, 28);
    glass.layer.cornerRadius = 14;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = glass.bounds;
    b.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [b setTitle:text forState:UIControlStateNormal];
    [b setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    b.titleLabel.textAlignment = NSTextAlignmentCenter;
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.8;
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 6);
    __weak UIButton *weakB = b;
    [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        AutoACSetPopAnchorFromView(weakB);
        gSheetSelected = (NSInteger)selected;
        AutoACPresentSheet(nil, nil, titles, ^(NSInteger index) { if (pick && index >= 0) pick((NSUInteger)index); });
    }] forControlEvents:UIControlEventTouchUpInside];
    [glass.contentView addSubview:b];
    return glass;
}

// Nút kính dạng viên thuốc cùng kiểu với ACGValueMenu nhưng chỉ chạm là chạy (không mở danh sách); kích thước đặt bằng .frame
static UIView *ACGActionPill(NSString *text, void (^tap)(void)) {
    UIVisualEffectView *glass = AutoACMakeGlass(14);
    glass.frame = CGRectMake(0, 0, 80, 28);   // đặt khung trước khi thêm nút để autoresizing co giãn đúng
    glass.layer.cornerRadius = 14;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = glass.bounds;
    b.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [b setTitle:text forState:UIControlStateNormal];
    [b setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    b.titleLabel.textAlignment = NSTextAlignmentCenter;
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.8;
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 6);
    [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { if (tap) tap(); }] forControlEvents:UIControlEventTouchUpInside];
    [glass.contentView addSubview:b];
    return glass;
}

// Tab YouTube hiển thị mặc định là Trang chủ, Shorts, Tạo, Kênh đăng ký, Bạn; các tab dưới đây là tab phụ do AutoAC thêm, mặc định ẩn
static NSArray<NSString *> *ACGExtraTabTokens(void) {
    return @[@"music", @"live", @"gaming", @"news", @"sports", @"learning", @"fashion", @"playlists", @"history", @"notifications", @"watchlater", @"posts"];
}

static NSString *ACGDiagnosticsLine(void) {
    NSString *tabs = [NSString stringWithFormat:AutoACT(@"kiểu %@ · thu nhỏ %@ · tab ẩn %lu · thứ tự %lu · tên riêng %lu"),
        ACGTabBarGlassMode() == 1 ? @"Glass" : AutoACT(@"Mặc định"),
        ACGFeatureEnabled(@"ACG.Preference.Tabs.GlassMinimize") ? AutoACT(@"bật") : AutoACT(@"tắt"),
        (unsigned long)({ NSUInteger n = 0; for (NSString *k in kPrefs.dictionaryRepresentation.allKeys) if ([k hasPrefix:@"ACG.Preference.Tabs.Hidden."] && [kPrefs boolForKey:k]) n++; n; }),
        (unsigned long)[kPrefs arrayForKey:@"ACG.Preference.Tabs.Order"].count,
        (unsigned long)[kPrefs dictionaryForKey:@"ACG.Preference.Tabs.Names"].count];
    return tabs;
}


static void AutoACRelayoutPlayerButton(void);
static void AutoACRelayoutPlayerTools(void);

#pragma mark - Tuỳ chỉnh Overlay

// Các nút công cụ AutoAC trên trình phát. "key" là khoá bật/tắt sẵn có của từng nút (giữ nguyên để bản sao lưu cũ vẫn dùng được)
static NSArray<NSDictionary *> *AutoACOverlayCatalog(void) {
    return @[
        @{@"id": @"download", @"title": AutoACT(@"Tải xuống"), @"symbol": @"arrow.down.circle", @"key": kPlayerFloatKey},
        @{@"id": @"speed", @"title": AutoACT(@"Tốc độ"), @"symbol": @"speedometer", @"key": kPlayerSpeedBtnKey},
        @{@"id": @"pip", @"title": @"PiP", @"symbol": @"pip", @"key": kPlayerPiPKey},
        @{@"id": @"sleep", @"title": AutoACT(@"Hẹn giờ"), @"symbol": @"moon.zzz", @"key": kPlayerSleepBtnKey},
        @{@"id": @"external", @"title": AutoACT(@"Phát ngoài"), @"symbol": @"arrow.up.right.square", @"key": kPlayerExternalKey},
        @{@"id": @"quality", @"title": AutoACT(@"Chất lượng"), @"symbol": @"slider.horizontal.3", @"key": kPlayerQualityKey},
        @{@"id": @"loop", @"title": AutoACT(@"Lặp video"), @"symbol": @"repeat", @"key": kPlayerLoopKey},
    ];
}

static NSDictionary *AutoACOverlayEntry(NSString *ident) {
    for (NSDictionary *c in AutoACOverlayCatalog()) if ([c[@"id"] isEqualToString:ident]) return c;
    return nil;
}

// Chia các nút vào hàng trên, hàng dưới và tắt (một nút có thể ở cả hai hàng). Nút đang bật mà chưa được xếp (mặc định, người dùng cũ) vào hàng trên theo A-Z
static void AutoACOverlayLayout(NSArray<NSString *> **topOut, NSArray<NSString *> **bottomOut, NSArray<NSString *> **offOut) {
    NSArray<NSDictionary *> *catalog = AutoACOverlayCatalog();
    NSMutableSet<NSString *> *enabled = [NSMutableSet set];
    for (NSDictionary *c in catalog) if ([kPrefs boolForKey:c[@"key"]]) [enabled addObject:c[@"id"]];
    NSMutableSet<NSString *> *placed = [NSMutableSet set];
    NSMutableArray<NSString *> *top = [NSMutableArray array], *bottom = [NSMutableArray array];
    for (NSArray *pair in @[@[kOverlayTopKey, top], @[kOverlayBottomKey, bottom]]) {
        NSMutableArray<NSString *> *row = pair[1];
        NSArray *stored = [kPrefs arrayForKey:pair[0]] ?: @[];
        for (id ident in stored) {
            if (![ident isKindOfClass:NSString.class] || ![enabled containsObject:ident] || [row containsObject:ident]) continue;
            [row addObject:ident];   // một nút có thể nằm ở cả hai hàng ("Tất cả")
            [placed addObject:ident];
        }
    }
    NSMutableArray<NSDictionary *> *rest = [NSMutableArray array], *off = [NSMutableArray array];
    for (NSDictionary *c in catalog) {
        if ([placed containsObject:c[@"id"]]) continue;
        [([enabled containsObject:c[@"id"]] ? rest : off) addObject:c];
    }
    NSComparator byTitle = ^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return AutoACCompareVI(a[@"title"], b[@"title"]); };
    [rest sortUsingComparator:byTitle];
    [off sortUsingComparator:byTitle];
    for (NSDictionary *c in rest) [top addObject:c[@"id"]];
    NSMutableArray<NSString *> *offIDs = [NSMutableArray array];
    for (NSDictionary *c in off) [offIDs addObject:c[@"id"]];
    if (topOut) *topOut = top;
    if (bottomOut) *bottomOut = bottom;
    if (offOut) *offOut = offIDs;
}

static CGFloat gAutoACToolStep = 0;   // bước (tâm-tâm) đo gần nhất từ cột icon gốc của hàng trên; hàng dưới dùng lại cho cùng khoảng cách

static NSString *AutoACOverlayNames(NSArray<NSString *> *ids) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *ident in ids) [names addObject:AutoACOverlayEntry(ident)[@"title"] ?: ident];
    return names.count ? [names componentsJoinedByString:@", "] : @"—";
}

static void AutoACOverlaySave(NSArray<NSString *> *top, NSArray<NSString *> *bottom, NSArray<NSString *> *off) {
    for (NSString *ident in off) {
        NSDictionary *c = AutoACOverlayEntry(ident);
        if (c) [kPrefs setBool:NO forKey:c[@"key"]];
    }
    for (NSString *ident in [top arrayByAddingObjectsFromArray:bottom]) {
        NSDictionary *c = AutoACOverlayEntry(ident);
        if (c) [kPrefs setBool:YES forKey:c[@"key"]];
    }
    [kPrefs setObject:top forKey:kOverlayTopKey];
    [kPrefs setObject:bottom forKey:kOverlayBottomKey];
    AutoACRelayoutPlayerTools();
}

// Bản 2.1.64 có hai công tắc hàng trên/hàng dưới: chuyển một lần sang cách xếp mới (ai chỉ bật hàng dưới thì các nút ở hàng dưới)
static void AutoACOverlayMigrateLegacy(void) {
    BOOL hadLegacy = [kPrefs objectForKey:@"kPlayerTopRow"] != nil || [kPrefs objectForKey:@"kPlayerBottomRow"] != nil;
    if (!hadLegacy) return;
    BOOL topExplicitOff = [kPrefs objectForKey:@"kPlayerTopRow"] != nil && ![kPrefs boolForKey:@"kPlayerTopRow"];
    if (topExplicitOff && [kPrefs boolForKey:@"kPlayerBottomRow"] && [kPrefs objectForKey:kOverlayBottomKey] == nil) {
        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        for (NSDictionary *c in AutoACOverlayCatalog()) if ([kPrefs boolForKey:c[@"key"]]) [ids addObject:c[@"id"]];
        [kPrefs setObject:@[] forKey:kOverlayTopKey];
        [kPrefs setObject:ids forKey:kOverlayBottomKey];
    }
    [kPrefs removeObjectForKey:@"kPlayerTopRow"];
    [kPrefs removeObjectForKey:@"kPlayerBottomRow"];
}

// Bảng Tuỳ chỉnh Overlay dạng trực quan: ba dải ngang (hàng trên, hàng dưới, đang tắt), mỗi nút là một biểu tượng tròn.
// Nhấn giữ rồi kéo để đổi thứ tự hoặc sang dải khác; chạm để chọn một nút rồi đặt vị trí bằng nút kính (Tất cả / Dưới / Trên / Tắt).
// "Tất cả" = nút nằm ở cả hai hàng, khi đó nó có hai biểu tượng, mỗi hàng một cái.
static const CGFloat kOverlayChipHeight = 68.0, kOverlayStripHeight = 84.0, kOverlayBoardHeight = 548.0;

// Bảng sắp xếp dùng tông trung tính (không còn màu riêng cho từng dải); chỉ nút đang chọn có viền sáng
static UIColor *AutoACOverlayStripColor(NSInteger strip) {
    return UIColor.labelColor;
}

static NSString *AutoACOverlayKey(NSInteger strip, NSString *ident) {
    return [NSString stringWithFormat:@"%ld|%@", (long)strip, ident];
}

// Bề rộng nút và khoảng cách giữa các nút trong một dải: luôn chừa chỗ cho ít nhất 6 nút mỗi hàng
static void AutoACOverlayMetrics(NSInteger slots, CGFloat boardWidth, CGFloat *chipWidth, CGFloat *gap) {
    CGFloat inner = boardWidth - 24, g = 4;
    NSInteger n = MAX(slots, 6);
    CGFloat w = MIN(MAX(floor((inner - (n - 1) * g) / n), 36), 56);
    CGFloat spread = n > 1 ? (inner - n * w) / (n - 1) : 0;
    if (chipWidth) *chipWidth = w;
    if (gap) *gap = MIN(MAX(spread, g), 10);
}

@interface AutoACOverlayChip : UIView
@property (nonatomic, copy) NSString *ident;
@property (nonatomic, assign) NSInteger strip;
@property (nonatomic, strong) UIView *disc;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) NSString *symbolName;
@property (nonatomic, assign) CGFloat shownDiameter;
@property (nonatomic, strong) UILabel *caption;
@property (nonatomic, strong) UIColor *tint;
@property (nonatomic, assign) BOOL picked;
- (instancetype)initWithEntry:(NSDictionary *)entry strip:(NSInteger)strip;
- (void)applyStrip:(NSInteger)strip;
@end

@implementation AutoACOverlayChip

- (instancetype)initWithEntry:(NSDictionary *)entry strip:(NSInteger)strip {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 58, kOverlayChipHeight)])) {
        _ident = [entry[@"id"] copy];
        _disc = [[UIView alloc] initWithFrame:CGRectMake(7, 0, 44, 44)];
        _disc.layer.cornerRadius = 22;
        _disc.userInteractionEnabled = NO;
        [self addSubview:_disc];
        _symbolName = [entry[@"symbol"] copy];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightMedium];
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:_symbolName withConfiguration:cfg]];
        icon.tintColor = UIColor.labelColor;
        icon.contentMode = UIViewContentModeCenter;
        icon.frame = _disc.bounds;
        [_disc addSubview:icon];
        _iconView = icon;
        _caption = [[UILabel alloc] initWithFrame:CGRectMake(0, 48, 58, 16)];
        _caption.text = entry[@"title"];
        _caption.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
        _caption.textColor = UIColor.labelColor;
        _caption.textAlignment = NSTextAlignmentCenter;
        _caption.adjustsFontSizeToFitWidth = YES;
        _caption.minimumScaleFactor = 0.7;
        [self addSubview:_caption];
        [self applyStrip:strip];
    }
    return self;
}

- (void)applyStrip:(NSInteger)strip {
    _strip = strip;
    _tint = AutoACOverlayStripColor(strip);
    [self refreshLook];
}

- (void)refreshLook {
    BOOL dim = _strip == 2;   // dải "đang tắt/đang ẩn": mờ hơn
    _disc.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:dim ? 0.07 : 0.12];
    _disc.layer.borderWidth = _picked ? 2.0 : 0.75;
    _disc.layer.borderColor = (_picked ? [UIColor.labelColor colorWithAlphaComponent:0.9] : [UIColor.labelColor colorWithAlphaComponent:0.20]).CGColor;
    _iconView.alpha = dim ? 0.55 : 1.0;
    _caption.alpha = _picked ? 1.0 : (dim ? 0.55 : 0.8);
}

- (void)setPicked:(BOOL)picked {
    _picked = picked;
    [self refreshLook];
}

// Nút co theo bề rộng được cấp: đĩa tròn tối đa 44pt, chữ nhỏ dần để vẫn đủ 6 nút mỗi hàng
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat d = MIN(44.0, MAX(28.0, width - 4.0));
    if (fabs(d - _shownDiameter) > 0.5) {
        _shownDiameter = d;
        _disc.bounds = CGRectMake(0, 0, d, d);
        _disc.layer.cornerRadius = d / 2;
        _iconView.frame = _disc.bounds;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:19.0 * d / 44.0 weight:UIImageSymbolWeightMedium];
        _iconView.image = [UIImage systemImageNamed:_symbolName withConfiguration:cfg];
        _caption.font = [UIFont systemFontOfSize:width >= 52 ? 10.5 : 9.5 weight:UIFontWeightMedium];
    }
    _disc.center = CGPointMake(CGRectGetMidX(self.bounds), d / 2);
    _caption.frame = CGRectMake(-2, d + 4, width + 4, 16);
}

@end

@interface AutoACOverlayBoard : UIView
@property (nonatomic, strong) NSMutableArray<NSMutableArray<NSString *> *> *lists;   // 0 hàng trên, 1 hàng dưới, 2 đang tắt
@property (nonatomic, copy) NSString *selectedIdent;
@property (nonatomic, strong) NSMutableDictionary<NSString *, AutoACOverlayChip *> *chips;   // khoá "dải|mã"
@property (nonatomic, strong) NSArray<UIView *> *strips;
@property (nonatomic, strong) NSArray<UILabel *> *hints;
@property (nonatomic, strong) NSArray<NSArray *> *headerParts;   // mỗi dải: biểu tượng, tiêu đề, chú thích
@property (nonatomic, strong) UIView *detail;
@property (nonatomic, strong) UIView *detailDisc;
@property (nonatomic, strong) UIImageView *detailIcon;
@property (nonatomic, strong) UILabel *detailTitle, *detailCaption, *footer;
@property (nonatomic, strong) UIView *pill;
@property (nonatomic, weak) UIScrollView *scroll;
@property (nonatomic, strong) AutoACOverlayChip *dragChip;
@property (nonatomic, assign) NSInteger holeStrip, holeIndex;
@property (nonatomic, assign) CGPoint grab;
- (void)resetToDefault;
@end

@implementation AutoACOverlayBoard

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _chips = [NSMutableDictionary dictionary];
        [self reloadLists];
        NSMutableArray<UIView *> *strips = [NSMutableArray array];
        NSMutableArray<UILabel *> *hints = [NSMutableArray array];
        NSMutableArray<NSArray *> *parts = [NSMutableArray array];
        NSArray<NSString *> *symbols = @[@"rectangle.topthird.inset.filled", @"rectangle.bottomthird.inset.filled", @"power"];
        NSArray<NSString *> *names = @[AutoACT(@"HÀNG TRÊN"), AutoACT(@"HÀNG DƯỚI"), AutoACT(@"ĐANG TẮT")];
        NSArray<NSString *> *captions = @[AutoACT(@"Dưới nút bánh răng"), AutoACT(@"Cạnh nút toàn màn hình"), AutoACT(@"Không hiện")];
        for (NSInteger s = 0; s < 3; s++) {
            UIColor *tint = AutoACOverlayStripColor(s);
            UIView *strip = [[UIView alloc] init];
            strip.backgroundColor = [tint colorWithAlphaComponent:0.05];
            strip.layer.cornerRadius = 20;
            strip.layer.cornerCurve = kCACornerCurveContinuous;
            strip.layer.borderWidth = 0.75;
            strip.layer.borderColor = [tint colorWithAlphaComponent:0.14].CGColor;
            [self addSubview:strip];
            [strips addObject:strip];
            UILabel *hint = [[UILabel alloc] init];
            hint.text = AutoACT(@"Kéo nút vào đây");
            hint.font = [UIFont systemFontOfSize:12];
            hint.textColor = UIColor.tertiaryLabelColor;
            hint.textAlignment = NSTextAlignmentCenter;
            [strip addSubview:hint];
            [hints addObject:hint];
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
            UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbols[(NSUInteger)s] withConfiguration:cfg]];
            icon.tintColor = UIColor.secondaryLabelColor;
            icon.contentMode = UIViewContentModeCenter;
            UILabel *title = [[UILabel alloc] init];
            title.text = names[(NSUInteger)s];
            title.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
            title.textColor = UIColor.secondaryLabelColor;
            UILabel *caption = [[UILabel alloc] init];
            caption.text = captions[(NSUInteger)s];
            caption.font = [UIFont systemFontOfSize:11];
            caption.textColor = UIColor.tertiaryLabelColor;
            caption.textAlignment = NSTextAlignmentRight;
            caption.adjustsFontSizeToFitWidth = YES;
            caption.minimumScaleFactor = 0.8;
            [self addSubview:icon];
            [self addSubview:title];
            [self addSubview:caption];
            [parts addObject:@[icon, title, caption]];
        }
        _strips = strips;
        _hints = hints;
        _headerParts = parts;

        _detail = [[UIView alloc] init];
        _detail.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.07];
        _detail.layer.cornerRadius = 20;
        _detail.layer.cornerCurve = kCACornerCurveContinuous;
        _detail.layer.borderWidth = 1.0;
        _detail.layer.borderColor = [UIColor.labelColor colorWithAlphaComponent:0.12].CGColor;
        [self addSubview:_detail];
        _detailDisc = [[UIView alloc] initWithFrame:CGRectMake(14, 15, 36, 36)];
        _detailDisc.layer.cornerRadius = 18;
        _detailDisc.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.12];
        [_detail addSubview:_detailDisc];
        _detailIcon = [[UIImageView alloc] initWithFrame:_detailDisc.bounds];
        _detailIcon.tintColor = UIColor.labelColor;
        _detailIcon.contentMode = UIViewContentModeCenter;
        [_detailDisc addSubview:_detailIcon];
        _detailTitle = [[UILabel alloc] init];
        _detailTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _detailTitle.textColor = UIColor.labelColor;
        [_detail addSubview:_detailTitle];
        _detailCaption = [[UILabel alloc] init];
        _detailCaption.text = AutoACT(@"Vị trí Overlay");
        _detailCaption.font = [UIFont systemFontOfSize:11.5];
        _detailCaption.textColor = UIColor.secondaryLabelColor;
        [_detail addSubview:_detailCaption];

        _footer = [[UILabel alloc] init];
        _footer.numberOfLines = 0;
        _footer.font = [UIFont systemFontOfSize:11];
        _footer.textColor = UIColor.secondaryLabelColor;
        _footer.text = AutoACT(@"Nhấn giữ một nút rồi kéo để đổi thứ tự hoặc sang hàng khác. Chạm một nút để chọn, rồi đặt vị trí bằng nút kính ở trên (Tất cả = cả hai hàng). Thứ tự đọc từ trái sang phải: nút cuối cùng nằm sát nút bánh răng (hàng trên) hoặc sát nút toàn màn hình (hàng dưới).");
        [self addSubview:_footer];

        [self selectDefault];
        [self rebuildAnimated:NO];
    }
    return self;
}

- (void)reloadLists {
    NSArray<NSString *> *top = nil, *bottom = nil, *off = nil;
    AutoACOverlayLayout(&top, &bottom, &off);
    self.lists = [NSMutableArray arrayWithObjects:[top mutableCopy], [bottom mutableCopy], [off mutableCopy], nil];
}

- (void)selectDefault {
    if (self.selectedIdent && AutoACOverlayEntry(self.selectedIdent)) return;
    for (NSMutableArray<NSString *> *list in self.lists) if (list.count) { self.selectedIdent = list.firstObject; return; }
    self.selectedIdent = [AutoACOverlayCatalog().firstObject[@"id"] copy];
}

// Nút đang chọn nằm ở đâu: 0 Tất cả, 1 Dưới, 2 Trên, 3 Tắt (đúng thứ tự trong nút kính)
- (NSUInteger)positionOf:(NSString *)ident {
    BOOL inTop = [self.lists[0] containsObject:ident], inBottom = [self.lists[1] containsObject:ident];
    return (inTop && inBottom) ? 0 : (inBottom ? 1 : (inTop ? 2 : 3));
}

- (void)normalize {
    for (NSDictionary *c in AutoACOverlayCatalog()) {
        NSString *ident = c[@"id"];
        BOOL placed = [self.lists[0] containsObject:ident] || [self.lists[1] containsObject:ident];
        if (placed) [self.lists[2] removeObject:ident];
        else if (![self.lists[2] containsObject:ident]) [self.lists[2] addObject:ident];
    }
}

- (void)persist {
    [self normalize];
    AutoACOverlaySave([self.lists[0] copy], [self.lists[1] copy], [self.lists[2] copy]);
}

- (void)resetToDefault {
    for (NSDictionary *c in AutoACOverlayCatalog()) [kPrefs removeObjectForKey:c[@"key"]];   // về giá trị mặc định đã đăng ký: tất cả bật
    [kPrefs removeObjectForKey:kOverlayTopKey];
    [kPrefs removeObjectForKey:kOverlayBottomKey];
    [self reloadLists];
    [self selectDefault];
    [self rebuildAnimated:YES];
    AutoACRelayoutPlayerTools();
}

#pragma mark Bố cục

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds), y = 4;
    for (NSInteger s = 0; s < 3; s++) {
        NSArray *parts = self.headerParts[(NSUInteger)s];
        ((UIView *)parts[0]).frame = CGRectMake(0, y + 4, 20, 20);
        ((UIView *)parts[1]).frame = CGRectMake(26, y, 110, 28);
        ((UIView *)parts[2]).frame = CGRectMake(width - 170, y, 170, 28);
        UIView *strip = self.strips[(NSUInteger)s];
        strip.frame = CGRectMake(0, y + 30, width, kOverlayStripHeight);
        self.hints[(NSUInteger)s].frame = strip.bounds;
        y += 30 + kOverlayStripHeight + 12;
    }
    self.detail.frame = CGRectMake(0, y, width, 66);
    self.detailTitle.frame = CGRectMake(62, 12, MAX(width - 62 - 128, 40), 22);
    self.detailCaption.frame = CGRectMake(62, 35, MAX(width - 62 - 128, 40), 16);
    self.pill.frame = CGRectMake(width - 14 - 104, 17, 104, 32);
    y += 66 + 12;
    CGSize fit = [self.footer sizeThatFits:CGSizeMake(MAX(width - 4, 10), CGFLOAT_MAX)];
    self.footer.frame = CGRectMake(2, y, MAX(width - 4, 10), ceil(fit.height));
    [self layoutChipsAnimated:NO];
}

- (void)placeChip:(AutoACOverlayChip *)chip frame:(CGRect)frame animated:(BOOL)animated {
    if (chip.tag == 0) { chip.frame = frame; chip.tag = 1; return; }   // nút mới: vào đúng chỗ, không bay từ góc
    if (CGRectEqualToRect(chip.frame, frame)) return;
    if (!animated) { chip.frame = frame; return; }
    [UIView animateWithDuration:0.26 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ chip.frame = frame; } completion:nil];
}

- (void)layoutChipsAnimated:(BOOL)animated {
    CGFloat width = CGRectGetWidth(self.bounds);
    if (width <= 0) return;
    NSString *dragKey = self.dragChip ? AutoACOverlayKey(self.dragChip.strip, self.dragChip.ident) : nil;
    for (NSInteger s = 0; s < 3; s++) {
        UIView *strip = self.strips[(NSUInteger)s];
        NSMutableArray<AutoACOverlayChip *> *items = [NSMutableArray array];
        for (NSString *ident in self.lists[(NSUInteger)s]) {
            NSString *key = AutoACOverlayKey(s, ident);
            if ([key isEqualToString:dragKey]) continue;
            AutoACOverlayChip *chip = self.chips[key];
            if (chip) [items addObject:chip];
        }
        BOOL hasHole = self.dragChip != nil && self.holeStrip == s;
        NSInteger slots = (NSInteger)items.count + (hasHole ? 1 : 0);
        self.hints[(NSUInteger)s].hidden = slots > 0;
        CGFloat chipWidth = 58, gap = 10;
        AutoACOverlayMetrics(slots, width, &chipWidth, &gap);
        CGFloat top = CGRectGetMinY(strip.frame) + (kOverlayStripHeight - kOverlayChipHeight) / 2;
        NSInteger slot = 0;
        for (NSInteger i = 0; i <= (NSInteger)items.count; i++) {
            if (hasHole && i == self.holeIndex) slot++;   // chừa chỗ cho nút đang kéo
            if (i == (NSInteger)items.count) break;
            CGRect frame = CGRectMake(12 + slot * (chipWidth + gap), top, chipWidth, kOverlayChipHeight);
            slot++;
            [self placeChip:items[(NSUInteger)i] frame:frame animated:animated];
        }
    }
}

- (void)refreshPicked {
    for (AutoACOverlayChip *chip in self.chips.allValues) chip.picked = [chip.ident isEqualToString:self.selectedIdent];
}

- (void)refreshDetail {
    NSDictionary *entry = AutoACOverlayEntry(self.selectedIdent);
    self.detailTitle.text = entry[@"title"];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium];
    self.detailIcon.image = entry ? [UIImage systemImageNamed:entry[@"symbol"] withConfiguration:cfg] : nil;
    NSUInteger position = entry ? [self positionOf:self.selectedIdent] : 3;
    NSArray<NSString *> *titles = @[AutoACT(@"Tất cả"), AutoACT(@"Dưới"), AutoACT(@"Trên"), AutoACT(@"Tắt")];
    [self.pill removeFromSuperview];
    __weak AutoACOverlayBoard *weakSelf = self;
    UIView *pill = ACGValueMenu([titles[position] stringByAppendingString:@" ▾"], titles, position, ^(NSUInteger index) { [weakSelf applyPosition:index]; });
    pill.frame = CGRectMake(CGRectGetWidth(self.bounds) - 14 - 104, 17, 104, 32);
    [self.detail addSubview:pill];
    self.pill = pill;
}

// Dựng lại các nút theo dữ liệu hiện tại (giữ nút đã có để chúng trượt sang chỗ mới)
- (void)rebuildAnimated:(BOOL)animated {
    [self normalize];
    NSMutableSet<NSString *> *wanted = [NSMutableSet set];
    for (NSInteger s = 0; s < 3; s++) {
        for (NSString *ident in self.lists[(NSUInteger)s]) {
            NSString *key = AutoACOverlayKey(s, ident);
            [wanted addObject:key];
            if (self.chips[key]) continue;
            NSDictionary *entry = AutoACOverlayEntry(ident);
            if (!entry) continue;
            AutoACOverlayChip *chip = [[AutoACOverlayChip alloc] initWithEntry:entry strip:s];
            UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlePress:)];
            press.minimumPressDuration = 0.2;
            [chip addGestureRecognizer:press];
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
            [chip addGestureRecognizer:tap];
            [self addSubview:chip];
            self.chips[key] = chip;
            if (animated) { chip.alpha = 0; [UIView animateWithDuration:0.2 animations:^{ chip.alpha = 1; }]; }
        }
    }
    for (NSString *key in self.chips.allKeys) {
        AutoACOverlayChip *chip = self.chips[key];
        if ([wanted containsObject:key] || chip == self.dragChip) continue;
        [self.chips removeObjectForKey:key];
        [UIView animateWithDuration:animated ? 0.18 : 0 animations:^{ chip.alpha = 0; } completion:^(BOOL finished) { [chip removeFromSuperview]; }];
    }
    [self layoutChipsAnimated:animated];
    [self refreshPicked];
    [self refreshDetail];
}

#pragma mark Thao tác

- (void)select:(NSString *)ident {
    if (!ident || [ident isEqualToString:self.selectedIdent]) return;
    self.selectedIdent = ident;
    [self refreshPicked];
    [self refreshDetail];
}

- (void)handleTap:(UITapGestureRecognizer *)g {
    AutoACOverlayChip *chip = (AutoACOverlayChip *)g.view;
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self select:chip.ident];
}

// Đặt vị trí cho nút đang chọn bằng nút kính: 0 Tất cả, 1 Dưới, 2 Trên, 3 Tắt
- (void)applyPosition:(NSUInteger)index {
    NSString *ident = self.selectedIdent;
    if (!ident) return;
    NSMutableArray<NSString *> *top = self.lists[0], *bottom = self.lists[1];
    BOOL wantTop = index == 0 || index == 2, wantBottom = index == 0 || index == 1;
    if (wantTop) { if (![top containsObject:ident]) [top addObject:ident]; } else { [top removeObject:ident]; }
    if (wantBottom) { if (![bottom containsObject:ident]) [bottom addObject:ident]; } else { [bottom removeObject:ident]; }
    [self persist];
    [self rebuildAnimated:YES];
}

- (NSInteger)stripAtY:(CGFloat)y {
    NSInteger best = 0;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSInteger s = 0; s < 3; s++) {
        CGRect frame = self.strips[(NSUInteger)s].frame;
        CGFloat distance = y < CGRectGetMinY(frame) ? CGRectGetMinY(frame) - y : (y > CGRectGetMaxY(frame) ? y - CGRectGetMaxY(frame) : 0);
        if (distance < bestDistance) { bestDistance = distance; best = s; }
    }
    return best;
}

// Vị trí chèn theo toạ độ ngang, tính trên bố cục KHÔNG có chỗ trống (để chỗ trống không làm các nút nhảy qua lại)
- (NSInteger)slotAtX:(CGFloat)x inStrip:(NSInteger)strip {
    NSString *dragKey = AutoACOverlayKey(self.dragChip.strip, self.dragChip.ident);
    NSInteger count = 0;
    for (NSString *ident in self.lists[(NSUInteger)strip]) if (![AutoACOverlayKey(strip, ident) isEqualToString:dragKey]) count++;
    CGFloat chipWidth = 58, gap = 10;
    AutoACOverlayMetrics(count, CGRectGetWidth(self.bounds), &chipWidth, &gap);
    NSInteger index = 0;
    for (NSInteger i = 0; i < count; i++) if (12 + i * (chipWidth + gap) + chipWidth / 2 < x) index++;
    return index;
}

- (void)highlightStrip:(NSInteger)target {
    [UIView animateWithDuration:0.15 animations:^{
        for (NSInteger s = 0; s < 3; s++) {
            UIColor *tint = AutoACOverlayStripColor(s);
            BOOL on = s == target;
            self.strips[(NSUInteger)s].backgroundColor = [tint colorWithAlphaComponent:on ? 0.11 : 0.05];
            self.strips[(NSUInteger)s].layer.borderColor = [tint colorWithAlphaComponent:on ? 0.55 : 0.14].CGColor;
        }
    }];
}

- (void)handlePress:(UILongPressGestureRecognizer *)g {
    AutoACOverlayChip *chip = (AutoACOverlayChip *)g.view;
    CGPoint p = [g locationInView:self];
    switch (g.state) {
        case UIGestureRecognizerStateBegan: {
            if (self.dragChip) return;
            [[UIImpactFeedbackGenerator new] impactOccurred];
            [self select:chip.ident];
            self.dragChip = chip;
            self.grab = CGPointMake(p.x - chip.center.x, p.y - chip.center.y);
            self.holeStrip = chip.strip;
            NSUInteger at = [self.lists[(NSUInteger)chip.strip] indexOfObject:chip.ident];
            self.holeIndex = at == NSNotFound ? 0 : (NSInteger)at;
            self.scroll.scrollEnabled = NO;
            [self bringSubviewToFront:chip];
            chip.layer.shadowColor = UIColor.blackColor.CGColor;
            chip.layer.shadowOpacity = 0.35;
            chip.layer.shadowRadius = 8;
            chip.layer.shadowOffset = CGSizeMake(0, 4);
            [UIView animateWithDuration:0.18 animations:^{ chip.transform = CGAffineTransformMakeScale(1.14, 1.14); }];
            [self highlightStrip:self.holeStrip];
            [self layoutChipsAnimated:YES];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (chip != self.dragChip) return;
            chip.center = CGPointMake(p.x - self.grab.x, p.y - self.grab.y);
            NSInteger strip = [self stripAtY:p.y];
            NSInteger slot = [self slotAtX:p.x inStrip:strip];
            if (strip != self.holeStrip || slot != self.holeIndex) {
                self.holeStrip = strip;
                self.holeIndex = slot;
                [self highlightStrip:strip];
                [self layoutChipsAnimated:YES];
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
            [self finishDrag:YES];
            break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self finishDrag:NO];
            break;
        default:
            break;
    }
}

- (void)finishDrag:(BOOL)commit {
    AutoACOverlayChip *chip = self.dragChip;
    if (!chip) return;
    NSInteger from = chip.strip;
    NSString *ident = chip.ident;
    NSString *oldKey = AutoACOverlayKey(from, ident);
    self.scroll.scrollEnabled = YES;
    [self highlightStrip:-1];
    CGPoint center = chip.center;
    chip.transform = CGAffineTransformIdentity;
    chip.center = center;
    chip.layer.shadowOpacity = 0;
    self.dragChip = nil;
    if (commit) {
        NSInteger to = self.holeStrip, index = self.holeIndex;
        [self.lists[(NSUInteger)from] removeObject:ident];
        if (to == 2) { [self.lists[0] removeObject:ident]; [self.lists[1] removeObject:ident]; }
        else { [self.lists[(NSUInteger)to] removeObject:ident]; }
        NSMutableArray<NSString *> *dest = self.lists[(NSUInteger)to];
        [dest insertObject:ident atIndex:MIN((NSUInteger)MAX(index, 0), dest.count)];
        // gắn lại khoá: nút vừa thả giữ nguyên view để trượt vào chỗ mới
        [self.chips removeObjectForKey:oldKey];
        NSString *newKey = AutoACOverlayKey(to, ident);
        AutoACOverlayChip *twin = self.chips[newKey];
        if (twin && twin != chip) { [self.chips removeObjectForKey:newKey]; [twin removeFromSuperview]; }
        [chip applyStrip:to];
        self.chips[newKey] = chip;
        [self persist];
        [[UIImpactFeedbackGenerator new] impactOccurred];
    }
    [self rebuildAnimated:YES];
}

@end

static AutoACOverlayBoard *gAutoACOverlayBoard;   // giữ bảng khi khung đang mở

static void AutoACPresentOverlayEditor(void) {
    UIWindow *window = AutoACKeyWindow();
    if (!window || gMenu) return;
    AutoACOverlayBoard *board = [[AutoACOverlayBoard alloc] initWithFrame:CGRectMake(0, 0, 320, kOverlayBoardHeight)];
    gAutoACOverlayBoard = board;
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.delaysContentTouches = NO;
    scroll.alwaysBounceVertical = NO;
    board.scroll = scroll;
    board.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:board];
    UIView *holder = [[UIView alloc] init];
    holder.translatesAutoresizingMaskIntoConstraints = NO;
    [holder addSubview:scroll];
    NSLayoutConstraint *wish = [holder.heightAnchor constraintEqualToConstant:kOverlayBoardHeight + 8];
    wish.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        wish,
        [scroll.topAnchor constraintEqualToAnchor:holder.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor constant:-16],
        [board.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [board.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [board.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [board.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [board.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [board.heightAnchor constraintEqualToConstant:kOverlayBoardHeight],
    ]];
    AutoACShowPanel(AutoACT(@"Tuỳ chỉnh Overlay"), AutoACT(@"Hàng trên, hàng dưới, thứ tự"), holder, window.safeAreaInsets.top + 12,
                    AutoACT(@"Khôi phục Overlay mặc định"), ^{
        static CFTimeInterval armedAt = 0;
        CFTimeInterval now = CACurrentMediaTime();
        if (armedAt > 0 && now - armedAt < 4.0) {
            armedAt = 0;
            [gAutoACOverlayBoard resetToDefault];
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
            AutoACShowHub(@"arrow.counterclockwise", UIColor.systemGreenColor, AutoACT(@"Đã khôi phục Overlay mặc định"), nil, 2.0);
            return;
        }
        armedAt = now;
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeWarning];
        AutoACShowHub(@"arrow.counterclockwise", UIColor.systemOrangeColor, AutoACT(@"Chạm lần nữa để khôi phục Overlay"), AutoACT(@"Trong 4 giây"), 3.0);
    });
}



#pragma mark - Tuỳ chỉnh tab (bảng kéo thả, cùng kiểu với Tuỳ chỉnh Overlay)

// Danh sách tab: mã, tên mặc định, biểu tượng, khoá lưu trạng thái ẨN
static NSArray<NSDictionary *> *ACGTabCatalog(void) {
    NSArray<NSArray<NSString *> *> *rows = @[
        @[@"home", AutoACT(@"Trang chủ"), @"house", @"ACG.Preference.Tabs.Hidden.Home"],
        @[@"shorts", @"Shorts", @"play.rectangle", @"ACG.Preference.Tabs.Hidden.Shorts"],
        @[@"create", AutoACT(@"Tạo"), @"plus.circle", @"ACG.Preference.Tabs.Hidden.Create"],
        @[@"subscriptions", AutoACT(@"Kênh đăng ký"), @"rectangle.stack", @"ACG.Preference.Tabs.Hidden.Subscriptions"],
        @[@"library", AutoACT(@"Bạn"), @"person.circle", @"ACG.Preference.Tabs.Hidden.Library"],
        @[@"music", AutoACT(@"Nhạc"), @"music.note", @"ACG.Preference.Tabs.Hidden.Music"],
        @[@"live", AutoACT(@"Trực tiếp"), @"dot.radiowaves.left.and.right", @"ACG.Preference.Tabs.Hidden.Live"],
        @[@"gaming", AutoACT(@"Trò chơi"), @"gamecontroller", @"ACG.Preference.Tabs.Hidden.Gaming"],
        @[@"news", AutoACT(@"Tin tức"), @"newspaper", @"ACG.Preference.Tabs.Hidden.News"],
        @[@"posts", AutoACT(@"Bài đăng"), @"bubble.left.and.bubble.right", @"ACG.Preference.Tabs.Hidden.Posts"],
        @[@"sports", AutoACT(@"Thể thao"), @"trophy", @"ACG.Preference.Tabs.Hidden.Sports"],
        @[@"learning", AutoACT(@"Học tập"), @"graduationcap", @"ACG.Preference.Tabs.Hidden.Learning"],
        @[@"fashion", AutoACT(@"Thời trang"), @"tshirt", @"ACG.Preference.Tabs.Hidden.Fashion"],
        @[@"playlists", @"Playlist", @"music.note.list", @"ACG.Preference.Tabs.Hidden.Playlists"],
        @[@"history", AutoACT(@"Lịch sử"), @"clock.arrow.circlepath", @"ACG.Preference.Tabs.Hidden.History"],
        @[@"notifications", AutoACT(@"Thông báo"), @"bell", @"ACG.Preference.Tabs.Hidden.Notifs"],
        @[@"watchlater", AutoACT(@"Xem sau"), @"clock", @"ACG.Preference.Tabs.Hidden.WatchLater"],
    ];
    NSMutableArray<NSDictionary *> *list = [NSMutableArray array];
    for (NSArray<NSString *> *r in rows) [list addObject:@{@"id": r[0], @"title": r[1], @"symbol": r[2], @"key": r[3]}];
    return list;
}

static NSDictionary *ACGTabEntry(NSString *token) {
    for (NSDictionary *e in ACGTabCatalog()) if ([e[@"id"] isEqualToString:token]) return e;
    return nil;
}

// Tên đang dùng cho tab (tên riêng nếu có, không thì tên mặc định)
static NSString *ACGTabDisplayName(NSDictionary *entry) {
    NSString *custom = [kPrefs dictionaryForKey:@"ACG.Preference.Tabs.Names"][entry[@"id"]];
    return custom.length ? custom : entry[@"title"];
}

static const CGFloat kTabRowPitch = 70.0, kTabChipHeight = 64.0;

// Số nút mỗi hàng (ít nhất 6, nhiều hơn khi màn hình rộng), bề rộng nút và khoảng cách giữa các nút (dải tự xuống hàng khi nhiều tab)
static void ACGTabMetrics(CGFloat boardWidth, NSInteger *perRow, CGFloat *gap, CGFloat *chipWidth) {
    CGFloat inner = boardWidth - 24.0, g = 4.0;
    NSInteger n = MAX(6, (NSInteger)floor((inner + g) / (44.0 + g)));
    CGFloat w = MIN(MAX(floor((inner - (n - 1) * g) / n), 36.0), 56.0);
    CGFloat spread = n > 1 ? (inner - n * w) / (n - 1) : 0;
    if (perRow) *perRow = n;
    if (gap) *gap = MIN(MAX(spread, g), 10.0);
    if (chipWidth) *chipWidth = w;
}

static UIColor *ACGTabStripColor(NSInteger strip) { return UIColor.labelColor; }   // tông trung tính, không màu riêng cho từng dải

@interface ACGTabBoard : UIView <UIColorPickerViewControllerDelegate>
@property (nonatomic, strong) NSMutableArray<NSMutableArray<NSString *> *> *lists;   // 0 đang hiện (có thứ tự), 1 đang ẩn
@property (nonatomic, copy) NSString *selectedIdent;
@property (nonatomic, strong) NSMutableDictionary<NSString *, AutoACOverlayChip *> *chips;   // khoá "dải|mã"
@property (nonatomic, strong) NSArray<UIView *> *strips;
@property (nonatomic, strong) NSArray<UILabel *> *hints;
@property (nonatomic, strong) NSArray<NSArray *> *headerParts;
@property (nonatomic, strong) UIView *detail, *detailDisc, *renameButton, *pill;
@property (nonatomic, strong) UIImageView *detailIcon;
@property (nonatomic, strong) UILabel *detailTitle, *detailCaption, *footer, *settingsTitle;
@property (nonatomic, strong) UIView *settingsCard;
@property (nonatomic, strong) NSMutableArray<UIView *> *settingRows;
@property (nonatomic, weak) UIScrollView *scroll;
@property (nonatomic, weak) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong) AutoACOverlayChip *dragChip;
@property (nonatomic, assign) NSInteger holeStrip, holeIndex;
@property (nonatomic, assign) CGPoint grab;
@property (nonatomic, strong) NSArray<NSNumber *> *frozenSlots;   // trong lúc kéo: số ô mỗi dải được giữ nguyên để dải không nhảy
- (void)restoreYouTubeDefaults;
@end

@implementation ACGTabBoard

static NSString *ACGTabKey(NSInteger strip, NSString *ident) { return [NSString stringWithFormat:@"%ld|%@", (long)strip, ident]; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _chips = [NSMutableDictionary dictionary];
        _settingRows = [NSMutableArray array];
        [self loadLists];
        NSMutableArray<UIView *> *strips = [NSMutableArray array];
        NSMutableArray<UILabel *> *hints = [NSMutableArray array];
        NSMutableArray<NSArray *> *parts = [NSMutableArray array];
        NSArray<NSString *> *symbols = @[@"rectangle.bottomthird.inset.filled", @"eye.slash"];
        NSArray<NSString *> *names = @[AutoACT(@"TAB ĐANG HIỆN"), AutoACT(@"TAB ĐANG ẨN")];
        NSArray<NSString *> *captions = @[AutoACT(@"Trên thanh tab, từ trái sang phải"), AutoACT(@"Không hiện trên thanh tab")];
        for (NSInteger s = 0; s < 2; s++) {
            UIColor *tint = ACGTabStripColor(s);
            UIView *strip = [[UIView alloc] init];
            strip.backgroundColor = [tint colorWithAlphaComponent:0.05];
            strip.layer.cornerRadius = 20;
            strip.layer.cornerCurve = kCACornerCurveContinuous;
            strip.layer.borderWidth = 0.75;
            strip.layer.borderColor = [tint colorWithAlphaComponent:0.14].CGColor;
            [self addSubview:strip];
            [strips addObject:strip];
            UILabel *hint = [[UILabel alloc] init];
            hint.text = AutoACT(@"Kéo tab vào đây");
            hint.font = [UIFont systemFontOfSize:12];
            hint.textColor = UIColor.tertiaryLabelColor;
            hint.textAlignment = NSTextAlignmentCenter;
            [strip addSubview:hint];
            [hints addObject:hint];
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
            UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbols[(NSUInteger)s] withConfiguration:cfg]];
            icon.tintColor = UIColor.secondaryLabelColor;
            icon.contentMode = UIViewContentModeCenter;
            UILabel *title = [[UILabel alloc] init];
            title.text = names[(NSUInteger)s];
            title.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
            title.textColor = UIColor.secondaryLabelColor;
            UILabel *caption = [[UILabel alloc] init];
            caption.text = captions[(NSUInteger)s];
            caption.font = [UIFont systemFontOfSize:11];
            caption.textColor = UIColor.tertiaryLabelColor;
            caption.textAlignment = NSTextAlignmentRight;
            caption.adjustsFontSizeToFitWidth = YES;
            caption.minimumScaleFactor = 0.75;
            [self addSubview:icon];
            [self addSubview:title];
            [self addSubview:caption];
            [parts addObject:@[icon, title, caption]];
        }
        _strips = strips;
        _hints = hints;
        _headerParts = parts;

        _detail = [[UIView alloc] init];
        _detail.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.07];
        _detail.layer.cornerRadius = 20;
        _detail.layer.cornerCurve = kCACornerCurveContinuous;
        _detail.layer.borderWidth = 1.0;
        _detail.layer.borderColor = [UIColor.labelColor colorWithAlphaComponent:0.12].CGColor;
        [self addSubview:_detail];
        _detailDisc = [[UIView alloc] initWithFrame:CGRectMake(14, 15, 36, 36)];
        _detailDisc.layer.cornerRadius = 18;
        _detailDisc.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.12];
        [_detail addSubview:_detailDisc];
        _detailIcon = [[UIImageView alloc] initWithFrame:_detailDisc.bounds];
        _detailIcon.tintColor = UIColor.labelColor;
        _detailIcon.contentMode = UIViewContentModeCenter;
        [_detailDisc addSubview:_detailIcon];
        _detailTitle = [[UILabel alloc] init];
        _detailTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _detailTitle.textColor = UIColor.labelColor;
        _detailTitle.adjustsFontSizeToFitWidth = YES;
        _detailTitle.minimumScaleFactor = 0.8;
        [_detail addSubview:_detailTitle];
        _detailCaption = [[UILabel alloc] init];
        _detailCaption.font = [UIFont systemFontOfSize:11.5];
        _detailCaption.textColor = UIColor.secondaryLabelColor;
        [_detail addSubview:_detailCaption];
        // nút kính đổi tên tab đang chọn (cùng hàng và cùng kích thước với nút Hiện/Ẩn)
        __weak ACGTabBoard *weakBoard = self;
        _renameButton = ACGActionPill([AutoACT(@"Đổi tên tab") stringByAppendingString:@"…"], ^{ [weakBoard renameTapped]; });
        [_detail addSubview:_renameButton];

        _settingsTitle = [[UILabel alloc] init];
        _settingsTitle.text = @"Liquid glass";
        _settingsTitle.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
        _settingsTitle.textColor = UIColor.secondaryLabelColor;
        [self addSubview:_settingsTitle];
        _settingsCard = [[UIView alloc] init];
        _settingsCard.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.06];
        _settingsCard.layer.cornerRadius = 20;
        _settingsCard.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_settingsCard];

        _footer = [[UILabel alloc] init];
        _footer.numberOfLines = 0;
        _footer.font = [UIFont systemFontOfSize:11];
        _footer.textColor = UIColor.secondaryLabelColor;
        _footer.text = AutoACT(@"Nhấn giữ một tab rồi kéo để đổi thứ tự hoặc chuyển giữa hai dải. Chạm một tab để chọn, rồi ẩn/hiện hoặc đổi tên ở thẻ bên dưới. Thay đổi tab có hiệu lực sau khi mở lại app.");
        [self addSubview:_footer];

        [self selectDefault];
        [self buildSettings];
        [self rebuildAnimated:NO];
    }
    return self;
}

#pragma mark Dữ liệu

- (void)loadLists {
    NSMutableArray<NSString *> *active = [NSMutableArray array], *hidden = [NSMutableArray array];
    NSArray<NSString *> *extras = ACGExtraTabTokens();
    for (NSDictionary *tab in ACGTabCatalog()) {
        id stored = ACGPreferenceObject(tab[@"key"]);
        BOOL isHidden = [stored respondsToSelector:@selector(boolValue)] ? [stored boolValue] : [extras containsObject:tab[@"id"]];
        ACGSetPreference(tab[@"key"], isHidden);
        [(isHidden ? hidden : active) addObject:tab[@"id"]];
    }
    NSArray *order = [kPrefs arrayForKey:@"ACG.Preference.Tabs.Order"];
    if (order.count != 0) {
        [active sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
            NSUInteger l = [order indexOfObject:left], r = [order indexOfObject:right];
            l = l == NSNotFound ? NSUIntegerMax : l;
            r = r == NSNotFound ? NSUIntegerMax : r;
            return l < r ? NSOrderedAscending : (l > r ? NSOrderedDescending : NSOrderedSame);
        }];
    }
    self.lists = [NSMutableArray arrayWithObjects:active, hidden, nil];
}

- (void)selectDefault {
    if (self.selectedIdent && ACGTabEntry(self.selectedIdent)) return;
    for (NSMutableArray<NSString *> *list in self.lists) if (list.count) { self.selectedIdent = list.firstObject; return; }
    self.selectedIdent = @"home";
}

- (void)persist {
    for (NSString *token in self.lists[0]) ACGSetPreference(ACGTabEntry(token)[@"key"], NO);
    for (NSString *token in self.lists[1]) ACGSetPreference(ACGTabEntry(token)[@"key"], YES);
    [kPrefs setObject:[self.lists[0] copy] forKey:@"ACG.Preference.Tabs.Order"];
    [NSNotificationCenter.defaultCenter postNotificationName:ACGTabConfigChangedNote object:nil];
    ACGRefreshPivotBarBackground();
    [self buildSettings];   // danh sách "Tab khi mở app" phụ thuộc tab đang ẩn
    [self setNeedsLayout];
}

// Đưa tập tab, thứ tự, tên riêng và tab khi mở app về như YouTube gốc (kiểu thanh tab, nhãn, màu giữ nguyên)
- (void)restoreYouTubeDefaults {
    NSArray<NSString *> *extras = ACGExtraTabTokens();
    for (NSDictionary *tab in ACGTabCatalog()) ACGSetPreference(tab[@"key"], [extras containsObject:tab[@"id"]]);
    [kPrefs removeObjectForKey:@"ACG.Preference.Tabs.Order"];
    [kPrefs removeObjectForKey:@"ACG.Preference.Tabs.Names"];
    [kPrefs removeObjectForKey:@"ACG.Preference.Tabs.Startup"];
    [self loadLists];
    [self selectDefault];
    [self reloadChipsAnimated:YES];
    [self buildSettings];
    [NSNotificationCenter.defaultCenter postNotificationName:ACGTabConfigChangedNote object:nil];
    ACGRefreshPivotBarBackground();
    ACGRefreshPivotLabels();
}

#pragma mark Cài đặt chung

- (UIView *)settingRowWithTitle:(NSString *)title detail:(NSString *)detail accessory:(UIView *)accessory tap:(SEL)tap {
    UIView *row = [[UIView alloc] init];
    UILabel *t = [[UILabel alloc] init];
    t.text = title;
    t.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    t.textColor = UIColor.labelColor;
    t.adjustsFontSizeToFitWidth = YES;
    t.minimumScaleFactor = 0.8;
    t.tag = 101;
    UILabel *d = [[UILabel alloc] init];
    d.text = detail;
    d.font = [UIFont systemFontOfSize:12];
    d.textColor = UIColor.secondaryLabelColor;
    d.tag = 102;
    [row addSubview:t];
    [row addSubview:d];
    if (accessory) { accessory.tag = 103; [row addSubview:accessory]; }
    if (tap) [row addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:tap]];
    return row;
}

- (UISwitch *)switchForKey:(NSString *)key on:(BOOL)on {
    UISwitch *toggle = [UISwitch new];
    toggle.transform = CGAffineTransformMakeScale(0.95, 0.95);
    toggle.onTintColor = UIColor.systemGreenColor;
    toggle.on = on;
    objc_setAssociatedObject(toggle, ACGTabSwitchKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return toggle;
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, ACGTabSwitchKey);
    BOOL isLabelsKey = [key isEqualToString:@"ACG.Preference.Tabs.LabelsHidden"];
    ACGSetPreference(key, isLabelsKey ? !sender.isOn : sender.isOn);   // khoá nhãn lưu trạng thái ẨN nên công tắc đảo ngược
    [kPrefs synchronize];
    ACGRefreshPivotBarBackground();
    if (isLabelsKey) ACGRefreshPivotLabels();
}

- (void)buildSettings {
    for (UIView *row in self.settingRows) [row removeFromSuperview];
    [self.settingRows removeAllObjects];
    __weak ACGTabBoard *weakSelf = self;
    BOOL liquid = ACGLiquidGlassAvailable();

    // ── Nhóm kính lỏng ──
    if (liquid) {
#if ACG_TAB_GLASS_ENABLED
        UIView *glassPill = ACGValueMenu(ACGTabBarGlassMode() == 1 ? @"Glass" : AutoACT(@"Mặc định"), @[AutoACT(@"Mặc định"), @"Glass"],
                                         ACGTabBarGlassMode() == 1 ? 1 : 0, ^(NSUInteger pick) {
            ACGSetPreferenceObject(@"ACG.Preference.Tabs.GlassMode", @(pick));
            [weakSelf buildSettings];
            ACGRefreshPivotBarBackground();
            AutoACRestartHint();
        });
        [self.settingRows addObject:[self settingRowWithTitle:AutoACT(@"Kiểu thanh tab") detail:AutoACT(@"Mặc định hoặc Glass") accessory:glassPill tap:nil]];
        [self.settingRows addObject:[self settingRowWithTitle:AutoACT(@"Bật thu gọn") detail:AutoACT(@"Thu nhỏ khi cuộn")
            accessory:[self switchForKey:@"ACG.Preference.Tabs.GlassMinimize" on:[ACGPreferenceObject(@"ACG.Preference.Tabs.GlassMinimize") boolValue]] tap:nil]];
#endif
        [self.settingRows addObject:[self settingRowWithTitle:AutoACT(@"Kính lỏng thanh trên") detail:AutoACT(@"Nút tìm kiếm, thông báo, quay lại")
            accessory:[self switchForKey:kGlassTopKey on:[kPrefs boolForKey:kGlassTopKey]] tap:nil]];
        [self.settingRows addObject:[self settingRowWithTitle:AutoACT(@"Kính lỏng bảng chọn") detail:AutoACT(@"Bảng, menu và hộp thoại")
            accessory:[self switchForKey:kGlassSheetKey on:[kPrefs boolForKey:kGlassSheetKey]] tap:nil]];
        [self.settingRows addObject:[self settingRowWithTitle:AutoACT(@"Kính lỏng trình phát") detail:AutoACT(@"Nút nổi trên video")
            accessory:[self switchForKey:kGlassPlayerKey on:[kPrefs boolForKey:kGlassPlayerKey]] tap:nil]];
    }
#if ACG_TAB_GLASS_ENABLED
    [self.settingRows addObject:[self settingRowWithTitle:AutoACT(@"Shorts tràn xuống thanh tab") detail:AutoACT(@"Dock trong suốt, không dải trắng/đen")
        accessory:[self switchForKey:kShortsFullBleedKey on:[kPrefs boolForKey:kShortsFullBleedKey]] tap:nil]];
#endif

    // ── Nhãn, màu, tab khi mở app ──
    [self.settingRows addObject:[self settingRowWithTitle:AutoACT(@"Bật nhãn") detail:AutoACT(@"Hiện tên dưới icon")
        accessory:[self switchForKey:@"ACG.Preference.Tabs.LabelsHidden" on:![ACGPreferenceObject(@"ACG.Preference.Tabs.LabelsHidden") boolValue]] tap:nil]];

    NSArray<NSString *> *tintTitles = @[AutoACT(@"Tắt"), AutoACT(@"Chỉ chữ"), @"Icon-text"];
    UIView *tintPill = ACGValueMenu(tintTitles[ACGTintIndex()], tintTitles, ACGTintIndex(), ^(NSUInteger pick) {
        ACGSetPreferenceObject(@"ACG.Preference.Tabs.SelectedTint", @(pick));
        [weakSelf buildSettings];
        ACGRefreshPivotBarBackground();
    });
    [self.settingRows addObject:[self settingRowWithTitle:AutoACT(@"Kiểu màu tab") detail:AutoACT(@"Màu chữ, icon tab chọn") accessory:tintPill tap:nil]];

    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
    dot.backgroundColor = ACGTintSwatchColor();
    dot.layer.cornerRadius = 14.0;
    dot.layer.borderWidth = 2.0;
    dot.layer.borderColor = UIColor.secondaryLabelColor.CGColor;
    [self.settingRows addObject:[self settingRowWithTitle:AutoACT(@"Kiểu màu") detail:AutoACT(@"Màu tab đang chọn") accessory:dot tap:@selector(pickTintColor)]];

    NSArray<NSString *> *startTitles = nil, *startValues = nil;
    ACGStartupDestinations(&startTitles, &startValues);
    NSUInteger startIndex = [startValues indexOfObject:ACGPreferenceObject(@"ACG.Preference.Tabs.Startup") ?: @""];
    NSUInteger startCur = (startIndex != NSNotFound && startIndex < startTitles.count) ? startIndex : 0;
    UIView *startPill = ACGValueMenu(startTitles[startCur], startTitles, startCur, ^(NSUInteger pick) {
        ACGSetPreferenceObject(@"ACG.Preference.Tabs.Startup", startValues[pick]);
        [weakSelf buildSettings];
        AutoACRestartHint();
    });
    [self.settingRows addObject:[self settingRowWithTitle:AutoACT(@"Tab khi mở app") detail:AutoACT(@"Tab hiện khi mở app") accessory:startPill tap:nil]];

    for (UIView *row in self.settingRows) [self.settingsCard addSubview:row];
    [self setNeedsLayout];
}

- (void)pickTintColor {
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.title = AutoACT(@"Kiểu màu");
    picker.supportsAlpha = NO;
    picker.selectedColor = ACGTintSwatchColor();
    picker.delegate = self;
    [AutoACTopViewController() presentViewController:picker animated:YES completion:nil];
}

- (void)saveTintColor:(UIColor *)color {
    if (!color) return;
    ACGSetPreferenceObject(@"ACG.Preference.Tabs.SelectedTintColor", ACGTintHexFromColor(color));
    [self buildSettings];
    ACGRefreshPivotBarBackground();
}
- (void)colorPickerViewController:(UIColorPickerViewController *)viewController didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    if (!continuously) [self saveTintColor:color];
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController { [self saveTintColor:viewController.selectedColor]; }

#pragma mark Bố cục

- (NSInteger)slotsInStrip:(NSInteger)s {
    if (self.frozenSlots) return self.frozenSlots[(NSUInteger)s].integerValue;
    return (NSInteger)self.lists[(NSUInteger)s].count;
}

- (CGFloat)stripHeight:(NSInteger)s perRow:(NSInteger)perRow {
    NSInteger rows = MAX(1, ((NSInteger)[self slotsInStrip:s] + perRow - 1) / perRow);
    return rows * kTabRowPitch + 8.0;
}

static const CGFloat kTabSettingRow = 52.0;

// Thứ tự từ trên xuống: nhóm Liquid glass, hai dải tab (đang hiện / đang ẩn), thẻ chi tiết, chú thích
- (CGFloat)layoutFrames:(BOOL)apply {
    CGFloat width = CGRectGetWidth(self.bounds) > 0 ? CGRectGetWidth(self.bounds) : 320.0, y = 4;
    NSInteger perRow = 6;
    ACGTabMetrics(width, &perRow, NULL, NULL);

    // 1) Liquid glass
    if (apply) {
        self.settingsTitle.frame = CGRectMake(2, y, 240, 24);
        self.settingsCard.frame = CGRectMake(0, y + 28, width, self.settingRows.count * kTabSettingRow);
        for (NSUInteger i = 0; i < self.settingRows.count; i++) {
            UIView *row = self.settingRows[i];
            row.frame = CGRectMake(0, i * kTabSettingRow, width, kTabSettingRow);
            UIView *accessory = [row viewWithTag:103];
            CGFloat aw = 0;
            if (accessory) {
                BOOL isSwitch = [accessory isKindOfClass:UISwitch.class];
                CGSize size = isSwitch ? CGSizeMake(51, 31) : (CGRectGetWidth(accessory.bounds) == 28 ? CGSizeMake(28, 28) : CGSizeMake(112, 28));
                accessory.bounds = CGRectMake(0, 0, size.width, size.height);
                accessory.center = CGPointMake(width - 14 - size.width / 2, kTabSettingRow / 2);
                aw = size.width;
            }
            CGFloat tw = MAX(width - 16 - aw - 28, 60);
            [row viewWithTag:101].frame = CGRectMake(16, 7, tw, 20);
            [row viewWithTag:102].frame = CGRectMake(16, 28, tw, 16);
            if (i > 0) {
                UIView *line = [row viewWithTag:104];
                if (!line) {
                    line = [[UIView alloc] init];
                    line.tag = 104;
                    line.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.10];
                    [row addSubview:line];
                }
                line.frame = CGRectMake(16, 0, width - 32, 0.5);
            }
        }
    }
    y += 28 + self.settingRows.count * kTabSettingRow + 16;

    // 2) Hai dải tab
    for (NSInteger s = 0; s < 2; s++) {
        CGFloat h = [self stripHeight:s perRow:perRow];
        if (apply) {
            NSArray *parts = self.headerParts[(NSUInteger)s];
            ((UIView *)parts[0]).frame = CGRectMake(0, y + 4, 20, 20);
            ((UIView *)parts[1]).frame = CGRectMake(26, y, 120, 28);
            ((UIView *)parts[2]).frame = CGRectMake(width - 170, y, 170, 28);
            UIView *strip = self.strips[(NSUInteger)s];
            strip.frame = CGRectMake(0, y + 30, width, h);
            self.hints[(NSUInteger)s].frame = CGRectMake(0, 0, width, kTabRowPitch);
        }
        y += 30 + h + 12;
    }

    // 3) Thẻ chi tiết: hàng 1 tên và trạng thái; hàng 2 hai nút kính cùng cỡ (Hiện/Ẩn và Đổi tên tab)
    CGFloat detailHeight = 114;
    if (apply) {
        self.detail.frame = CGRectMake(0, y, width, detailHeight);
        self.detailDisc.frame = CGRectMake(14, 12, 36, 36);
        self.detailTitle.frame = CGRectMake(62, 11, MAX(width - 62 - 14, 40), 22);
        self.detailCaption.frame = CGRectMake(62, 33, MAX(width - 62 - 14, 40), 16);
        CGFloat pillWidth = floor((width - 28 - 10) / 2.0), pillHeight = 36;
        self.pill.frame = CGRectMake(14, 62, pillWidth, pillHeight);
        self.renameButton.frame = CGRectMake(14 + pillWidth + 10, 62, pillWidth, pillHeight);
    }
    y += detailHeight + 14;

    // 4) Chú thích
    CGSize fit = [self.footer sizeThatFits:CGSizeMake(MAX(width - 4, 10), CGFLOAT_MAX)];
    if (apply) self.footer.frame = CGRectMake(2, y, MAX(width - 4, 10), ceil(fit.height));
    return y + ceil(fit.height) + 8;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat total = [self layoutFrames:YES];
    [self layoutChipsAnimated:NO];
    NSLayoutConstraint *c = self.heightConstraint;
    if (c && fabs(c.constant - total) > 0.5) {
        c.constant = total;
        dispatch_async(dispatch_get_main_queue(), ^{ [self.superview setNeedsLayout]; });
    }
}

- (CGPoint)slotOrigin:(NSInteger)slot strip:(NSInteger)s perRow:(NSInteger)perRow gap:(CGFloat)gap chipWidth:(CGFloat)chipWidth {
    CGFloat top = CGRectGetMinY(self.strips[(NSUInteger)s].frame) + 4.0;
    NSInteger row = slot / perRow, col = slot % perRow;
    return CGPointMake(12 + col * (chipWidth + gap), top + row * kTabRowPitch);
}

- (void)placeChip:(AutoACOverlayChip *)chip frame:(CGRect)frame animated:(BOOL)animated {
    if (chip.tag == 0) { chip.frame = frame; chip.tag = 1; return; }
    if (CGRectEqualToRect(chip.frame, frame)) return;
    if (!animated) { chip.frame = frame; return; }
    [UIView animateWithDuration:0.26 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ chip.frame = frame; } completion:nil];
}

- (void)layoutChipsAnimated:(BOOL)animated {
    CGFloat width = CGRectGetWidth(self.bounds);
    if (width <= 0) return;
    NSInteger perRow = 6;
    CGFloat gap = 4, chipWidth = 48;
    ACGTabMetrics(width, &perRow, &gap, &chipWidth);
    NSString *dragKey = self.dragChip ? ACGTabKey([self boardStripOf:self.dragChip], self.dragChip.ident) : nil;
    for (NSInteger s = 0; s < 2; s++) {
        NSMutableArray<AutoACOverlayChip *> *items = [NSMutableArray array];
        for (NSString *ident in self.lists[(NSUInteger)s]) {
            NSString *key = ACGTabKey(s, ident);
            if ([key isEqualToString:dragKey]) continue;
            AutoACOverlayChip *chip = self.chips[key];
            if (chip) [items addObject:chip];
        }
        BOOL hasHole = self.dragChip != nil && self.holeStrip == s;
        self.hints[(NSUInteger)s].hidden = (items.count + (hasHole ? 1 : 0)) > 0;
        NSInteger slot = 0;
        for (NSInteger i = 0; i <= (NSInteger)items.count; i++) {
            if (hasHole && i == self.holeIndex) slot++;
            if (i == (NSInteger)items.count) break;
            CGPoint o = [self slotOrigin:slot strip:s perRow:perRow gap:gap chipWidth:chipWidth];
            slot++;
            [self placeChip:items[(NSUInteger)i] frame:CGRectMake(o.x, o.y, chipWidth, kTabChipHeight) animated:animated];
        }
    }
}

- (NSInteger)boardStripOf:(AutoACOverlayChip *)chip { return chip.strip == 0 ? 0 : 1; }   // nút dải hiện dùng màu dải 0, dải ẩn dùng màu dải 2

#pragma mark Dựng nút

- (void)reloadChipsAnimated:(BOOL)animated {
    for (AutoACOverlayChip *chip in self.chips.allValues) [chip removeFromSuperview];
    [self.chips removeAllObjects];
    [self rebuildAnimated:animated];
}

- (void)rebuildAnimated:(BOOL)animated {
    NSMutableSet<NSString *> *wanted = [NSMutableSet set];
    for (NSInteger s = 0; s < 2; s++) {
        for (NSString *ident in self.lists[(NSUInteger)s]) {
            NSString *key = ACGTabKey(s, ident);
            [wanted addObject:key];
            if (self.chips[key]) continue;
            NSDictionary *entry = ACGTabEntry(ident);
            if (!entry) continue;
            NSMutableDictionary *shown = [entry mutableCopy];
            shown[@"title"] = ACGTabDisplayName(entry);
            AutoACOverlayChip *chip = [[AutoACOverlayChip alloc] initWithEntry:shown strip:s == 0 ? 0 : 2];
            UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlePress:)];
            press.minimumPressDuration = 0.2;
            [chip addGestureRecognizer:press];
            [chip addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)]];
            [self addSubview:chip];
            self.chips[key] = chip;
            if (animated) { chip.alpha = 0; [UIView animateWithDuration:0.2 animations:^{ chip.alpha = 1; }]; }
        }
    }
    for (NSString *key in self.chips.allKeys) {
        AutoACOverlayChip *chip = self.chips[key];
        if ([wanted containsObject:key] || chip == self.dragChip) continue;
        [self.chips removeObjectForKey:key];
        [UIView animateWithDuration:animated ? 0.18 : 0 animations:^{ chip.alpha = 0; } completion:^(BOOL finished) { [chip removeFromSuperview]; }];
    }
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [self layoutChipsAnimated:animated];
    [self refreshPicked];
    [self refreshDetail];
}

- (void)refreshPicked {
    for (AutoACOverlayChip *chip in self.chips.allValues) chip.picked = [chip.ident isEqualToString:self.selectedIdent];
}

- (void)refreshDetail {
    NSDictionary *entry = ACGTabEntry(self.selectedIdent);
    self.detailTitle.text = entry ? ACGTabDisplayName(entry) : @"";
    BOOL shown = [self.lists[0] containsObject:self.selectedIdent];
    self.detailCaption.text = shown ? AutoACT(@"Đang hiện trên thanh tab") : AutoACT(@"Đang ẩn");
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium];
    self.detailIcon.image = entry ? [UIImage systemImageNamed:entry[@"symbol"] withConfiguration:cfg] : nil;
    self.detailDisc.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:shown ? 0.14 : 0.08];
    NSArray<NSString *> *titles = @[AutoACT(@"Hiện"), AutoACT(@"Ẩn")];
    NSUInteger position = shown ? 0 : 1;
    [self.pill removeFromSuperview];
    __weak ACGTabBoard *weakSelf = self;
    UIView *pill = ACGValueMenu([titles[position] stringByAppendingString:@" ▾"], titles, position, ^(NSUInteger index) { [weakSelf applyVisibility:index == 0]; });
    [self.detail addSubview:pill];
    self.pill = pill;
    [self setNeedsLayout];
}

#pragma mark Thao tác

- (void)select:(NSString *)ident {
    if (!ident || [ident isEqualToString:self.selectedIdent]) return;
    self.selectedIdent = ident;
    [self refreshPicked];
    [self refreshDetail];
}

- (void)handleTap:(UITapGestureRecognizer *)g {
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self select:((AutoACOverlayChip *)g.view).ident];
}

// Hiện / Ẩn tab đang chọn bằng nút kính (tab chuyển xuống cuối dải kia)
- (void)applyVisibility:(BOOL)show {
    NSString *ident = self.selectedIdent;
    if (!ident) return;
    NSInteger from = show ? 1 : 0, to = show ? 0 : 1;
    if (![self.lists[(NSUInteger)from] containsObject:ident]) return;
    [self.lists[(NSUInteger)from] removeObject:ident];
    [self.lists[(NSUInteger)to] addObject:ident];
    [self persist];
    [self reloadChipsAnimated:YES];
}

- (void)renameTapped {
    NSDictionary *entry = ACGTabEntry(self.selectedIdent);
    if (!entry) return;
    NSString *token = entry[@"id"];
    NSDictionary *names = [kPrefs dictionaryForKey:@"ACG.Preference.Tabs.Names"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:AutoACT(@"Đổi tên tab")
        message:AutoACT(@"Để trống để dùng lại tên mặc định.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = entry[@"title"];
        field.text = names[token];
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:AutoACT(@"Huỷ") style:UIAlertActionStyleCancel handler:nil]];
    __weak ACGTabBoard *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:AutoACT(@"Lưu") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSMutableDictionary *updated = [names mutableCopy] ?: [NSMutableDictionary dictionary];
        NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (value.length == 0) [updated removeObjectForKey:token]; else updated[token] = value;
        [kPrefs setObject:updated forKey:@"ACG.Preference.Tabs.Names"];
        [NSNotificationCenter.defaultCenter postNotificationName:ACGTabConfigChangedNote object:nil];
        [weakSelf reloadChipsAnimated:NO];
    }]];
    [AutoACTopViewController() presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)stripAtY:(CGFloat)y {
    NSInteger best = 0;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSInteger s = 0; s < 2; s++) {
        CGRect frame = self.strips[(NSUInteger)s].frame;
        CGFloat distance = y < CGRectGetMinY(frame) ? CGRectGetMinY(frame) - y : (y > CGRectGetMaxY(frame) ? y - CGRectGetMaxY(frame) : 0);
        if (distance < bestDistance) { bestDistance = distance; best = s; }
    }
    return best;
}

// Vị trí chèn gần điểm chạm nhất, tính trên bố cục KHÔNG có chỗ trống (chỗ trống không làm các nút nhảy qua lại)
- (NSInteger)slotAtPoint:(CGPoint)p inStrip:(NSInteger)strip {
    NSString *dragKey = ACGTabKey([self boardStripOf:self.dragChip], self.dragChip.ident);
    NSInteger count = 0;
    for (NSString *ident in self.lists[(NSUInteger)strip]) if (![ACGTabKey(strip, ident) isEqualToString:dragKey]) count++;
    NSInteger perRow = 6;
    CGFloat gap = 4, chipWidth = 48;
    ACGTabMetrics(CGRectGetWidth(self.bounds), &perRow, &gap, &chipWidth);
    NSInteger best = 0;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (NSInteger i = 0; i <= count; i++) {
        CGPoint o = [self slotOrigin:i strip:strip perRow:perRow gap:gap chipWidth:chipWidth];
        CGFloat dx = p.x - (o.x + chipWidth / 2), dy = p.y - (o.y + kTabChipHeight / 2);
        CGFloat d = dx * dx + dy * dy;
        if (d < bestDistance) { bestDistance = d; best = i; }
    }
    return best;
}

- (void)highlightStrip:(NSInteger)target {
    [UIView animateWithDuration:0.15 animations:^{
        for (NSInteger s = 0; s < 2; s++) {
            UIColor *tint = ACGTabStripColor(s);
            BOOL on = s == target;
            self.strips[(NSUInteger)s].backgroundColor = [tint colorWithAlphaComponent:on ? 0.11 : 0.05];
            self.strips[(NSUInteger)s].layer.borderColor = [tint colorWithAlphaComponent:on ? 0.55 : 0.14].CGColor;
        }
    }];
}

- (void)handlePress:(UILongPressGestureRecognizer *)g {
    AutoACOverlayChip *chip = (AutoACOverlayChip *)g.view;
    CGPoint p = [g locationInView:self];
    switch (g.state) {
        case UIGestureRecognizerStateBegan: {
            if (self.dragChip) return;
            [[UIImpactFeedbackGenerator new] impactOccurred];
            [self select:chip.ident];
            NSInteger origin = [self boardStripOf:chip];
            // giữ nguyên số ô mỗi dải trong lúc kéo: dải gốc đang có đủ chỗ, dải kia chừa thêm một ô cho nút được thả vào
            NSMutableArray<NSNumber *> *frozen = [NSMutableArray array];
            for (NSInteger s = 0; s < 2; s++) [frozen addObject:@((NSInteger)self.lists[(NSUInteger)s].count + (s == origin ? 0 : 1))];
            self.frozenSlots = frozen;
            self.dragChip = chip;
            self.grab = CGPointMake(p.x - chip.center.x, p.y - chip.center.y);
            self.holeStrip = origin;
            NSUInteger at = [self.lists[(NSUInteger)origin] indexOfObject:chip.ident];
            self.holeIndex = at == NSNotFound ? 0 : (NSInteger)at;
            self.scroll.scrollEnabled = NO;
            [self bringSubviewToFront:chip];
            chip.layer.shadowColor = UIColor.blackColor.CGColor;
            chip.layer.shadowOpacity = 0.35;
            chip.layer.shadowRadius = 8;
            chip.layer.shadowOffset = CGSizeMake(0, 4);
            [UIView animateWithDuration:0.18 animations:^{ chip.transform = CGAffineTransformMakeScale(1.14, 1.14); }];
            [self highlightStrip:self.holeStrip];
            [self setNeedsLayout];
            [self layoutIfNeeded];
            [self layoutChipsAnimated:YES];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (chip != self.dragChip) return;
            chip.center = CGPointMake(p.x - self.grab.x, p.y - self.grab.y);
            NSInteger strip = [self stripAtY:p.y];
            NSInteger slot = [self slotAtPoint:p inStrip:strip];
            if (strip != self.holeStrip || slot != self.holeIndex) {
                self.holeStrip = strip;
                self.holeIndex = slot;
                [self highlightStrip:strip];
                [self layoutChipsAnimated:YES];
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
            [self finishDrag:YES];
            break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self finishDrag:NO];
            break;
        default:
            break;
    }
}

- (void)finishDrag:(BOOL)commit {
    AutoACOverlayChip *chip = self.dragChip;
    if (!chip) return;
    NSInteger from = [self boardStripOf:chip];
    NSString *ident = chip.ident;
    self.scroll.scrollEnabled = YES;
    [self highlightStrip:-1];
    CGPoint center = chip.center;
    chip.transform = CGAffineTransformIdentity;
    chip.center = center;
    chip.layer.shadowOpacity = 0;
    self.dragChip = nil;
    self.frozenSlots = nil;
    if (commit) {
        NSInteger to = self.holeStrip, index = self.holeIndex;
        [self.lists[(NSUInteger)from] removeObject:ident];
        NSMutableArray<NSString *> *dest = self.lists[(NSUInteger)to];
        [dest insertObject:ident atIndex:MIN((NSUInteger)MAX(index, 0), dest.count)];
        [self persist];
        [[UIImpactFeedbackGenerator new] impactOccurred];
        [self reloadChipsAnimated:NO];   // đổi dải thì đổi màu nút: dựng lại cho gọn
    } else {
        [self rebuildAnimated:YES];
    }
}

@end

static ACGTabBoard *gACGTabBoard;   // giữ bảng khi khung đang mở

static void ACGPresentTabEditor(void) {
    UIWindow *window = AutoACKeyWindow();
    if (!window || gMenu) return;
    ACGTabBoard *board = [[ACGTabBoard alloc] initWithFrame:CGRectMake(0, 0, 320, 900)];
    gACGTabBoard = board;
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.delaysContentTouches = NO;
    scroll.alwaysBounceVertical = NO;
    board.scroll = scroll;
    board.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:board];
    UIView *holder = [[UIView alloc] init];
    holder.translatesAutoresizingMaskIntoConstraints = NO;
    [holder addSubview:scroll];
    NSLayoutConstraint *boardHeight = [board.heightAnchor constraintEqualToConstant:900];
    board.heightConstraint = boardHeight;
    NSLayoutConstraint *wish = [holder.heightAnchor constraintEqualToConstant:4000];   // muốn cao tối đa, khung tự giới hạn theo màn hình
    wish.priority = UILayoutPriorityDefaultLow;
    [NSLayoutConstraint activateConstraints:@[
        wish, boardHeight,
        [scroll.topAnchor constraintEqualToAnchor:holder.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor constant:-16],
        [board.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [board.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [board.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [board.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [board.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];
    // Nút khôi phục: icon kính tròn bên phải đầu khung; hai chạm để tránh lỡ tay làm mất bố cục đã sắp
    AutoACShowPanel(AutoACT(@"Tuỳ chỉnh tab"), AutoACT(@"Thứ tự, ẩn hiện, Liquid Glass"), holder, window.safeAreaInsets.top + 12,
                    AutoACT(@"Khôi phục tab mặc định"), ^{
        static CFTimeInterval armedAt = 0;
        CFTimeInterval now = CACurrentMediaTime();
        if (armedAt > 0 && now - armedAt < 4.0) {
            armedAt = 0;
            [gACGTabBoard restoreYouTubeDefaults];
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
            AutoACShowHub(@"arrow.counterclockwise", UIColor.systemGreenColor, AutoACT(@"Đã khôi phục tab mặc định"), nil, 2.0);
            return;
        }
        armedAt = now;
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeWarning];
        AutoACShowHub(@"arrow.counterclockwise", UIColor.systemOrangeColor, AutoACT(@"Chạm lần nữa để khôi phục tab"), AutoACT(@"Trong 4 giây"), 3.0);
    });
}


#pragma mark - Dung lượng ứng dụng

// Ghi chú ngắn cho từng thư mục lớn để biết mục nào dọn được
static NSString *AutoACStorageHint(NSString *path) {
    if ([path hasPrefix:@"Library/Caches"]) return AutoACT(@"Cache: Dọn cache ngay xoá được phần cũ");
    if ([path hasPrefix:@"Library/WebKit"]) return AutoACT(@"Dữ liệu web (đăng nhập, bộ nhớ trang)");
    if ([path hasPrefix:@"Library/Application Support"]) return AutoACT(@"Dữ liệu của app");
    if ([path hasPrefix:@"Library/Saved Application State"]) return AutoACT(@"Ảnh chụp trạng thái app");
    if ([path hasPrefix:@"Documents"]) return AutoACT(@"Tệp của app (video đã tải, cơ sở dữ liệu)");
    if ([path hasPrefix:@"tmp"]) return AutoACT(@"Tệp tạm");
    return nil;
}

static UIView *AutoACStorageRow(NSString *size, NSString *path) {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.06];
    card.layer.cornerRadius = 14;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    UILabel *sizeLabel = AutoACLabel(size, 15, UIFontWeightBold, UIColor.systemTealColor);
    sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    sizeLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightBold];
    [sizeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [sizeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [sizeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:70].active = YES;
    UILabel *pathLabel = AutoACLabel(path, 13, UIFontWeightMedium, UIColor.labelColor);
    pathLabel.numberOfLines = 0;
    NSString *hint = AutoACStorageHint(path);
    UILabel *hintLabel = AutoACLabel(hint ?: @"", 11.5, UIFontWeightRegular, UIColor.secondaryLabelColor);
    hintLabel.numberOfLines = 0;
    hintLabel.hidden = hint == nil;
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[pathLabel, hintLabel]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 2;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[sizeLabel, text]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentTop;
    row.spacing = 12;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
    ]];
    return card;
}

// Khung xem dung lượng: mở thẳng từ menu (không cần vào trang (i) hay bật Chẩn đoán)
static void AutoACPresentStoragePanel(void) {
    UIWindow *window = AutoACKeyWindow();
    if (!window || gMenu) return;
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.layoutMarginsRelativeArrangement = YES;
    stack.layoutMargins = UIEdgeInsetsMake(4, 16, 16, 16);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    NSLayoutConstraint *wish = [scroll.heightAnchor constraintEqualToConstant:470];
    wish.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        wish,
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];
    void (^fill)(void) = ^{
        for (UIView *v in [stack.arrangedSubviews copy]) { [stack removeArrangedSubview:v]; [v removeFromSuperview]; }
        NSString *report = gStorageReport;
        if (!report) {
            [stack addArrangedSubview:AutoACLabel(AutoACT(@"Đang tính…"), 14, UIFontWeightMedium, UIColor.secondaryLabelColor)];
            return;
        }
        NSMutableArray<NSString *> *lines = [[report componentsSeparatedByString:@"\n"] mutableCopy];
        NSString *first = lines.firstObject ?: @"";
        if (lines.count) [lines removeObjectAtIndex:0];
        NSRange tr = [first rangeOfString:@"  "];
        NSString *total = tr.location == NSNotFound ? first : [first substringToIndex:tr.location];
        [stack addArrangedSubview:AutoACLabel(total, 34, UIFontWeightBold, UIColor.labelColor)];
        UILabel *caption = AutoACLabel(AutoACT(@"Tổng dung lượng thư mục dữ liệu của YouTube trên máy (Documents, Library, tmp). Các mục lớn nhất:"), 12, UIFontWeightRegular, UIColor.secondaryLabelColor);
        caption.numberOfLines = 0;
        [stack addArrangedSubview:caption];
        [stack setCustomSpacing:12 afterView:caption];
        BOOL any = NO;
        for (NSString *line in lines) {
            NSRange r = [line rangeOfString:@"  "];
            if (r.location == NSNotFound) continue;
            [stack addArrangedSubview:AutoACStorageRow([line substringToIndex:r.location], [line substringFromIndex:r.location + 2])];
            any = YES;
        }
        if (!any) [stack addArrangedSubview:AutoACLabel(AutoACT(@"Không có mục nào từ 20 MB trở lên."), 13, UIFontWeightRegular, UIColor.secondaryLabelColor)];
    };
    fill();
    AutoACShowPanel(AutoACT(@"Dung lượng ứng dụng"), AutoACT(@"Mục lớn nhất trong thư mục của YouTube"), scroll, window.safeAreaInsets.top + 12,
                    AutoACT(@"Tính lại"), ^{
        gStorageReport = nil;
        fill();
        AutoACRefreshStorageReportForce(YES, fill);
    });
    AutoACRefreshStorageReportForce(NO, fill);
}

static NSArray<AutoACItem *> *AutoACBuildItems(void) {
    NSMutableArray<AutoACItem *> *items = [NSMutableArray array];
    void (^restart)(void) = ^{ AutoACRestartHint(); };

    // ── Tác vụ nhanh ──
    [items addObject:ACAction(AutoACT(@"Dọn cache ngay"), AutoACT(@"Đang tính…"), @"trash.fill", UIColor.systemBlueColor,
        AutoACT(@"Xoá các tệp cache không còn dùng của YouTube, giữ nguyên dữ liệu đăng nhập, rồi báo dung lượng đã giải phóng. Dọn cache tự động chỉ xoá tệp cũ hơn 30 phút. Không ảnh hưởng video đã tải hay cài đặt."),
        ^{ AutoACDismissMenu(); AutoACRunCleanup(YES); })];
    [items addObject:ACAction(AutoACT(@"Dung lượng ứng dụng"), AutoACT(@"Thư mục nào đang chiếm bộ nhớ"), @"internaldrive.fill", UIColor.systemIndigoColor,
        AutoACT(@"Xem tổng dung lượng thư mục dữ liệu của YouTube và các mục lớn nhất (Documents, Caches, WebKit…), kèm ghi chú mục nào dọn được. Mở thẳng từ đây, không cần vào trang (i) hay bật Chẩn đoán."),
        ^{ AutoACDismissMenu(); AutoACPresentStoragePanel(); })];
    [items addObject:ACAction(AutoACT(@"Đặt lại cài đặt"), AutoACT(@"Khôi phục mặc định"), @"arrow.counterclockwise", UIColor.systemRedColor,
        AutoACT(@"Đưa toàn bộ tuỳ chọn của AutoAC về giá trị mặc định. Cần mở lại app để áp dụng."),
        ^{   // hai chạm: chạm đầu để xác nhận, chạm thứ hai (trong 4 giây) mới đặt lại
            static CFTimeInterval armedAt = 0;
            CFTimeInterval now = CACurrentMediaTime();
            if (armedAt > 0 && now - armedAt < 4.0) {
                armedAt = 0;
                for (NSString *k in AutoACAllPrefKeys()) [kPrefs removeObjectForKey:k];
                for (NSString *k in kPrefs.dictionaryRepresentation.allKeys) if ([k hasPrefix:@"ACG.Preference."]) [kPrefs removeObjectForKey:k];
                AutoACDismissMenu();
                AutoACRestartHint();
                return;
            }
            armedAt = now;
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeWarning];
            AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemRedColor, AutoACT(@"Chạm lần nữa để đặt lại"), AutoACT(@"Trong 4 giây"), 3.0);
        })];
    [items addObject:ACAction(AutoACT(@"Sao lưu cài đặt"), AutoACT(@"Xuất ra tệp"), @"square.and.arrow.up.fill", UIColor.systemBlueColor,
        AutoACT(@"Xuất toàn bộ cài đặt của AutoAC (kể cả thanh tab) ra một tệp .plist để lưu vào Tệp hoặc gửi đi. Dùng Khôi phục cài đặt để nhập lại."),
        ^{ AutoACDismissMenu(); AutoACExportSettings(); })];
    [items addObject:ACAction(AutoACT(@"Khôi phục cài đặt"), AutoACT(@"Nhập từ tệp"), @"square.and.arrow.down.fill", UIColor.systemGreenColor,
        AutoACT(@"Chọn tệp .plist đã sao lưu để khôi phục cài đặt của AutoAC. Chỉ nhận các tuỳ chọn của AutoAC. Cần mở lại app để áp dụng."),
        ^{ AutoACDismissMenu(); AutoACImportSettings(); })];
    [items addObject:ACAction(AutoACT(@"Sao chép"), AutoACT(@"Liên kết, tiêu đề, mô tả"), @"doc.on.doc.fill", UIColor.systemTealColor,
        AutoACT(@"Mở từ nút Tải xuống. Sao chép liên kết ngắn, liên kết tại thời điểm đang xem, tiêu đề, mô tả, hoặc phụ đề (thường, kèm thời gian, dịch sang tiếng Việt, có thể lưu thành tệp .txt)."),
        ^{ AutoACDismissMenu(); AutoACShowCopyMenu(); })];
    [items addObject:ACAction(AutoACT(@"Tốc độ và tua"), AutoACT(@"Mở video, chạm đúp"), @"speedometer", UIColor.systemTealColor,
        AutoACT(@"Chọn tốc độ phát khi mở video (0.5x đến 3x) và số giây tua khi chạm đúp (5 đến 60 giây). Chọn Theo YouTube để dùng mặc định."),
        ^{ AutoACDismissMenu(); AutoACShowPlaybackSettings(); })];
    [items addObject:ACAction(AutoACT(@"Lưu ảnh bìa"), AutoACT(@"Vào Ảnh"), @"photo.fill", UIColor.systemYellowColor,
        AutoACT(@"Mở từ nút Tải xuống. Lưu ảnh bìa độ phân giải cao nhất của video hoặc Short đang xem vào thư viện Ảnh."),
        ^{ AutoACDismissMenu(); AutoACSaveThumbnail(); })];
    [items addObject:ACAction(AutoACT(@"Tải âm thanh"), @"M4A", @"waveform", UIColor.systemPinkColor,
        AutoACT(@"Mở từ nút Tải xuống. Tải âm thanh chất lượng cao nhất (M4A) của video hoặc Short đang xem, rồi lưu vào Tệp hoặc app khác qua bảng chia sẻ."),
        ^{ AutoACDismissMenu(); AutoACStartDownload(YES); })];
    [items addObject:ACAction(AutoACT(@"Tải video"), @"MP4", @"arrow.down.circle.fill", UIColor.systemGreenColor,
        AutoACT(@"Mở từ nút Tải xuống. Tải video hoặc Short đang xem kèm âm thanh (MP4, H.264). Có thể chọn chất lượng và nơi lưu (Ảnh hoặc bảng chia sẻ) trước khi tải."),
        ^{ AutoACDismissMenu(); AutoACStartDownload(NO); })];

    // ── Bộ nhớ ──
    [items addObject:ACSwitch(AutoACT(@"Bộ nhớ"), AutoACT(@"Dọn cache tự động"), AutoACT(@"Khi thoát app"), @"arrow.triangle.2.circlepath",
        UIColor.systemGreenColor, kAutoClearCacheKey,
        AutoACT(@"Tự xoá cache và tệp tạm của YouTube cũ quá 30 phút mỗi khi thoát app. Không đụng tới video đã tải hay cài đặt."), nil)];

    // ── Giao diện ──

    // ── Phát lại ──
#if TWEAK_UPSTREAM_YOUTUBEX_GATED
    [items addObject:ACSwitch(AutoACT(@"Phát lại"), AutoACT(@"Phát nền"), AutoACT(@"Khi tắt màn hình"), @"headphones",
        UIColor.systemPurpleColor, kYTXBackgroundKey,
        AutoACT(@"Tiếp tục phát khi thoát app hoặc tắt màn hình (YouTube X). Cần mở lại app."), restart)];
    [items addObject:ACSwitch(AutoACT(@"Quảng cáo"), AutoACT(@"Chặn quảng cáo"), AutoACT(@"Video, trang chủ, Shorts"), @"shield.lefthalf.filled",
        UIColor.systemRedColor, kYTXAdsKey,
        AutoACT(@"Chặn quảng cáo trong video, trang chủ và Shorts (YouTube X). Cần mở lại app."), restart)];
#endif

    [items addObject:ACAction(AutoACT(@"Tuỳ chỉnh Overlay"), AutoACT(@"Nút trên trình phát"), @"slider.horizontal.3", UIColor.systemTealColor,
        AutoACT(@"Chọn và sắp xếp các nút AutoAC trên trình phát (tải xuống, tốc độ, PiP, hẹn giờ, phát ngoài): đặt ở hàng trên (dưới nút bánh răng) hoặc hàng dưới (cạnh nút toàn màn hình), kéo để đổi thứ tự hoặc chuyển hàng, hoặc tắt hẳn từng nút. Nhấn giữ biểu tượng Tốc độ để về tốc độ gốc. Nút tải chỉ áp dụng trong video; nút tải trong Shorts luôn bật."),
        ^{ AutoACDismissMenu(); AutoACPresentOverlayEditor(); })];
    items.lastObject.category = AutoACT(@"Phát lại");
    items.lastObject.inlineRow = YES;
    [items addObject:ACSwitch(AutoACT(@"Phát lại"), AutoACT(@"Tắt lặp Short"), AutoACT(@"Không phát lặp lại một Short"), @"repeat.1",
        UIColor.systemOrangeColor, kShortsNoLoopKey,
        AutoACT(@"Short phát hết sẽ không lặp lại. Nếu Tắt cuộn Short đang tắt thì tự chuyển sang Short kế tiếp; nếu Tắt cuộn Short đang bật thì dừng lại ở cuối Short."), nil)];
    [items addObject:ACSwitch(AutoACT(@"Phát lại"), AutoACT(@"Tắt lỗi phát"), AutoACT(@"Tự thử lại khi video báo lỗi"), @"exclamationmark.arrow.triangle.2.circlepath",
        UIColor.systemRedColor, kPlayFixKey,
        AutoACT(@"Khi video báo \"Đã xảy ra lỗi, nhấn để thử lại\" hoặc đứng hình, AutoAC tự tải lại luồng phát và tua về đúng vị trí đang xem (theo Playback Fix của YTKACE, chế độ Reload). Cần mở lại app."), restart)];
    items.lastObject.sortKey = AutoACT(@"Tắt lặp Short ~");
    [items addObject:ACSwitch(AutoACT(@"Phát lại"), AutoACT(@"Tắt tự động phát"), AutoACT(@"Không tự phát khi mở video"), @"play.slash.fill",
        UIColor.systemIndigoColor, kNoAutoplayKey,
        AutoACT(@"Video ở trang chủ không tự phát xem trước, và khi chọn một video bất kỳ để xem thì video đó không phát ngay mà chờ bạn bấm phát. Cần mở lại app."), restart)];
    items.lastObject.sortKey = AutoACT(@"Tắt lặp Short ~~");
    [items addObject:ACSwitch(AutoACT(@"Phát lại"), AutoACT(@"Tắt cuộn Short"), AutoACT(@"Không tự sang Short kế"), @"arrow.up.and.down.circle.fill",
        UIColor.systemTealColor, kShortsNoScrollKey,
        AutoACT(@"Tắt tự động cuộn Short: khi bật, Short phát hết sẽ ở lại và lặp lại, không tự chuyển sang Short tiếp theo. Vuốt tay vẫn chuyển bình thường. Kết hợp với Tắt lặp Short để dừng hẳn ở cuối."), nil)];
    [items addObject:ACAction(AutoACT(@"Tuỳ chỉnh tab"), AutoACT(@"Tab, thứ tự, Liquid Glass"), @"rectangle.bottomthird.inset.filled", UIColor.systemIndigoColor,
        AutoACT(@"Tuỳ chỉnh thanh tab dưới cùng: đổi thứ tự, ẩn hoặc hiện tab (kể cả Shorts), thêm tab (Nhạc, Trực tiếp, Trò chơi, Tin tức, Thể thao, Học tập, Thời trang, Playlist, Lịch sử, Thông báo, Xem sau, Bài đăng), đổi tên tab, chọn tab khi mở app, kiểu thanh tab Mặc định hoặc Glass, thu nhỏ khi cuộn và màu tab đang chọn. Cần mở lại app để áp dụng."),
        ^{ AutoACDismissMenu(); ACGPresentTabEditor(); })];
    items.lastObject.category = AutoACT(@"Giao diện");
    items.lastObject.inlineRow = YES;

    // ── Nút AutoAC trên trình phát và tài khoản ──
    [items addObject:ACSwitch(AutoACT(@"Tải xuống"), AutoACT(@"Nút tải xuống"), AutoACT(@"Thay nút Tải xuống gốc"), @"arrow.down.circle.fill",
        UIColor.systemPurpleColor, kPlayerButtonKey,
        AutoACT(@"Chạm nút Tải xuống gốc của YouTube (hàng nút dưới video) sẽ mở bảng tải của AutoAC thay cho bảng của YouTube. Có thể bật cùng Nút icon tải khi cần."), ^{ AutoACRelayoutPlayerButton(); })];

    // ── SponsorBlock ──
    [items addObject:ACAction(@"Sponsor block", AutoACT(@"Loại đoạn tự bỏ qua"), @"checklist", UIColor.systemGreenColor,
        AutoACT(@"Chọn các loại đoạn SponsorBlock sẽ tự bỏ qua: tài trợ, tự quảng bá, nhắc tương tác, mở đầu, kết, xem trước, phần không phải nhạc, đoạn thừa."),
        ^{ AutoACDismissMenu(); AutoACShowSponsorCategories(); })];
    items.lastObject.inlineRow = YES;
    [items addObject:ACSwitch(AutoACT(@"Quảng cáo"), AutoACT(@"Bật tự bỏ qua"), AutoACT(@"Dữ liệu từ sponsor.ajay.app"), @"forward.end.alt.fill",
        UIColor.systemGreenColor, kSponsorKey,
        AutoACT(@"Tự tua qua các đoạn tài trợ, tự quảng bá, nhắc like và đăng ký do cộng đồng SponsorBlock đánh dấu. Chọn các loại đoạn ở mục Sponsor block. Áp dụng từ video tiếp theo."), nil)];
    [items addObject:ACSwitch(AutoACT(@"Quảng cáo"), AutoACT(@"Báo khi bỏ qua"), AutoACT(@"Hiện thông báo nhỏ"), @"bell.badge.fill",
        UIColor.systemOrangeColor, kSponsorAlertKey,
        AutoACT(@"Hiện thông báo ngắn cho biết loại đoạn vừa được bỏ qua."), nil)];

    // ── Shorts và nội dung trang chủ (theo ytkace) ──
    NSArray *shortsRows = @[
        @[AutoACT(@"Ẩn nút Thích"), AutoACT(@"Cột nút bên phải"), @"hand.thumbsup.fill", kShortsLikeKey, AutoACT(@"Ẩn nút Thích trong Shorts.")],
        @[AutoACT(@"Ẩn bình luận"), AutoACT(@"Cột nút bên phải"), @"text.bubble.fill", kShortsCommentKey, AutoACT(@"Ẩn nút Bình luận trong Shorts.")],
        @[AutoACT(@"Ẩn chia sẻ"), AutoACT(@"Cột nút bên phải"), @"arrowshape.turn.up.right.fill", kShortsShareKey, AutoACT(@"Ẩn nút Chia sẻ trong Shorts.")],
        @[AutoACT(@"Ẩn nút lưu"), AutoACT(@"Cột nút bên phải"), @"bookmark.fill", kShortsSaveKey, AutoACT(@"Ẩn nút Lưu vào danh sách phát trong Shorts.")],
        @[AutoACT(@"Ẩn Remix"), AutoACT(@"Cột nút bên phải"), @"rectangle.on.rectangle.angled", kShortsRemixKey, AutoACT(@"Ẩn nút Remix trong Shorts.")],
        @[AutoACT(@"Ẩn âm thanh"), AutoACT(@"Đĩa nhạc góc dưới"), @"music.note", kShortsSoundKey, AutoACT(@"Ẩn nút âm thanh (đĩa nhạc) trong Shorts.")],
        @[AutoACT(@"Ẩn thẻ tạm dừng"), AutoACT(@"Khi chạm dừng video"), @"pause.rectangle.fill", kShortsPauseCardKey, AutoACT(@"Ẩn thẻ gợi ý hiện ra khi bạn chạm để dừng một Short.")],
        @[AutoACT(@"Ẩn thẻ sản phẩm"), AutoACT(@"Sản phẩm, giỏ hàng"), @"cart.badge.minus", kHideShopTagKey, AutoACT(@"Ẩn thẻ sản phẩm và giỏ hàng gắn trên Short. Chỉ tác động lên lớp phủ của Short đang xem, không quét trang chủ hay danh sách nên không gây trắng trang hay lag.")]];
    for (NSArray *r in shortsRows) {
        [items addObject:ACSwitch(@"Shorts", r[0], r[1], r[2], UIColor.systemOrangeColor, r[3],
            [r[4] stringByAppendingString:AutoACT(@" Áp dụng khi cuộn tới Short mới hoặc mở lại app.")], restart)];
    }
    [items addObject:ACSwitch(AutoACT(@"Giao diện"), AutoACT(@"Ẩn bài đăng"), AutoACT(@"Bài đăng cộng đồng"), @"doc.richtext",
        UIColor.systemTealColor, kHideCommunityKey,
        AutoACT(@"Ẩn các bài đăng cộng đồng (bài viết của kênh) xuất hiện trong trang chủ. Có thể để lại khoảng trống nhỏ. Cần mở lại app."), restart)];
    [items addObject:ACSwitch(AutoACT(@"Giao diện"), AutoACT(@"Ẩn chơi game"), AutoACT(@"Khỏi trang chủ"), @"gamecontroller.fill",
        UIColor.systemIndigoColor, kHideGamesKey,
        AutoACT(@"Ẩn mục Chơi game (Playables) xuất hiện giữa các video trong trang chủ. Có thể để lại khoảng trống nhỏ. Cần mở lại app."), restart)];
    [items addObject:ACSwitch(AutoACT(@"Giao diện"), AutoACT(@"Ẩn gợi ý Mix"), AutoACT(@"Thẻ đề xuất trong bảng tin"), @"rectangle.stack.badge.minus",
        UIColor.systemPinkColor, kHideMixesKey,
        AutoACT(@"Ẩn thẻ gợi ý (nudge) và Mix trong bảng tin. Cần mở lại app."), restart)];

    // ── Chức năng bổ sung từ ytkace ──
    [items addObject:ACSwitch(AutoACT(@"Quảng cáo"), @"No premium", AutoACT(@"Chặn popup và thẻ mời Premium"), @"xmark.shield.fill",
        UIColor.systemRedColor, kHidePromosKey,
        AutoACT(@"No premium: chặn các popup, thanh gợi ý và hộp thoại mời dùng thử hoặc mua YouTube Premium, đồng thời gỡ khỏi bảng tin các thẻ mời dùng thử hoặc mua YouTube Music Premium (không để lại khoảng trống). Khi bản build có NoYTPremium thì công tắc này bật tắt luôn cả phần đó (chặn khảo sát, mục dùng thử trong cài đặt). Cần mở lại app."),
        TWEAK_UPSTREAM_NOYTPREMIUM_GATED ? restart : nil)];
    [items addObject:ACSwitch(AutoACT(@"Quảng cáo"), AutoACT(@"Ẩn nhãn trả phí"), AutoACT(@"Có quảng cáo trả phí"), @"tag.slash.fill",
        UIColor.systemOrangeColor, kHidePaidPromoKey,
        AutoACT(@"Ẩn nhãn \"Có quảng cáo trả phí\" hiện trên trình phát khi video có nội dung được tài trợ. Chỉ ẩn nhãn, không chặn nội dung của video."), nil)];
    [items addObject:ACSwitch(AutoACT(@"Giao diện"), AutoACT(@"Ẩn hiệu ứng mở"), AutoACT(@"Vào thẳng trang chủ"), @"bolt.fill",
        UIColor.systemOrangeColor, kNoLaunchAnimKey,
        AutoACT(@"Ẩn hiệu ứng logo YouTube lúc khởi động để vào app nhanh hơn."), nil)];
    [items addObject:ACSwitch(AutoACT(@"Giao diện"), AutoACT(@"Ẩn video Short"), AutoACT(@"Khỏi trang chủ"), @"play.square.stack.fill",
        UIColor.systemRedColor, kHideShortsShelfKey,
        AutoACT(@"Ẩn các hàng video Short xuất hiện giữa các video trong trang chủ. Không ảnh hưởng tab Shorts. Có thể để lại khoảng trống nhỏ. Cần mở lại app."), restart)];

    // ── Tải xuống ──
    [items addObject:ACSwitch(AutoACT(@"Tải xuống"), AutoACT(@"Hỏi nơi lưu"), AutoACT(@"Ảnh hoặc bảng chia sẻ"), @"folder.fill",
        UIColor.systemOrangeColor, kAskDestKey,
        AutoACT(@"Trước khi tải video, hỏi lưu vào Ảnh hay mở bảng chia sẻ. Tắt đi sẽ theo tuỳ chọn Mở bảng chia sẻ."), nil)];
    [items addObject:ACSwitch(AutoACT(@"Tải xuống"), AutoACT(@"Hỏi chất lượng"), AutoACT(@"Chọn trước khi tải"), @"slider.horizontal.3",
        UIColor.systemBlueColor, kAskQualityKey,
        AutoACT(@"Hiện bảng chọn độ phân giải trước khi tải video. Tắt đi sẽ tải chất lượng cao nhất có thể."), nil)];
    [items addObject:ACSwitch(AutoACT(@"Tải xuống"), AutoACT(@"Mở bảng chia sẻ"), AutoACT(@"Lưu sau khi tải"), @"square.and.arrow.up",
        UIColor.systemGreenColor, kShareAfterKey,
        AutoACT(@"Tự mở bảng chia sẻ khi tải xong để lưu vào Tệp, Ảnh hoặc gửi cho app khác."), nil)];

    [items addObject:ACSwitch(AutoACT(@"Tải xuống"), AutoACT(@"Sao chép dịch"), AutoACT(@"Nhấn giữ bình luận"), @"doc.on.clipboard.fill",
        UIColor.systemTealColor, kCommentToolsKey,
        AutoACT(@"Sao chép dịch: nhấn giữ vào một bình luận để sao chép nội dung, dịch sang ngôn ngữ của thiết bị hoặc dịch rồi sao chép."), ^{ AutoACAttachCommentGestures(); })];
    [items addObject:ACSwitch(AutoACT(@"Tải xuống"), AutoACT(@"Lưu ảnh bài đăng"), AutoACT(@"Nút lưu khi xem ảnh"), @"photo.on.rectangle.angled",
        UIColor.systemYellowColor, kPostImageKey,
        AutoACT(@"Hiện nút lưu ở góc trên bên trái khi xem ảnh trong bài đăng cộng đồng, lưu bản gốc vào Ảnh. Cần mở lại app."), restart)];

    // Tác vụ tải xuống và sao chép nằm trong nhóm Tải xuống; các tác vụ trình phát cũ đã bỏ khỏi menu
    NSSet<NSString *> *downloadTitles = [NSSet setWithArray:@[AutoACT(@"Tải video"), AutoACT(@"Tải âm thanh"), AutoACT(@"Lưu ảnh bìa"), AutoACT(@"Sao chép")]];
    NSMutableIndexSet *dropIdx = [NSMutableIndexSet indexSet];
    [items enumerateObjectsUsingBlock:^(AutoACItem *i, NSUInteger idx, BOOL *stop) {
        if (!i.action) return;
        if ([i.title isEqualToString:AutoACT(@"Dọn cache ngay")] || [i.title isEqualToString:AutoACT(@"Đặt lại cài đặt")] ||
            [i.title isEqualToString:AutoACT(@"Sao lưu cài đặt")] || [i.title isEqualToString:AutoACT(@"Khôi phục cài đặt")] ||
            [i.title isEqualToString:AutoACT(@"Dung lượng ứng dụng")]) { i.category = AutoACT(@"Bộ nhớ"); i.inlineRow = YES; }   // xếp xen kẽ theo A-Z cùng công tắc
        else if ([i.title isEqualToString:@"Sponsor block"]) i.category = AutoACT(@"Quảng cáo");
        else if ([i.title isEqualToString:AutoACT(@"Tuỳ chỉnh tab")]) i.category = AutoACT(@"Giao diện");
        else if ([i.title isEqualToString:AutoACT(@"Tuỳ chỉnh Overlay")]) i.category = AutoACT(@"Phát lại");
        else if ([downloadTitles containsObject:i.title]) i.category = AutoACT(@"Tải xuống");
        else [dropIdx addIndex:idx];
    }];
    [items removeObjectsAtIndexes:dropIdx];
    return items;
}

static NSDictionary<NSString *, NSArray *> *AutoACCategoryStyle(void) {
    return @{
        AutoACT(@"Bộ nhớ"):   @[@"internaldrive.fill", UIColor.systemGreenColor],
        AutoACT(@"Giao diện"): @[@"paintbrush.pointed.fill", UIColor.systemIndigoColor],
        AutoACT(@"Phát lại"):  @[@"play.rectangle.fill", UIColor.systemTealColor],
        AutoACT(@"Quảng cáo"): @[@"shield.fill", UIColor.systemRedColor],
        @"Shorts":    @[@"play.square.stack.fill", UIColor.systemOrangeColor],
        @"SponsorBlock": @[@"forward.end.alt.fill", UIColor.systemGreenColor],
        AutoACT(@"Tài khoản"): @[@"person.crop.circle.fill", UIColor.systemBlueColor],
        kCatPlayer:   @[@"sparkles", UIColor.systemPurpleColor],
        AutoACT(@"Tải xuống"): @[@"arrow.down.circle.fill", UIColor.systemBlueColor],
        kCatQuick:    @[@"bolt.fill", UIColor.systemOrangeColor],
    };
}

#pragma mark - Thành phần dựng menu

static UIImage *AutoACGradientImage(CGSize size, UIColor *from, UIColor *to) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)@[(id)from.CGColor, (id)to.CGColor], NULL);
        CGContextDrawLinearGradient(ctx.CGContext, g, CGPointZero, CGPointMake(size.width, size.height), 0);
        CGGradientRelease(g);
        CGColorSpaceRelease(space);
    }];
}

static UILabel *AutoACLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = color;
    return l;
}

// Hàng công tắc: ô biểu tượng + tên + dòng phụ + công tắc
static UIView *AutoACSwitchRow(AutoACItem *item) {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    AutoACAddHighlight(button);

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.onTintColor = UIColor.systemGreenColor;
    toggle.on = [kPrefs boolForKey:item.key];
    toggle.transform = CGAffineTransformMakeScale(0.82, 0.82);

    __weak UISwitch *weakToggle = toggle;
    NSString *key = item.key;
    void (^onChange)(void) = item.onChange;
    void (^commit)(void) = ^{
        UISwitch *t = weakToggle;
        if (!t) return;
        [kPrefs setBool:t.isOn forKey:key];
        [[UISelectionFeedbackGenerator new] selectionChanged];
        if (onChange) onChange();
    };
    __block id syncObserver = nil;
    syncObserver = [[NSNotificationCenter defaultCenter] addObserverForName:@"AutoACSwitchSync" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        UISwitch *t = weakToggle;
        if (!t) { [[NSNotificationCenter defaultCenter] removeObserver:syncObserver]; return; }
        BOOL now = [kPrefs boolForKey:key];
        if (t.isOn != now) [t setOn:now animated:YES];
    }];
    [toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { commit(); }]
     forControlEvents:UIControlEventValueChanged];
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        UISwitch *t = weakToggle;
        if (!t) return;
        [t setOn:!t.isOn animated:YES];
        commit();
    }] forControlEvents:UIControlEventTouchUpInside];

    UIView *tile = AutoACIconTile(item.symbol, item.color);
    UILabel *title = AutoACLabel(item.title, 15, UIFontWeightSemibold, UIColor.labelColor);
    UILabel *sub = AutoACLabel(item.sub, 11.5, UIFontWeightRegular, UIColor.secondaryLabelColor);
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[title, sub]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 1;
    text.translatesAutoresizingMaskIntoConstraints = NO;
    text.userInteractionEnabled = NO;

    [row addSubview:button];
    [row addSubview:tile];
    [row addSubview:text];
    [row addSubview:toggle];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:52],
        [button.topAnchor constraintEqualToAnchor:row.topAnchor],
        [button.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [button.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [tile.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [tile.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [text.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:12],
        [text.topAnchor constraintEqualToAnchor:row.topAnchor constant:8],
        [text.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-8],
        [text.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-6],
        [toggle.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-6],
        [toggle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}


static UIView *AutoACSectionTitle(NSString *name, NSString *symbol, UIColor *color, BOOL withTopSpace) {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:cfg]];
    icon.tintColor = color;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UILabel *label = [[UILabel alloc] init];
    label.attributedText = [[NSAttributedString alloc] initWithString:name.uppercaseString attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
        NSKernAttributeName: @0.6}];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, label]];
    row.spacing = 9;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *wrap = [[UIView alloc] init];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:withTopSpace ? 16 : 6],
        [row.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-8],
        [row.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:6],
        [row.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-6],
        [wrap.heightAnchor constraintGreaterThanOrEqualToConstant:48],
    ]];
    return wrap;
}

// Thẻ nhóm bo góc, các hàng cách nhau bằng đường kẻ mảnh
static UIView *AutoACGroupCard(NSArray<UIView *> *rows) {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.06];
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;

    NSMutableArray<UIView *> *arranged = [NSMutableArray array];
    for (NSUInteger i = 0; i < rows.count; i++) {
        if (i > 0) [arranged addObject:AutoACSeparator()];
        [arranged addObject:rows[i]];
    }
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:arranged];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
    ]];
    return card;
}

// Thanh hành động ngang: ô biểu tượng + tên + dòng phụ + mũi tên (dùng cho Dọn cache ngay, Đặt lại cài đặt)
static UIView *AutoACActionBar(AutoACItem *item, NSMutableArray<UILabel *> *subLabels) {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.06];
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    AutoACAddHighlight(button);
    void (^action)(void) = item.action;
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        [[UIImpactFeedbackGenerator new] impactOccurred];
        if (action) action();
    }] forControlEvents:UIControlEventTouchUpInside];

    UIView *tile = AutoACIconTile(item.symbol, item.color);
    UILabel *title = AutoACLabel(item.title, 15, UIFontWeightSemibold, UIColor.labelColor);
    UILabel *sub = AutoACLabel(item.sub, 11.5, UIFontWeightRegular, UIColor.secondaryLabelColor);
    if ([item.title isEqualToString:AutoACT(@"Dọn cache ngay")]) [subLabels addObject:sub];
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[title, sub]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 1;
    text.translatesAutoresizingMaskIntoConstraints = NO;
    text.userInteractionEnabled = NO;

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold];
    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:cfg]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = UIColor.tertiaryLabelColor;
    chevron.userInteractionEnabled = NO;

    [card addSubview:button];
    [card addSubview:tile];
    [card addSubview:text];
    [card addSubview:chevron];
    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:52],
        [button.topAnchor constraintEqualToAnchor:card.topAnchor],
        [button.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [button.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [tile.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [tile.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [text.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:12],
        [text.topAnchor constraintEqualToAnchor:card.topAnchor constant:8],
        [text.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8],
        [text.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-8],
        [chevron.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [chevron.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
    ]];
    return card;
}

// Tiêu đề nhóm có nút thu gọn / mở rộng: chạm vào cả dòng để đổi, mũi tên xoay theo trạng thái
static UIView *AutoACCollapsibleTitle(NSString *name, NSString *symbol, UIColor *color, BOOL withTopSpace,
                                      BOOL collapsed, void (^onToggle)(BOOL nowCollapsed)) {
    UIView *wrap = AutoACSectionTitle(name, symbol, color, withTopSpace);
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightHeavy];
    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:cfg]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = UIColor.secondaryLabelColor;
    chevron.contentMode = UIViewContentModeCenter;
    chevron.transform = collapsed ? CGAffineTransformMakeRotation(-M_PI_2) : CGAffineTransformIdentity;
    UIView *bubble = [[UIView alloc] init];
    bubble.translatesAutoresizingMaskIntoConstraints = NO;
    bubble.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.10];
    bubble.layer.cornerRadius = 17;
    bubble.userInteractionEnabled = NO;
    [bubble addSubview:chevron];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.accessibilityLabel = name;
    [wrap addSubview:bubble];
    [wrap addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:wrap.topAnchor],
        [button.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
        [button.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
        [bubble.widthAnchor constraintEqualToConstant:34],
        [bubble.heightAnchor constraintEqualToConstant:34],
        [bubble.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-6],
        [bubble.centerYAnchor constraintEqualToAnchor:wrap.centerYAnchor constant:withTopSpace ? 4 : -1],
        [chevron.centerXAnchor constraintEqualToAnchor:bubble.centerXAnchor],
        [chevron.centerYAnchor constraintEqualToAnchor:bubble.centerYAnchor],
    ]];
    __block BOOL state = collapsed;
    __weak UIImageView *weakChevron = chevron;
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        state = !state;
        [[UISelectionFeedbackGenerator new] selectionChanged];
        [UIView animateWithDuration:0.25 animations:^{
            weakChevron.transform = state ? CGAffineTransformMakeRotation(-M_PI_2) : CGAffineTransformIdentity;
        }];
        onToggle(state);
    }] forControlEvents:UIControlEventTouchUpInside];
    return wrap;
}

static NSString *const kCollapsedPrefix = @"kCollapsed.";

static BOOL AutoACGroupCollapsed(NSString *name) {
    id stored = [kPrefs objectForKey:[kCollapsedPrefix stringByAppendingString:name]];
    return stored ? [stored boolValue] : YES;   // mặc định: mọi nhóm gập sẵn
}

// Một nhóm: tiêu đề bấm được + phần nội dung thu gọn được (trạng thái nhớ lại cho lần mở sau)
static void AutoACAddSection(UIStackView *page, NSString *name, NSArray *style, BOOL topSpace,
                             NSArray<UIView *> *content, CGFloat spacingAfter) {
    UIStackView *box = [[UIStackView alloc] initWithArrangedSubviews:content];
    box.axis = UILayoutConstraintAxisVertical;
    box.spacing = 8;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    BOOL collapsed = AutoACGroupCollapsed(name);
    box.hidden = collapsed;
    NSString *key = [kCollapsedPrefix stringByAppendingString:name];
    UIView *header = AutoACCollapsibleTitle(name, style[0], style[1], topSpace, collapsed, ^(BOOL nowCollapsed) {
        [kPrefs setBool:nowCollapsed forKey:key];
        if (!nowCollapsed) box.alpha = 0;
        AutoACSmooth(0.42, 1.0, ^{
            box.hidden = nowCollapsed;
            box.alpha = nowCollapsed ? 0 : 1;
            [box.window layoutIfNeeded];
        }, ^(BOOL finished) { if (nowCollapsed) box.alpha = 1; });
    });
    [page addArrangedSubview:header];
    [page addArrangedSubview:box];
    if (spacingAfter > 0) [page setCustomSpacing:spacingAfter afterView:box];
}

// Trang danh sách chính: mọi nhóm đều thu gọn / mở rộng được (A–Z).
// Mục có nút bấm (Dọn cache ngay, Đặt lại cài đặt) hiện thành thanh ngang ở đầu nhóm của nó; nhóm "Trong trình phát" chỉ hiện ở trang chú thích.
static UIStackView *AutoACBuildListPage(NSArray<AutoACItem *> *items, NSMutableArray<UILabel *> *cacheLabels) {
    UIStackView *page = [[UIStackView alloc] init];
    page.axis = UILayoutConstraintAxisVertical;
    page.spacing = 0;
    page.translatesAutoresizingMaskIntoConstraints = NO;
    NSDictionary *styles = AutoACCategoryStyle();

    NSMutableDictionary<NSString *, NSMutableArray<AutoACItem *> *> *groups = [NSMutableDictionary dictionary];
    for (AutoACItem *i in items) {
        if ([i.category isEqualToString:kCatPlayer]) continue;
        if (!groups[i.category]) groups[i.category] = [NSMutableArray array];
        [groups[i.category] addObject:i];
    }
    NSArray<NSString *> *names = [groups.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return AutoACCompareVI(a, b);
    }];
    BOOL first = YES;
    for (NSString *name in names) {
        NSArray *style = styles[name] ?: @[@"circle.fill", UIColor.systemGrayColor];
        NSMutableArray<UIView *> *content = [NSMutableArray array];
        NSArray<AutoACItem *> *sorted = AutoACSortedItems(groups[name]);
        for (AutoACItem *i in sorted) if (i.action && !i.inlineRow) [content addObject:AutoACActionBar(i, cacheLabels)];
        NSMutableArray<UIView *> *rows = [NSMutableArray array];
        for (AutoACItem *i in sorted) {
            if (i.action && !i.inlineRow) continue;
            if (i.inlineRow) {   // đóng thẻ công tắc đang dựng, chèn hành động, rồi dựng thẻ mới
                if (rows.count) { [content addObject:AutoACGroupCard(rows)]; rows = [NSMutableArray array]; }
                [content addObject:AutoACActionBar(i, cacheLabels)];
                continue;
            }
            [rows addObject:AutoACSwitchRow(i)];
        }
        if (rows.count) [content addObject:AutoACGroupCard(rows)];
        AutoACAddSection(page, name, style, !first, content, 0);
        first = NO;
    }
    return page;
}


// Hook của YouTube X nằm cùng dylib với AutoAC: hàm nào đang trỏ vào dylib này thì hook đã gắn; không thì lớp/hàm không có trong bản YouTube đang chạy
static NSString *AutoACAdBlockReport(void) {
    NSMutableString *t = [NSMutableString string];
    id adsValue = [kPrefs objectForKey:kYTXAdsKey], bgValue = [kPrefs objectForKey:kYTXBackgroundKey];
    [t appendFormat:@"[Chặn quảng cáo] bản build có YouTube X: %@ · bọc công tắc: %@ · công tắc quảng cáo: %@ · phát nền: %@\n",
        TWEAK_UPSTREAM_COUNT > 0 && [TWEAK_UPSTREAM_INFO containsString:@"YouTube X"] ? @"có" : @"không",
        TWEAK_UPSTREAM_YOUTUBEX_GATED ? @"có" : @"không",
        (adsValue ? [adsValue boolValue] : YES) ? @"bật" : @"tắt", (bgValue ? [bgValue boolValue] : YES) ? @"bật" : @"tắt"];
    Dl_info mine = {0};
    dladdr((void *)&AutoACAdBlockReport, &mine);
    NSArray<NSArray *> *checks = @[
        @[@"YTLocalPlaybackController", @"createAdsPlaybackCoordinator", @NO],
        @[@"YTIPlayerResponse", @"playerAdsArray", @NO],
        @[@"YTAdShieldUtils", @"spamSignalsDictionary", @YES],
        @[@"YTReelDataSource", @"makeContentModelForEntry:", @NO],
        @[@"YTArraySectionViewModel", @"initWithEntries:", @NO],
        @[@"YTAdElementsCellExternallyManagedSlotAdapterImpl", @"isValidSlotType:", @NO],
        @[@"YTInnerTubeCollectionViewController", @"addSectionsFromArray:", @NO],
        @[@"YTIPlayabilityStatus", @"isPlayableInBackground", @NO],
        @[@"MLVideo", @"playableInBackground", @NO],
    ];
    NSUInteger hooked = 0;
    NSMutableString *lines = [NSMutableString string];
    for (NSArray *c in checks) {
        Class cls = NSClassFromString(c[0]);
        NSString *state;
        if (!cls) {
            state = @"YouTube này không có lớp";
        } else {
            Method m = class_getInstanceMethod([c[2] boolValue] ? object_getClass(cls) : cls, NSSelectorFromString(c[1]));
            if (!m) {
                state = @"không có hàm";
            } else {
                IMP imp = method_getImplementation(m);
#if __has_feature(ptrauth_calls)
                imp = ptrauth_strip(imp, ptrauth_key_function_pointer);
#endif
                Dl_info info = {0};
                BOOL inMine = dladdr((void *)imp, &info) && info.dli_fbase == mine.dli_fbase;
                state = inMine ? @"đã gắn" : @"chưa gắn";
                if (inMine) hooked++;
            }
        }
        [lines appendFormat:@"  %@ %@ → %@\n", c[0], c[1], state];
    }
    [t appendFormat:@"[Chặn quảng cáo] hook đã gắn %lu/%lu\n%@", (unsigned long)hooked, (unsigned long)checks.count, lines];
    return t;
}

static NSString *AutoACExtraTabReport(void) {
    NSMutableString *t = [NSMutableString string];
    for (NSString *page in @[@"Short", @"thường"]) {
        NSDictionary *bucket = gACGExtraDump[page];
        if (bucket.count == 0) continue;
        [t appendFormat:@"[Tab thêm — lúc ở trang %@]\n", page];
        for (NSString *token in [bucket.allKeys sortedArrayUsingSelector:@selector(compare:)]) [t appendFormat:@"  %@: %@\n", token, bucket[token]];
    }
    return t;
}

static NSString *AutoACDiagnosticsText(void) {
    NSMutableString *t = [NSMutableString string];
    UIDevice *d = UIDevice.currentDevice;
    [t appendFormat:AutoACT(@"bản %@ · iOS %@ · %@\n"), kCurrentBuildID, d.systemVersion, d.model];
    [t appendFormat:AutoACT(@"an toàn mức %ld · kính lỏng %@\n"), (long)gSafeLevel, AutoACGlassAvailable() ? AutoACT(@"có") : AutoACT(@"không")];
    [t appendFormat:AutoACT(@"nút tải phủ %@ · nút icon tải %@ · tốc độ %@ · PiP %@\n"),
        [kPrefs boolForKey:kPlayerButtonKey] ? AutoACT(@"bật") : AutoACT(@"tắt"), [kPrefs boolForKey:kPlayerFloatKey] ? AutoACT(@"bật") : AutoACT(@"tắt"),
        [kPrefs boolForKey:kPlayerSpeedBtnKey] ? AutoACT(@"bật") : AutoACT(@"tắt"), [kPrefs boolForKey:kPlayerPiPKey] ? AutoACT(@"bật") : AutoACT(@"tắt")];
    {
        NSArray<NSString *> *top = nil, *bottom = nil, *off = nil;
        AutoACOverlayLayout(&top, &bottom, &off);
        [t appendFormat:@"[Overlay] hàng trên: %@ · hàng dưới: %@ · tắt: %@ · bước %.0f\n", AutoACOverlayNames(top), AutoACOverlayNames(bottom), AutoACOverlayNames(off), gAutoACToolStep];
    }
    [t appendFormat:AutoACT(@"ẩn nút lưu Shorts %@ · tốc độ đã chọn %g\n"),
        [kPrefs boolForKey:kShortsSaveKey] ? AutoACT(@"bật") : AutoACT(@"tắt"), [kPrefs doubleForKey:@"kAutoACLastPickedRate"]];
    { UIWindow *w = AutoACKeyWindow(); if (w) [t appendFormat:AutoACT(@"cửa sổ %.0f×%.0f · vùng an toàn T%.0f D%.0f Tr%.0f Ph%.0f\n"), w.bounds.size.width, w.bounds.size.height, w.safeAreaInsets.top, w.safeAreaInsets.bottom, w.safeAreaInsets.left, w.safeAreaInsets.right]; }
    [t appendFormat:@"%@\n", gPrevRunNote ?: AutoACT(@"lần chạy trước: không rõ")];
    if ([gPreviousTrace containsString:@"CRASH"]) {
        NSString *lg = gPreviousTrace.length > 1200 ? [gPreviousTrace substringFromIndex:gPreviousTrace.length - 1200] : gPreviousTrace;
        [t appendFormat:AutoACT(@"[Nhật ký crash]\n%@\n"), lg];
    }
    [t appendFormat:AutoACT(@"\n[Tab] hook %@ · đã nhận %ld tab, hiện %ld\n%@\n"), gACGTabHooked ? AutoACT(@"đã gắn") : AutoACT(@"chưa gắn"),
        (long)gACGTabSeen, (long)gACGTabShown, ACGDiagnosticsLine()];
    if (gACGIconColorDiag.length) [t appendFormat:@"[Màu icon tab] %@\n", gACGIconColorDiag];
    [t appendString:AutoACExtraTabReport()];
    [t appendString:AutoACAdBlockReport()];
    if (gACGShortsDockDiag) [t appendFormat:@"[Dock Short] %@\n", gACGShortsDockDiag];
    [t appendFormat:AutoACT(@"kính lỏng iOS 26: %@ · hook kính: %@\n"), ACGLiquidGlassAvailable() ? AutoACT(@"có") : AutoACT(@"không"), gACGGlassHooked ? AutoACT(@"đã gắn") : AutoACT(@"chưa gắn")];
    [t appendFormat:AutoACT(@"\n[Dung lượng] mục lớn nhất:\n%@"), gStorageReport ?: AutoACT(@"đang tính…\n")];
    [t appendFormat:@"\n[Shorts] advance seen %ld (blocked %ld) · last: %@ · noloop armed %ld\n",
        (long)gAdvSeen, (long)gAdvBlocked, gAdvLast ?: @"-", (long)gAdvTickArmed];
    if (gReelSeen.count) [t appendFormat:AutoACT(@"\n[Shorts] nút cột phải:\n%@\n"), [gReelSeen.array componentsJoinedByString:@"\n"]];
    [t appendFormat:@"\n[Lọc danh sách] tab hiện tại %@ · %@\n", gListTabIdent.length ? gListTabIdent : @"?",
        gListFilterAllowed ? @"đang lọc" : (gListTabIdent.length ? @"không lọc (chỉ lọc ở Trang chủ)" : @"không lọc (chưa đọc được tab)")];
    [t appendFormat:@"[Lọc danh sách] bỏ hàng Short %ld · bài đăng %ld · Mix %ld · game %ld · thẻ Premium %ld\n", (long)gDropShelf, (long)gDropPost, (long)gDropMix, (long)gDropGame, (long)gDropBanner];
    [t appendFormat:@"[Lọc danh sách] ô đã duyệt %ld · Ẩn video Short %@\n", (long)gFeedCellsSeen, [kPrefs boolForKey:kHideShortsShelfKey] ? @"bật" : @"tắt"];
    if (gACGShortsExtendDiag) [t appendFormat:@"[Short kéo xuống] %@\n", gACGShortsExtendDiag];
    if (gPremiumSeen.count) [t appendFormat:@"[Thẻ Premium/Music/Short đã thấy] %@\n", [gPremiumSeen.array componentsJoinedByString:@" | "]];
    if (gOverlaySeen.count) [t appendFormat:@"\n[%@]\n%@\n", AutoACT(@"Mã lớp phủ Shorts"), [gOverlaySeen.array componentsJoinedByString:@"\n"]];
    return t;
}

static UIStackView *AutoACBuildInfoPage(NSArray<AutoACItem *> *items) {
    UIStackView *page = [[UIStackView alloc] init];
    page.axis = UILayoutConstraintAxisVertical;
    page.translatesAutoresizingMaskIntoConstraints = NO;
    page.layoutMarginsRelativeArrangement = YES;
    page.layoutMargins = UIEdgeInsetsMake(6, 16, 12, 14);

    NSMutableParagraphStyle *tight = [[NSMutableParagraphStyle alloc] init];
    tight.paragraphSpacing = 4;
    NSMutableParagraphStyle *headPara = [[NSMutableParagraphStyle alloc] init];
    headPara.paragraphSpacingBefore = 12;
    headPara.paragraphSpacing = 3;
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
    void (^add)(NSString *, UIFont *, UIColor *, NSParagraphStyle *) = ^(NSString *str, UIFont *font, UIColor *color, NSParagraphStyle *para) {
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:str attributes:@{
            NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: para}]];
    };
    add(AutoACT(@"TÁC GIẢ\n"), [UIFont systemFontOfSize:12 weight:UIFontWeightBold], UIColor.systemBlueColor, headPara);
    add(@"GitHub\n", [UIFont systemFontOfSize:13.5], UIColor.labelColor, tight);

    add(AutoACT(@"Tùy chỉnh YouTube\n"), [UIFont systemFontOfSize:13.5], UIColor.labelColor, tight);

    add(AutoACT(@"MÃ NGUỒN THAM KHẢO\n"), [UIFont systemFontOfSize:12 weight:UIFontWeightBold], UIColor.systemBlueColor, headPara);
    NSString *src = @"YouTube X · NoYTPremium · ytkace • ytlite · SponsorBlock (sponsor.ajay.app)\n";
    NSString *up = TWEAK_UPSTREAM_INFO;
    if (TWEAK_UPSTREAM_COUNT > 0 && up.length > 0) src = [src stringByAppendingFormat:AutoACT(@"Đã tích hợp: %@\n"), up];
    add(src, [UIFont systemFontOfSize:13.5], UIColor.labelColor, tight);

    add(AutoACT(@"CHỨC NĂNG CHÍNH\n"), [UIFont systemFontOfSize:12 weight:UIFontWeightBold], UIColor.systemBlueColor, headPara);
    // Xếp A-Z theo tên nhóm
    NSArray<NSArray<NSString *> *> *mainFeatures = @[
        @[AutoACT(@"Bộ nhớ"), AutoACT(@"tự dọn cache khi thoát app")],
        @[AutoACT(@"Giao diện"), AutoACT(@"thanh tab Glass, thêm và sắp xếp tab, ẩn hiệu ứng mở, bài đăng, Mix, Short ở trang chủ")],
        @[AutoACT(@"Phát lại"), AutoACT(@"tốc độ, PiP, tự thử lại khi lỗi, tắt tự động phát, tắt lặp và tắt cuộn Short")],
        @[AutoACT(@"Quảng cáo"), AutoACT(@"chặn quảng cáo, ẩn popup Premium, Sponsor block")],
        @[@"Shorts", AutoACT(@"ẩn nút Thích, bình luận, chia sẻ, lưu, Remix, âm thanh, thẻ tạm dừng")],
        @[AutoACT(@"Tải xuống"), AutoACT(@"video, âm thanh, ảnh bìa, ảnh bài đăng, sao chép và dịch bình luận")],
    ];
    for (NSArray<NSString *> *f in mainFeatures) {
        add([NSString stringWithFormat:@"%@  ", f[0]], [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold], UIColor.labelColor, tight);
        add([f[1] stringByAppendingString:@"\n"], [UIFont systemFontOfSize:13.5], UIColor.secondaryLabelColor, tight);
    }

    UILabel *infoTitle = AutoACLabel(AutoACT(@"Thông tin"), 17, UIFontWeightBold, UIColor.labelColor);
    [page addArrangedSubview:infoTitle];

    // ── Thanh trạng thái tải: chỉ hiện khi đang tải, tải xong tự biến mất ──
    UIButton *(^pill)(UIColor *, BOOL) = ^UIButton *(UIColor *tint, BOOL tappable) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
        b.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        b.tintColor = tint;
        b.backgroundColor = [tint colorWithAlphaComponent:0.14];
        b.contentEdgeInsets = UIEdgeInsetsMake(5, 11, 5, 11);
        b.layer.cornerRadius = 14;
        b.layer.cornerCurve = kCACornerCurveContinuous;
        b.userInteractionEnabled = tappable;
        [b.heightAnchor constraintEqualToConstant:30].active = YES;
        return b;
    };
    UIButton *dlLabel = pill(UIColor.labelColor, NO);
    UIButton *dlPercent = pill(UIColor.systemBlueColor, NO);
    UIButton *dlPause = pill(UIColor.systemBlueColor, YES);
    UIButton *dlCancel = pill(UIColor.systemRedColor, YES);
    UIView *spacer = [[UIView alloc] init];
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *dlHead = [[UIStackView alloc] initWithArrangedSubviews:@[dlLabel, dlPercent, dlPause, dlCancel]];
    dlHead.axis = UILayoutConstraintAxisHorizontal;
    dlHead.distribution = UIStackViewDistributionFillEqually;
    dlHead.spacing = 4;
    dlHead.alignment = UIStackViewAlignmentCenter;
    UIProgressView *dlBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    dlBar.progressTintColor = UIColor.systemBlueColor;
    UIButton *dlName = pill(UIColor.secondaryLabelColor, NO);
    dlName.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    UIButton *dlQueue = pill(UIColor.systemOrangeColor, NO);
    dlQueue.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    dlQueue.titleLabel.numberOfLines = 0;
    UIStackView *dlBox = [[UIStackView alloc] initWithArrangedSubviews:@[dlHead, dlBar, dlName, dlQueue]];
    dlBox.axis = UILayoutConstraintAxisVertical;
    dlBox.spacing = 8;
    dlBox.layoutMarginsRelativeArrangement = YES;
    dlBox.layoutMargins = UIEdgeInsetsMake(10, 0, 4, 0);
    dlBox.hidden = !(gDownloading || gDLQueue.count > 0);
    [page addArrangedSubview:dlBox];
    UIImageSymbolConfiguration *dlCfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    void (^dlRefresh)(void) = ^{
        BOOL mux = [gDLLabel isEqualToString:AutoACT(@"Đang ghép tệp")];
        NSString *stateIcon = gDLPaused ? @"pause.circle.fill" : (mux ? @"film.stack.fill" : ([gDLLabel containsString:AutoACT(@"âm thanh")] ? @"waveform.circle.fill" : @"arrow.down.circle.fill"));
        [dlLabel setImage:[UIImage systemImageNamed:stateIcon withConfiguration:dlCfg] forState:UIControlStateNormal];
        [dlLabel setTitle:nil forState:UIControlStateNormal];
        [dlPercent setTitle:[NSString stringWithFormat:@"%d%%", (int)round(MIN(MAX(gDLFraction, 0), 1) * 100)] forState:UIControlStateNormal];
        dlBar.progress = (float)MIN(MAX(gDLFraction, 0), 1);
        [dlName setImage:[UIImage systemImageNamed:@"doc.fill" withConfiguration:dlCfg] forState:UIControlStateNormal];
        [dlName setTitle:gDLName.length ? [@" " stringByAppendingString:gDLName] : @" —" forState:UIControlStateNormal];
        [dlPause setImage:[UIImage systemImageNamed:gDLPaused ? @"play.fill" : @"pause.fill" withConfiguration:dlCfg] forState:UIControlStateNormal];
        [dlPause setTitle:nil forState:UIControlStateNormal];
        [dlCancel setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:dlCfg] forState:UIControlStateNormal];
        [dlCancel setTitle:nil forState:UIControlStateNormal];
        dlPause.accessibilityLabel = gDLPaused ? AutoACT(@"Tiếp tục") : AutoACT(@"Tạm dừng");
        dlCancel.accessibilityLabel = AutoACT(@"Huỷ tải");
        dlQueue.hidden = gDLQueueIDs.count == 0;
        if (gDLQueueIDs.count) {
            [dlQueue setImage:[UIImage systemImageNamed:@"text.badge.plus" withConfiguration:dlCfg] forState:UIControlStateNormal];
            [dlQueue setTitle:[NSString stringWithFormat:@" %@ (%lu): %@", AutoACT(@"Hàng đợi"), (unsigned long)gDLQueueIDs.count, [gDLQueueIDs componentsJoinedByString:@", "]] forState:UIControlStateNormal];
        }
        dlPause.enabled = !mux; dlCancel.enabled = !mux;
        dlPause.alpha = dlCancel.alpha = mux ? 0.4 : 1;
    };
    dlRefresh();
    [dlPause addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        gDLPaused = !gDLPaused;
        [[UISelectionFeedbackGenerator new] selectionChanged];
        dlRefresh();
    }] forControlEvents:UIControlEventTouchUpInside];
    [dlCancel addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        gDLCancelled = YES; gDLPaused = NO;
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeWarning];
    }] forControlEvents:UIControlEventTouchUpInside];
    __weak UIStackView *weakBox = dlBox;
    [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        UIStackView *box = weakBox;
        if (!box) { [t invalidate]; return; }
        if (!box.window) return;   // trang chưa/không còn hiện: bỏ qua nhịp này, không tự huỷ bộ đếm (trước đây huỷ ngay nên thanh tải và hàng đợi không bao giờ cập nhật)
        BOOL show = gDownloading || gDLQueue.count > 0;
        if (show) dlRefresh();
        if (box.hidden == show) {
            box.hidden = !show;
            [box.window layoutIfNeeded];
        }
    }];

    UILabel *body = [[UILabel alloc] init];
    body.numberOfLines = 0;
    body.attributedText = text;
    body.translatesAutoresizingMaskIntoConstraints = NO;
    [page addArrangedSubview:body];

    // ── Chế độ an toàn: trạng thái và nút thoát ──
    {
        UILabel *safeTitle = AutoACLabel(AutoACT(@"CHẾ ĐỘ AN TOÀN"), 12, UIFontWeightBold, UIColor.systemOrangeColor);
        UIStackView *safeHead = [[UIStackView alloc] initWithArrangedSubviews:@[safeTitle]];
        safeHead.layoutMarginsRelativeArrangement = YES;
        safeHead.layoutMargins = UIEdgeInsetsMake(12, 0, 0, 0);
        [page addArrangedSubview:safeHead];
        BOOL on = gSafeLevel > 0;
        UILabel *safeBody = AutoACLabel(on
            ? [NSString stringWithFormat:AutoACT(@"Đang bật mức %ld: AutoAC đã tắt bớt một số nhóm chức năng vì app từng crash (mức 1: kính lỏng gốc; mức 2: thêm hook trình phát; mức 3: chỉ còn menu)."), (long)gSafeLevel]
            : AutoACT(@"Đang tắt. Chỉ tự bật khi app crash thật; app bị hệ thống tắt không tính."),
            12.5, UIFontWeightRegular, UIColor.secondaryLabelColor);
        safeBody.numberOfLines = 0;
        [page addArrangedSubview:safeBody];
        if (on) {
            UIButton *safeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            [safeBtn setTitle:AutoACT(@"Thoát chế độ an toàn") forState:UIControlStateNormal];
            safeBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
            safeBtn.tintColor = UIColor.systemOrangeColor;
            safeBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
            safeBtn.contentEdgeInsets = UIEdgeInsetsMake(6, 0, 2, 0);
            [safeBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction *act) {
                [kPrefs setInteger:0 forKey:kSafeLevelKey];
                AutoACDismissMenu();
                AutoACShowHub(@"checkmark.circle.fill", UIColor.systemGreenColor, AutoACT(@"Đã thoát chế độ an toàn"), AutoACT(@"Hãy đóng và mở lại YouTube"), 2.4);
            }] forControlEvents:UIControlEventTouchUpInside];
            [page addArrangedSubview:safeBtn];
        }
    }

    // ── Chẩn đoán toàn hệ thống: công tắc + nội dung ──
    UILabel *diagTitle = AutoACLabel(AutoACT(@"CHẨN ĐOÁN HỆ THỐNG"), 12, UIFontWeightBold, UIColor.systemOrangeColor);
    UISwitch *diagSwitch = [[UISwitch alloc] init];
    diagSwitch.transform = CGAffineTransformMakeScale(0.8, 0.8);
    diagSwitch.on = [kPrefs boolForKey:kDiagKey];
    UIStackView *diagRow = [[UIStackView alloc] initWithArrangedSubviews:@[diagTitle, diagSwitch]];
    diagRow.axis = UILayoutConstraintAxisHorizontal;
    diagRow.alignment = UIStackViewAlignmentCenter;
    diagRow.layoutMarginsRelativeArrangement = YES;
    diagRow.layoutMargins = UIEdgeInsetsMake(10, 0, 0, 0);
    [diagTitle setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [page addArrangedSubview:diagRow];

    UILabel *diagBody = [[UILabel alloc] init];
    diagBody.numberOfLines = 0;
    diagBody.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    diagBody.textColor = UIColor.secondaryLabelColor;
    diagBody.text = AutoACDiagnosticsText();
    diagBody.hidden = !diagSwitch.on;
    diagBody.translatesAutoresizingMaskIntoConstraints = NO;
    [page addArrangedSubview:diagBody];
    __weak UILabel *weakDiag = diagBody;
    // Báo cáo dung lượng tính nền xong mới có; cập nhật lại nội dung khi sẵn sàng
    // Quét dung lượng khá nặng: chỉ khi bật Chẩn đoán, và dùng lại kết quả trong 60 giây
    if (diagSwitch.on) AutoACRefreshStorageReport(^{ UILabel *d = weakDiag; if (d) d.text = AutoACDiagnosticsText(); });
    [diagSwitch addAction:[UIAction actionWithHandler:^(__kindof UIAction *act) {
        BOOL on = ((UISwitch *)act.sender).isOn;
        [kPrefs setBool:on forKey:kDiagKey];
        UILabel *d = weakDiag;
        if (on) { d.text = AutoACDiagnosticsText(); AutoACRefreshStorageReport(^{ UILabel *dd = weakDiag; if (dd) dd.text = AutoACDiagnosticsText(); }); }
        [UIView animateWithDuration:0.2 animations:^{ d.hidden = !on; }];
    }] forControlEvents:UIControlEventValueChanged];
    (void)items;
    return page;
}

// Thanh đầu: biểu tượng gradient, tên + phiên bản, nút "i"
static UIView *AutoACHeaderBar(UIButton *infoButton) {
    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *logo = [[UIImageView alloc] initWithImage:
        AutoACGradientImage(CGSizeMake(34, 34), UIColor.systemIndigoColor, UIColor.systemPinkColor)];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.layer.cornerRadius = 10;
    logo.layer.cornerCurve = kCACornerCurveContinuous;
    logo.clipsToBounds = YES;
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightBold];
    UIImageView *spark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"sparkles" withConfiguration:cfg]];
    spark.translatesAutoresizingMaskIntoConstraints = NO;
    spark.tintColor = UIColor.whiteColor;
    [logo addSubview:spark];

    UILabel *title = AutoACLabel(@"AutoAC", 18, UIFontWeightBold, UIColor.labelColor);
    // Số phiên bản nằm ngay dưới tên AutoAC (thay dòng "Tùy chỉnh YouTube", dòng đó chuyển sang trang Thông tin)
    NSString *tag = AutoACVersionTag();
    UIView *under = tag.length > 0
        ? AutoACPill(tag, UIColor.secondaryLabelColor, 11, 8, 3)
        : AutoACLabel(AutoACT(@"Tùy chỉnh YouTube"), 11.5, UIFontWeightRegular, UIColor.secondaryLabelColor);
    UIStackView *names = [[UIStackView alloc] initWithArrangedSubviews:@[title, under]];
    names.axis = UILayoutConstraintAxisVertical;
    names.alignment = UIStackViewAlignmentLeading;
    names.spacing = 2;
    names.translatesAutoresizingMaskIntoConstraints = NO;

    infoButton.translatesAutoresizingMaskIntoConstraints = NO;
    infoButton.tintColor = UIColor.secondaryLabelColor;
    infoButton.accessibilityLabel = AutoACT(@"Chú thích các chức năng");

    [bar addSubview:logo];
    [bar addSubview:names];
    [bar addSubview:infoButton];
    NSMutableArray<NSLayoutConstraint *> *c = [NSMutableArray arrayWithArray:@[
        [bar.heightAnchor constraintEqualToConstant:58],
        [logo.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:14],
        [logo.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [logo.widthAnchor constraintEqualToConstant:34],
        [logo.heightAnchor constraintEqualToConstant:34],
        [spark.centerXAnchor constraintEqualToAnchor:logo.centerXAnchor],
        [spark.centerYAnchor constraintEqualToAnchor:logo.centerYAnchor],
        [names.leadingAnchor constraintEqualToAnchor:logo.trailingAnchor constant:10],
        [names.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [infoButton.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-6],
        [infoButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [infoButton.widthAnchor constraintEqualToConstant:42],
        [infoButton.heightAnchor constraintEqualToConstant:42],
    ]];
    [c addObject:[names.trailingAnchor constraintLessThanOrEqualToAnchor:infoButton.leadingAnchor constant:-4]];
    [NSLayoutConstraint activateConstraints:c];
    return bar;
}

static void AutoACShowMenu(CGPoint anchor) {
    UIWindow *window = AutoACKeyWindow();
    if (!window || gMenu) return;
    gLastMenuAnchor = anchor;

    CGFloat topConstant = MIN(MAX(anchor.y + 24, window.safeAreaInsets.top + 8), CGRectGetHeight(window.bounds) * 0.35);

    UIButton *backdrop = [UIButton buttonWithType:UIButtonTypeCustom];
    backdrop.frame = window.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backdrop.backgroundColor = UIColor.clearColor;
    [backdrop addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { AutoACDismissMenu(); }]
       forControlEvents:UIControlEventTouchUpInside];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    AutoACStyleShadow(card, 0.22, 20, CGSizeMake(0, 8));
    UIVisualEffectView *blur = AutoACMakeGlass(28);
    [card addSubview:blur];

    NSArray<AutoACItem *> *items = AutoACBuildItems();
    NSMutableArray<UILabel *> *cacheLabels = [NSMutableArray array];
    NSIndexSet *hideRows = [items indexesOfObjectsPassingTest:^BOOL(AutoACItem *it, NSUInteger idx, BOOL *stop) {
        return it.action && [it.category isEqualToString:AutoACT(@"Tải xuống")];   // đã có trong nút Tải xuống
    }];
    NSMutableArray<AutoACItem *> *listItems = [items mutableCopy];
    [listItems removeObjectsAtIndexes:hideRows];
    UIStackView *listPage = AutoACBuildListPage(listItems, cacheLabels);
    UIStackView *infoPage = AutoACBuildInfoPage(items);
    infoPage.hidden = YES;

    UIStackView *holder = [[UIStackView alloc] initWithArrangedSubviews:@[listPage, infoPage]];
    holder.axis = UILayoutConstraintAxisVertical;
    holder.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsVerticalScrollIndicator = YES;
    scroll.alwaysBounceVertical = NO;
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [scroll addSubview:holder];

    UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImageSymbolConfiguration *infoConfig =
        [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    [infoButton setImage:[UIImage systemImageNamed:@"info.circle" withConfiguration:infoConfig]
                forState:UIControlStateNormal];
    UIView *header = AutoACHeaderBar(infoButton);
    [blur.contentView addSubview:header];
    [blur.contentView addSubview:scroll];

    [backdrop addSubview:card];
    [window addSubview:backdrop];
    gMenu = backdrop;

    NSLayoutConstraint *fit = [scroll.heightAnchor constraintEqualToAnchor:holder.heightAnchor];
    fit.priority = UILayoutPriorityDefaultHigh;
    AutoACPinCardWidth(card, window);
    [NSLayoutConstraint activateConstraints:@[
        // Căn giữa, hai bên cách đều mép an toàn; rộng tối đa kMenuMaxWidth; co theo chiều cao khi xoay ngang
        [card.centerXAnchor constraintEqualToAnchor:backdrop.centerXAnchor],
        [card.widthAnchor constraintLessThanOrEqualToConstant:kMenuMaxWidth],
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:backdrop.safeAreaLayoutGuide.leadingAnchor constant:16],
        [card.topAnchor constraintEqualToAnchor:backdrop.topAnchor constant:topConstant],
        [card.bottomAnchor constraintLessThanOrEqualToAnchor:backdrop.safeAreaLayoutGuide.bottomAnchor constant:-70],
        [blur.topAnchor constraintEqualToAnchor:card.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],

        [header.topAnchor constraintEqualToAnchor:blur.contentView.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor],

        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:blur.contentView.bottomAnchor constant:-8],
        fit,

        [holder.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [holder.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-4],
        [holder.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:10],
        [holder.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-10],
        [holder.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-20],
    ]];

    // Nút "Xong" nằm ngay dưới khung menu
    UIVisualEffectView *doneGlass = AutoACMakeGlass(27);
    doneGlass.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop addSubview:doneGlass];
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [done setTitle:AutoACT(@"Xong") forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    done.tintColor = UIColor.whiteColor;
    doneGlass.contentView.backgroundColor = UIColor.systemBlueColor;
    doneGlass.layer.cornerRadius = 27;
    doneGlass.layer.cornerCurve = kCACornerCurveContinuous;
    doneGlass.contentView.layer.cornerRadius = 27;
    doneGlass.contentView.layer.cornerCurve = kCACornerCurveContinuous;
    doneGlass.contentView.clipsToBounds = YES;
    doneGlass.clipsToBounds = YES;
    [done addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { AutoACDismissMenu(); }]
   forControlEvents:UIControlEventTouchUpInside];
    [doneGlass.contentView addSubview:done];
    [NSLayoutConstraint activateConstraints:@[
        [doneGlass.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:10],
        [doneGlass.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [doneGlass.widthAnchor constraintEqualToAnchor:card.widthAnchor],
        [doneGlass.heightAnchor constraintEqualToConstant:54],
        [done.topAnchor constraintEqualToAnchor:doneGlass.contentView.topAnchor],
        [done.bottomAnchor constraintEqualToAnchor:doneGlass.contentView.bottomAnchor],
        [done.leadingAnchor constraintEqualToAnchor:doneGlass.contentView.leadingAnchor],
        [done.trailingAnchor constraintEqualToAnchor:doneGlass.contentView.trailingAnchor],
    ]];

    // Nút "i": chuyển giữa danh sách và trang chú thích
    __block BOOL infoOn = NO;
    __weak UIButton *weakInfo = infoButton;
    __weak UIScrollView *weakScroll = scroll;
    __weak UIWindow *weakWindow = window;
    [infoButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        infoOn = !infoOn;
        [[UISelectionFeedbackGenerator new] selectionChanged];
        UIButton *b = weakInfo;
        b.tintColor = infoOn ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
        [b setImage:[UIImage systemImageNamed:(infoOn ? @"info.circle.fill" : @"info.circle") withConfiguration:infoConfig]
           forState:UIControlStateNormal];
        weakScroll.contentOffset = CGPointZero;
        holder.alpha = 0;
        holder.transform = CGAffineTransformMakeScale(0.96, 0.96);   // nổi lên bật nhẹ
        listPage.hidden = infoOn;
        infoPage.hidden = !infoOn;
        [weakWindow layoutIfNeeded];
        AutoACBounce(^{ holder.alpha = 1; holder.transform = CGAffineTransformIdentity; }, nil);
    }] forControlEvents:UIControlEventTouchUpInside];

    [window layoutIfNeeded];

    // Dung lượng cache hiện tại cho ô "Dọn cache"
    UILabel *cacheLabel = cacheLabels.firstObject;
    if (cacheLabel) {
        __weak UILabel *weakLabel = cacheLabel;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            unsigned long long removable = AutoACCacheRemovableNow();
            unsigned long long total = AutoACCacheSizeNow();
            dispatch_async(dispatch_get_main_queue(), ^{
                weakLabel.text = removable == 0 ? [AutoACT(@"Không có gì để dọn · cache ") stringByAppendingString:AutoACFormatBytes(total)]
                    : [NSString stringWithFormat:AutoACT(@"Dọn được %@ · cache %@"), AutoACFormatBytes(removable), AutoACFormatBytes(total)];
            });
        });
    }

    // Mở ra như popover; khi quay lại từ bảng con thì trượt vào từ trái
    CGRect frame = card.frame;
    CGPoint pivot = CGPointMake(CGRectGetMidX(frame), CGRectGetMinY(frame));
    CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    const CGFloat startScale = 0.86;
    BOOL fromBack = AutoACNavActive() && gNavDir < 0;
    backdrop.alpha = 0;
    if (fromBack) {
        CGFloat dx = -CGRectGetWidth(window.bounds) * 0.12;
        for (UIView *v in backdrop.subviews) v.transform = CGAffineTransformMakeTranslation(dx, 0);
    } else {
        card.transform = CGAffineTransformMake(startScale, 0, 0, startScale,
                                               (pivot.x - center.x) * (1 - startScale),
                                               (pivot.y - center.y) * (1 - startScale));
    }
    AutoACBounce(^{
        backdrop.alpha = 1;
        for (UIView *v in backdrop.subviews) v.transform = CGAffineTransformIdentity;
    }, nil);

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
    // Loại nhanh các điểm chạm ngoài vùng góc trên-trái, tránh hitTest ở mọi lần chạm
    CGFloat topLimit = MAX(window.safeAreaInsets.top, 20) + 90;
    if (point.y > topLimit || point.x > CGRectGetWidth(window.bounds) * 0.6) return NO;
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
    AutoACAttachCommentGestures();
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

#pragma mark - Hook thanh tab (ẩn Shorts)


%hook YTPivotBarView
- (void)layoutSubviews {
    %orig;
    AutoACApplyShortsPreference(self);
}
%end

#pragma mark - Fix Promo

%hook YTCommerceEventGroupHandler
- (void)addEventHandlers {}
%end

#pragma mark - Tự động dọn khi thoát app

static BOOL gDidAutoClean = NO;
static BOOL gBGCleaning = NO;

// Mở app: chỉ xoá nhanh tệp tải xuống bỏ lại trong tmp (lần trước app bị tắt đột ngột), không đụng cache khác
// để không tranh đĩa với lúc YouTube đang tải trang chủ.
static void AutoACAutoCleanOnce(void) {
    if (gDidAutoClean) return;
    gDidAutoClean = YES;
    if (![kPrefs boolForKey:kAutoClearCacheKey]) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *tmp = NSTemporaryDirectory();
        for (NSString *name in [fm contentsOfDirectoryAtPath:tmp error:nil]) {
            if (![name hasPrefix:@"AutoAC-"]) continue;
            NSString *full = [tmp stringByAppendingPathComponent:name];
            if (gHeldDir.length > 0 && [full hasPrefix:gHeldDir]) continue;
            [fm removeItemAtPath:full error:nil];
        }
    });
}

// Đưa app xuống nền (thoát app): dọn tệp cache cũ quá 30 phút, xin hệ thống thêm thời gian chạy nền để dọn cho xong.
// Không xoá cache mạng nên ảnh bìa vẫn còn ở lần mở sau.
static void AutoACCleanOnBackground(void) {
    if (![kPrefs boolForKey:kAutoClearCacheKey] || gBGCleaning || gCleaning) return;
    gBGCleaning = YES;
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    void (^finish)(void) = ^{
        gBGCleaning = NO;
        if (task != UIBackgroundTaskInvalid) { [UIApplication.sharedApplication endBackgroundTask:task]; task = UIBackgroundTaskInvalid; }
    };
    task = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"AutoACClean" expirationHandler:^{ finish(); }];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        AutoACClearCache(NO);
        dispatch_async(dispatch_get_main_queue(), finish);
    });
}

#pragma mark - Chức năng bổ sung theo ytkace (hook qua runtime, tự bỏ qua nếu class/selector không tồn tại)


// Thay method bằng block do `maker` tạo ra. `prefix` là đầu chuỗi type encoding mong đợi
// (vd "B16" = BOOL, không tham số) để không hook nhầm khi YouTube đổi chữ ký.
static BOOL AutoACHook(NSString *className, NSString *selectorName, BOOL classMethod,
                       const char *prefix, AutoACHookMaker maker) {
    Class cls = NSClassFromString(className);
    if (!cls) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    Class target = classMethod ? object_getClass(cls) : cls;
    Method method = class_getInstanceMethod(target, selector);
    if (!method) return NO;
    const char *types = method_getTypeEncoding(method);
    if (prefix && (!types || strncmp(types, prefix, strlen(prefix)) != 0)) return NO;

    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(maker(original, selector));
    if (!class_addMethod(target, selector, replacement, types)) {
        method_setImplementation(method, replacement);
    }
    return YES;
}


// ── Ẩn nhãn "Có quảng cáo trả phí" trên trình phát (tự viết; cùng mục đích với YTNoPaidPromo, repo đó không có giấy phép nên không nhúng) ──
static void AutoACInstallPaidPromoHooks(void) {
    for (NSString *cls in @[@"YTMainAppVideoPlayerOverlayViewController", @"YTInlineMutedPlaybackPlayerOverlayViewController"]) {
        AutoACHook(cls, @"setPaidContentWithPlayerData:", NO, "v24", ^id(IMP original, SEL selector) {
            return ^void(id self_, id data) {
                if ([kPrefs boolForKey:kHidePaidPromoKey]) return;
                if (original) ((void (*)(id, SEL, id))original)(self_, selector, data);
            };
        });
    }
    AutoACHook(@"YTMainAppVideoPlayerOverlayViewController", @"playerOverlayProvider:didInsertPlayerOverlay:", NO, "v32",
               ^id(IMP original, SEL selector) {
        return ^void(id self_, id provider, id overlay) {
            if ([kPrefs boolForKey:kHidePaidPromoKey]) {
                SEL idSel = NSSelectorFromString(@"overlayIdentifier");
                id ident = [overlay respondsToSelector:idSel] ? ((id (*)(id, SEL))objc_msgSend)(overlay, idSel) : nil;
                if ([ident isKindOfClass:NSString.class] && [ident isEqualToString:@"player_overlay_paid_content"]) return;
            }
            if (original) ((void (*)(id, SEL, id, id))original)(self_, selector, provider, overlay);
        };
    });
}

// ── Chặn popup khuyến mãi / nâng cấp Premium (theo ytkace PromoHooks) ──
static BOOL AutoACPromosOff(void) { return [kPrefs boolForKey:kHidePromosKey]; }

static void AutoACInstallPromoHooks(void) {
    for (NSArray *entry in @[@[@"YTMealbarPromoController", @"showMealbarPromoWithEvent:"],
                             @[@"YTPromosheetController", @"presentPromosheetWithEvent:"]]) {
        AutoACHook(entry[0], entry[1], NO, "v24", ^id(IMP original, SEL selector) {
            return ^void(id self_, id event) {
                if (AutoACPromosOff()) return;
                if (original) ((void (*)(id, SEL, id))original)(self_, selector, event);
            };
        });
    }
    for (NSString *name in @[@"showUpgradeDialog", @"showOldUpgradeDialog"]) {
        AutoACHook(@"YTUpgradeController", name, NO, "v16", ^id(IMP original, SEL selector) {
            return ^void(id self_) {
                if (AutoACPromosOff()) return;
                if (original) ((void (*)(id, SEL))original)(self_, selector);
            };
        });
    }
    for (NSArray *entry in @[@[@"YTGlobalConfig", @"shouldShowUpgrade"],
                             @[@"YTGlobalConfig", @"shouldShowUpgradeDialog"],
                             @[@"YTYouThereControllerImpl", @"shouldShowYouTherePrompt"]]) {
        AutoACHook(entry[0], entry[1], NO, "B16", ^id(IMP original, SEL selector) {
            return ^BOOL(id self_) {
                if (AutoACPromosOff()) return NO;
                return original ? ((BOOL (*)(id, SEL))original)(self_, selector) : NO;
            };
        });
    }
}


// ── Bỏ hoạt ảnh logo khi mở app (theo ytkace StartupHooks) ──
static void AutoACFinishStartup(UIViewController *controller) {
    SEL delegateSelector = NSSelectorFromString(@"delegate");
    id delegate = [controller respondsToSelector:delegateSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(controller, delegateSelector) : nil;
    SEL complete = NSSelectorFromString(@"startupAnimationDidComplete");
    if ([delegate respondsToSelector:complete]) {
        ((void (*)(id, SEL))objc_msgSend)(delegate, complete);
        return;
    }
    SEL force = NSSelectorFromString(@"forceDismissStartupAnimationAnimated:");
    if ([delegate respondsToSelector:force]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(delegate, force, NO);
        return;
    }
    [controller dismissViewControllerAnimated:NO completion:nil];
}

static void AutoACInstallStartupHooks(void) {
    for (NSString *cls in @[@"YTStartupAnimationViewController", @"YTRiveStartupAnimationViewController"]) {
        AutoACHook(cls, @"viewDidAppear:", NO, "v", ^id(IMP original, SEL selector) {
            return ^void(UIViewController *self_, BOOL animated) {
                if (original) ((void (*)(id, SEL, BOOL))original)(self_, selector, animated);
                if ([kPrefs boolForKey:kNoLaunchAnimKey]) {
                    dispatch_async(dispatch_get_main_queue(), ^{ AutoACFinishStartup(self_); });
                }
            };
        });
    }
}


// ── Ẩn nút Shorts, bài đăng cộng đồng, thẻ Mix theo accessibilityIdentifier (theo ytkace) ──
static const void *kAutoACHiddenOwnKey = &kAutoACHiddenOwnKey;

static void AutoACSetOwnedHidden(UIView *view, BOOL hide) {
    BOOL owned = objc_getAssociatedObject(view, kAutoACHiddenOwnKey) != nil;
    if (hide) {
        objc_setAssociatedObject(view, kAutoACHiddenOwnKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.hidden = YES;
        view.userInteractionEnabled = NO;
    } else if (owned) {
        objc_setAssociatedObject(view, kAutoACHiddenOwnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.hidden = NO;
        view.userInteractionEnabled = YES;
    }
}

static void AutoACAttachDownloadOverlay(UIView *view);


// Đang ở trình phát Shorts (đặt khi quét thấy lớp Shorts hiển thị): tuyệt đối không ẩn gì của Shorts lúc này
static CFTimeInterval gShortsOnScreenAt = 0;


static void AutoACApplyContentRules(UIView *view) {
    AutoACAttachDownloadOverlay(view);
    NSString *ident = view.accessibilityIdentifier;
    if (ident.length == 0) return;
    // Khi Short đang hiện: ghi lại mã view của lớp phủ (hiện ở Chẩn đoán) và ẩn thẻ sản phẩm/giỏ hàng nếu bật.
    // Chỉ chạy trong khoảng thời gian Short đang trên màn hình, không đụng trang chủ hay danh sách.
    BOOL shortsOn = gShortsOnScreenAt > 0 && CACurrentMediaTime() - gShortsOnScreenAt < 2.5;
    if (shortsOn) {
        if (gOverlaySeen.count < 60 && [kPrefs boolForKey:kDiagKey]) {
            if (!gOverlaySeen) gOverlaySeen = [NSMutableOrderedSet orderedSet];
            [gOverlaySeen addObject:[NSString stringWithFormat:@"%@ · %@", NSStringFromClass(view.class), ident]];
        }
        if ([kPrefs boolForKey:kHideShopTagKey]) {
            for (NSString *w in @[@"shop", @"product", @"cart", @"merch", @"offer"]) {
                if ([ident rangeOfString:w options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    AutoACSetOwnedHidden(view, YES);
                    return;
                }
            }
        }
    }
    // Chỉ còn các nút trong cột nút của Short (id.reel_…). Hàng Short, bài đăng, Mix, game KHÔNG ẩn ở đây nữa:
    // ẩn view/ô trong danh sách để lại khoảng trắng lớn khi lướt; việc đó do bộ lọc dữ liệu lo.
    if ([ident rangeOfString:@"id.reel_" options:NSCaseInsensitiveSearch | NSAnchoredSearch].location == NSNotFound) return;
    static NSDictionary<NSString *, NSString *> *rules;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rules = @{@"id.reel_like_button": kShortsLikeKey,
                  @"id.reel_comment_button": kShortsCommentKey,
                  @"id.reel_share_button": kShortsShareKey,
                  @"id.reel_remix_button": kShortsRemixKey,
                  @"id.reel_pivot_button": kShortsSoundKey};
    });
    NSString *low = ident.lowercaseString;
    NSString *key = rules[low];
    if (!key && ([low containsString:@"save"] || [low containsString:@"playlist"] || [low containsString:@"bookmark"]))
        key = kShortsSaveKey;   // nút Lưu của Shorts: nhận theo tên định danh trong cột nút "id.reel_…"
    if (!key) return;
    AutoACSetOwnedHidden(view, [kPrefs boolForKey:key]);
}

// ── Ẩn Short, bài đăng, Mix, game khỏi trang chủ: làm theo YTLite (đã đối chiếu mã nguồn YTLite) ──
// 1) elementData của phần tử trả nil cho hàng Short (YTLite dùng đúng ba mẫu: shorts_shelf.eml, shorts_video_cell.eml, 6Shorts, trừ lịch sử);
//    kết quả được nhớ theo từng phần tử nên chỉ in mô tả một lần.
// 2) cellForItemAtIndexPath: ô hàng Short bị XOÁ khỏi danh sách (deleteItemsAtIndexPaths) thay vì ẩn, nên không để lại khoảng trắng.
//    Bản trước ẩn ô bằng thuộc tính hidden: ô vẫn chiếm chỗ nên trang Đăng ký trắng một khoảng lớn.
// Chỉ lọc ở tab Trang chủ. Đăng ký, Thư viện và mọi tab khác giữ nguyên danh sách của YouTube: ở đó bỏ phần tử hay ô
// để lại khoảng trắng cỡ một ô video. Tab hiện tại đọc từ thanh tab (chỉ ở luồng chính, nhớ 0,5 giây) và được chốt ngay lúc bấm đổi tab (ACGPivotItemSetSelected);
// không đọc được tab thì KHÔNG lọc.
static void AutoACRefreshListScope(void) {
    static CFTimeInterval at = -10;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - at < 0.5 || now < gListScopeLockUntil || ![NSThread isMainThread]) return;
    at = now;
    UIWindow *w = AutoACKeyWindow();
    if (!w) return;
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    ACGCollectPivotItems(w, items);
    NSString *ident = nil;
    for (UIView *item in items) {
        if (!ACGPivotItemSelected(item)) continue;
        ident = ACGPivotItemIdentifier(item);
        break;
    }
    gListTabIdent = ident;
    // Chỉ lọc khi CHẮC CHẮN là Trang chủ. Không đọc được tab thì KHÔNG lọc: lọc nhầm ở Đăng ký/Thư viện để lại khoảng trắng cỡ một ô video.
    gListFilterAllowed = [ident isEqualToString:@"FEwhat_to_watch"];
    if (ident.length == 0) at = now - 0.3;   // chưa đọc được: thử lại sau 0,2 giây thay vì chờ 0,5 giây
}

// Thẻ mời dùng thử / mua Premium (YouTube Music Premium...) nhận theo mã định danh của phần tử.
// "statement_banner" là thẻ YTLite cũng gỡ; các mã còn lại là tên thường gặp của thẻ mời nâng cấp.
static BOOL AutoACIsPremiumUpsellIdent(NSString *ident) {
    if (ident.length == 0) return NO;
    for (NSString *w in @[@"statement_banner", @"music_premium", @"youtube_music_premium", @"premium_upsell", @"music_upsell",
                          @"ytm_upsell", @"premium_promo", @"premium_banner"]) {
        if ([ident rangeOfString:w options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}
static void AutoACNotePremiumIdent(NSString *ident) {
    if (ident.length == 0 || ![kPrefs boolForKey:kDiagKey]) return;
    for (NSString *w in @[@"premium", @"music", @"upsell", @"banner", @"short", @"reel"]) {
        if ([ident rangeOfString:w options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        if (!gPremiumSeen) gPremiumSeen = [NSMutableOrderedSet orderedSet];
        if (gPremiumSeen.count < 12) [gPremiumSeen addObject:ident];
        return;
    }
}

static void AutoACInstallShortsShelfHooks(void) {
    AutoACHook(@"YTIElementRenderer", @"elementData", NO, "@16", ^id(IMP original, SEL selector) {
        return ^id(id self_) {
            static BOOL fShelf, fPost, fMix, fGame, fBanner;
            static CFTimeInterval at = -10;
            CFTimeInterval now = CACurrentMediaTime();
            if (now - at > 1.0) {   // hàm này chạy rất nhiều lần khi lướt: đọc cài đặt nhớ 1 giây
                fShelf = [kPrefs boolForKey:kHideShortsShelfKey]; fPost = [kPrefs boolForKey:kHideCommunityKey];
                fMix = [kPrefs boolForKey:kHideMixesKey]; fGame = [kPrefs boolForKey:kHideGamesKey];
                fBanner = [kPrefs boolForKey:kHidePromosKey];
                at = now;
            }
            // Chưa đọc được tab hiện tại (gListTabIdent rỗng): vẫn cho ẩn hàng Short như nhánh cellForItemAtIndexPath bên dưới,
            // còn bài đăng/Mix/game/banner thì không lọc để khỏi để lại khoảng trắng
            BOOL shelfOnlyScope = !gListFilterAllowed && fShelf && gListTabIdent.length == 0;
            if (!(fShelf || fPost || fMix || fGame || fBanner) || !(gListFilterAllowed || shelfOnlyScope) || (gShortsOnScreenAt > 0 && now - gShortsOnScreenAt < 2.5))
                return ((id (*)(id, SEL))original)(self_, selector);
            static const void *kVerdictKey = &kVerdictKey;
            NSNumber *verdict = objc_getAssociatedObject(self_, kVerdictKey);   // 0 giữ, 2 hàng Short, 3 bài đăng, 4 Mix, 5 game
            if (!verdict) {
                NSString *d = [self_ description];
                NSInteger v = 0;
                if (d.length && ![d containsString:@"history*"]) {
                    if ([d containsString:@"shorts_shelf.eml"] || [d containsString:@"shorts_video_cell.eml"] || [d containsString:@"6Shorts"] ||
                        [d containsString:@"reel_shelf.eml"] || [d containsString:@"shorts_grid.eml"] || [d containsString:@"shorts_lockup_shelf"]) v = 2;
                    else if ([d containsString:@"id.ui.backstage.original_post"] || [d containsString:@"id_ui_backstage_original_post"] ||
                             [d containsString:@"backstage_original_post"]) v = 3;
                    else if ([d containsString:@"feed_nudge"]) v = 4;
                    else if ([d containsString:@"playables"] || [d containsString:@"mini_app"] || [d containsString:@"game_shelf"]) v = 5;
                    else if (AutoACIsPremiumUpsellIdent(d)) v = 6;
                }
                verdict = @(v);
                objc_setAssociatedObject(self_, kVerdictKey, verdict, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (shelfOnlyScope && verdict.integerValue != 2) return ((id (*)(id, SEL))original)(self_, selector);
            switch (verdict.integerValue) {
                case 2: if (fShelf) { gDropShelf++; return nil; } break;
                case 3: if (fPost) { gDropPost++; return nil; } break;
                case 4: if (fMix) { gDropMix++; return nil; } break;
                case 5: if (fGame) { gDropGame++; return nil; } break;
                case 6: if (fBanner) { gDropBanner++; return nil; } break;
            }
            return ((id (*)(id, SEL))original)(self_, selector);
        };
    });
    AutoACHook(@"YTAsyncCollectionView", @"cellForItemAtIndexPath:", NO, "@", ^id(IMP original, SEL selector) {
        return ^id(id self_, NSIndexPath *indexPath) {
            UICollectionViewCell *cell = ((id (*)(id, SEL, id))original)(self_, selector, indexPath);
            AutoACRefreshListScope();
            BOOL bannerOn = [kPrefs boolForKey:kHidePromosKey];
            // Xoá hàng Short ở mức ô (deleteItemsAtIndexPaths) không để lại khoảng trống, nên khi chưa đọc được tab hiện tại vẫn cho phép
            // (trước đây chưa đọc được tab thì bộ lọc tắt hẳn và "Ẩn video Short" không chạy)
            BOOL shelfOn = (gListFilterAllowed || gListTabIdent.length == 0) && [kPrefs boolForKey:kHideShortsShelfKey];
            if (!cell || !(bannerOn || shelfOn || [kPrefs boolForKey:kDiagKey])) return cell;
            if (gShortsOnScreenAt > 0 && CACurrentMediaTime() - gShortsOnScreenAt < 2.5) return cell;
            BOOL shelf = shelfOn && [cell isKindOfClass:NSClassFromString(@"YTReelShelfCell")];
            BOOL upsell = NO;
            if ([cell respondsToSelector:@selector(node)]) {
                id node = ((id (*)(id, SEL))objc_msgSend)(cell, @selector(node));
                NSString *ident = [node respondsToSelector:@selector(accessibilityIdentifier)] ? [node accessibilityIdentifier] : nil;
                gFeedCellsSeen++;
                AutoACNotePremiumIdent(ident);
                if (!shelf && shelfOn && ident.length > 0) {   // ident nil thì rangeOfString trả {0,0} chứ không phải NSNotFound
                    shelf = [ident isEqualToString:@"eml.shorts-grid"] || [ident isEqualToString:@"eml.shorts-shelf"] ||
                            ([ident rangeOfString:@"shorts" options:NSCaseInsensitiveSearch].location != NSNotFound &&
                             ([ident rangeOfString:@"shelf" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                              [ident rangeOfString:@"grid" options:NSCaseInsensitiveSearch].location != NSNotFound)) ||
                            [ident rangeOfString:@"reel_shelf" options:NSCaseInsensitiveSearch].location != NSNotFound;
                }
                upsell = bannerOn && AutoACIsPremiumUpsellIdent(ident);
            }
            if ((shelf || upsell) && indexPath && [self_ respondsToSelector:@selector(deleteItemsAtIndexPaths:)]) {
                @try { [self_ deleteItemsAtIndexPaths:@[indexPath]]; } @catch (__unused NSException *e) {}
                if (shelf) gDropShelf++; else gDropBanner++;
                return ((id (*)(id, SEL, id))original)(self_, selector, indexPath);   // như YTLite: gọi lại sau khi xoá
            }
            return cell;
        };
    });
    // Thẻ khuyến mãi / sản phẩm dưới thông tin Short: YTLite chặn bằng cách không gán phần tử (setActionElement:), nên không để lại ô trống
    AutoACHook(@"YTReelWatchHeaderView", @"setActionElement:", NO, "v", ^id(IMP original, SEL selector) {
        return ^void(id self_, id element) {
            if ([kPrefs boolForKey:kHideShopTagKey]) return;
            ((void (*)(id, SEL, id))original)(self_, selector, element);
        };
    });
}


#pragma mark - Kính lỏng cho thanh trên, bảng chọn và trình phát
// Tự viết lại ý tưởng của GlassChrome / GlassSheets / PlayerGlass trong ytkace (giấy phép MIT): đặt lớp UIGlassEffect phía sau
// các phần giao diện gốc của YouTube. Chỉ chạy khi máy có UIGlassEffect (iOS 26+); mỗi phần có công tắc riêng và tự gỡ khi tắt.

static const void *kAGlassAssoc = &kAGlassAssoc;
static const void *kAGlassLeftAssoc = &kAGlassLeftAssoc;

static BOOL AutoACGlassOn(NSString *key) { return ACGLiquidGlassAvailable() && [kPrefs boolForKey:key]; }

static UIVisualEffectView *AutoACMakeGlassView(void) {
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:ACGMakeGlassEffect(NO)];
    glass.userInteractionEnabled = NO;
    glass.clipsToBounds = YES;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    return glass;
}

static UIView *AutoACFindClass(UIView *root, NSString *name, int depth) {
    if ([NSStringFromClass(root.class) isEqualToString:name]) return root;
    if (depth <= 0) return nil;
    for (UIView *sub in root.subviews) {
        UIView *found = AutoACFindClass(sub, name, depth - 1);
        if (found) return found;
    }
    return nil;
}

// ── Trình phát: nền mờ YTFrostedGlassView của các nút nổi → kính lỏng ──
static BOOL AutoACInPlayerControls(UIView *view) {
    int depth = 0;
    for (UIView *current = view.superview; current != nil && depth < 10; current = current.superview, depth++) {
        NSString *name = NSStringFromClass(current.class);
        if ([name containsString:@"Overlay"] || [name containsString:@"Player"] || [name containsString:@"Fullscreen"] ||
            [name containsString:@"Watch"]) return YES;
    }
    return NO;
}

static void AutoACApplyPlayerGlass(UIView *frosted) {
    UIVisualEffectView *glass = objc_getAssociatedObject(frosted, kAGlassAssoc);
    NSMutableArray<UIView *> *layers = [NSMutableArray array];
    for (NSString *key in @[@"_blurEffectView", @"_overlayView"]) {
        id v = nil;
        @try { v = [frosted valueForKey:key]; } @catch (__unused NSException *e) {}
        if ([v isKindOfClass:UIView.class]) [layers addObject:v];
    }
    if (!(AutoACGlassOn(kGlassPlayerKey) && AutoACInPlayerControls(frosted))) {
        if (glass) {
            [glass removeFromSuperview];
            objc_setAssociatedObject(frosted, kAGlassAssoc, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            for (UIView *v in layers) v.alpha = 1.0;
        }
        return;
    }
    if (!glass) {
        glass = AutoACMakeGlassView();
        objc_setAssociatedObject(frosted, kAGlassAssoc, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *v in layers) v.alpha = 0.0;
    if (glass.superview != frosted) [frosted insertSubview:glass atIndex:0];
    glass.frame = frosted.bounds;
    CGFloat capsule = MIN(CGRectGetWidth(frosted.bounds), CGRectGetHeight(frosted.bounds)) * 0.5;
    CGFloat radius = frosted.layer.cornerRadius;
    glass.layer.cornerRadius = radius > 0.0 ? MIN(radius, capsule) : capsule;
    frosted.backgroundColor = UIColor.clearColor;
}

// ── Thanh trên: viên kính sau cụm nút bên phải (tìm kiếm, thông báo…) và vòng tròn sau nút nhỏ bên trái (quay lại) ──
static void AutoACPlaceGlassBehind(UIVisualEffectView *glass, UIView *view, CGRect frame, CGFloat radius) {
    UIView *host = view.superview;
    if (!host) return;
    if (glass.superview != host) {
        [glass removeFromSuperview];
        [host insertSubview:glass belowSubview:view];
    } else {
        NSUInteger gi = [host.subviews indexOfObjectIdenticalTo:glass], vi = [host.subviews indexOfObjectIdenticalTo:view];
        if (gi == NSNotFound || vi == NSNotFound || gi + 1 != vi) [host insertSubview:glass belowSubview:view];
    }
    glass.frame = frame;
    glass.layer.cornerRadius = radius;
}

static void AutoACCollectControlsUnion(UIView *view, UIView *space, CGRect *rect, NSInteger *count) {
    for (UIView *sub in view.subviews) {
        if (sub.hidden || sub.alpha <= 0.01 || CGRectIsEmpty(sub.bounds)) continue;
        if ([sub isKindOfClass:UIControl.class]) {
            CGRect r = [space convertRect:sub.bounds fromView:sub];
            *rect = *count == 0 ? r : CGRectUnion(*rect, r);
            (*count)++;
            continue;
        }
        AutoACCollectControlsUnion(sub, space, rect, count);
    }
}

static void AutoACUpdateRightGlass(UIView *container) {
    UIVisualEffectView *glass = objc_getAssociatedObject(container, kAGlassAssoc);
    CGRect rect = CGRectZero;
    NSInteger count = 0;
    BOOL on = AutoACGlassOn(kGlassTopKey) && container.window && container.superview && !CGRectIsEmpty(container.bounds);
    if (on) AutoACCollectControlsUnion(container, container, &rect, &count);
    if (!on || count == 0) {
        if (glass) { [glass removeFromSuperview]; objc_setAssociatedObject(container, kAGlassAssoc, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        return;
    }
    if (!glass) {
        glass = AutoACMakeGlassView();
        objc_setAssociatedObject(container, kAGlassAssoc, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect area = CGRectIntersection(CGRectInset(rect, -8.0, -4.0), CGRectInset(container.bounds, -10.0, -6.0));
    CGFloat height = MAX(40.0, CGRectGetHeight(area)), width = MAX(height, CGRectGetWidth(area));
    CGRect local = CGRectMake(CGRectGetMidX(area) - width * 0.5, CGRectGetMidY(area) - height * 0.5, width, height);
    AutoACPlaceGlassBehind(glass, container, [container convertRect:local toView:container.superview], height * 0.5);
}

static BOOL AutoACHeaderButtonHasContent(UIButton *b) {
    if (b.hidden || b.alpha <= 0.01) return NO;
    if (b.currentImage || b.currentTitle.length || b.currentBackgroundImage) return YES;
    for (UIView *sub in b.subviews) {
        if (sub.hidden || sub.alpha <= 0.01 || CGRectIsEmpty(sub.bounds)) continue;
        if ([sub isKindOfClass:UIImageView.class] && ((UIImageView *)sub).image) return YES;
    }
    return NO;
}

static void AutoACCollectHeaderButtons(UIView *view, NSMutableArray<UIButton *> *out) {
    for (UIView *sub in view.subviews) {
        if (sub.hidden || sub.alpha <= 0.01 || CGRectIsEmpty(sub.bounds)) continue;
        if ([sub isKindOfClass:UIButton.class] && CGRectGetWidth(sub.bounds) <= 64.0 && CGRectGetHeight(sub.bounds) <= 64.0 &&
            AutoACHeaderButtonHasContent((UIButton *)sub)) { [out addObject:(UIButton *)sub]; continue; }
        AutoACCollectHeaderButtons(sub, out);
    }
}

static void AutoACUpdateHeaderGlass(UIView *header) {
    UIVisualEffectView *glass = objc_getAssociatedObject(header, kAGlassLeftAssoc);
    BOOL on = AutoACGlassOn(kGlassTopKey) && header.window && !CGRectIsEmpty(header.bounds);
    UIButton *best = nil;
    if (on) {
        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        AutoACCollectHeaderButtons(header, buttons);
        CGFloat width = CGRectGetWidth(header.bounds), bestX = CGFLOAT_MAX;
        for (UIButton *b in buttons) {
            CGRect f = [header convertRect:b.bounds fromView:b];
            if (CGRectGetMidX(f) >= width * 0.5 || CGRectGetMinX(f) > width * 0.28) continue;
            if (CGRectGetMinX(f) < bestX) { bestX = CGRectGetMinX(f); best = b; }
        }
    }
    if (!best) {
        if (glass) { [glass removeFromSuperview]; objc_setAssociatedObject(header, kAGlassLeftAssoc, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        return;
    }
    if (!glass) {
        glass = AutoACMakeGlassView();
        objc_setAssociatedObject(header, kAGlassLeftAssoc, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect f = [header convertRect:best.bounds fromView:best];
    CGFloat d = MAX(40.0, MAX(CGRectGetWidth(f), CGRectGetHeight(f)));
    CGRect circle = CGRectMake(CGRectGetMidX(f) - d * 0.5, CGRectGetMidY(f) - d * 0.5, d, d);
    UIView *host = best.superview;
    if (!host) return;
    if (glass.superview != host) { [glass removeFromSuperview]; [host insertSubview:glass belowSubview:best]; }
    glass.frame = [host convertRect:circle fromView:header];
    glass.layer.cornerRadius = d * 0.5;
}

// ── Bảng chọn, hộp thoại: nền kính lỏng thay nền đặc ──
static BOOL AutoACColorSolid(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    return c != nil && [c getRed:&r green:&g blue:&b alpha:&a] && a > 0.3;
}

static void AutoACClearELMBackground(UIView *view, UIView *sheet, int depth) {
    if (depth > 4) return;
    for (UIView *sub in view.subviews) {
        if (![NSStringFromClass(sub.class) isEqualToString:@"_ASDisplayView"]) continue;
        if (AutoACColorSolid(sub.backgroundColor) && CGRectGetWidth(sub.bounds) >= CGRectGetWidth(sheet.bounds) * 0.9 &&
            CGRectGetHeight(sub.bounds) >= 40.0) {
            id node = nil;
            @try { node = [sub valueForKey:@"asyncdisplaykit_node"]; } @catch (__unused NSException *e) {}
            if ([node respondsToSelector:@selector(setBackgroundColor:)])
                ((void (*)(id, SEL, id))objc_msgSend)(node, @selector(setBackgroundColor:), UIColor.clearColor);
            else sub.backgroundColor = UIColor.clearColor;
        }
        AutoACClearELMBackground(sub, sheet, depth + 1);
    }
}

static void AutoACClearSheetBackgrounds(UIView *view, UIView *sheet, UIView *glass, int depth) {
    if (depth > 10) return;
    static NSSet<NSString *> *containers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        containers = [NSSet setWithArray:@[@"YTDraggableView", @"YTDialogContainerScrollView", @"GOODialogView", @"YTContextualWrapView",
                                           @"YTActionSheetHeaderView", @"UIScrollView", @"GOODialogContentView", @"YTMinimumWidthDialogView"]];
    });
    for (UIView *sub in view.subviews) {
        if (sub == glass) continue;
        NSString *name = NSStringFromClass(sub.class);
        if ([name hasSuffix:@"ELMView"]) { AutoACClearELMBackground(sub, sheet, 0); continue; }
        if ([name hasPrefix:@"_AS"] || [name hasPrefix:@"AS"]) continue;
        if ([containers containsObject:name] && AutoACColorSolid(sub.backgroundColor)) sub.backgroundColor = UIColor.clearColor;
        AutoACClearSheetBackgrounds(sub, sheet, glass, depth + 1);
    }
}

static void AutoACApplyPanelGlass(UIView *sheet, CGFloat fallbackRadius, BOOL allCorners) {
    UIVisualEffectView *glass = objc_getAssociatedObject(sheet, kAGlassAssoc);
    if (!glass) {
        glass = AutoACMakeGlassView();
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(sheet, kAGlassAssoc, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glass.superview != sheet) [sheet insertSubview:glass atIndex:0];
    else if (sheet.subviews.firstObject != glass) [sheet sendSubviewToBack:glass];
    glass.frame = sheet.bounds;
    CGFloat radius = sheet.layer.cornerRadius > 0.0 ? sheet.layer.cornerRadius : fallbackRadius;
    glass.layer.cornerRadius = radius;
    glass.layer.maskedCorners = allCorners ? (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner)
        : (sheet.layer.cornerRadius > 0.0 ? sheet.layer.maskedCorners : (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner));
    sheet.backgroundColor = UIColor.clearColor;
    AutoACClearSheetBackgrounds(sheet, sheet, glass, 0);
}

static void AutoACClearShadows(UIView *view, UIView *stop) {
    for (UIView *c = view; c != nil && c != stop; c = c.superview) if (c.layer.shadowOpacity > 0.0) c.layer.shadowOpacity = 0.0;
}

static void AutoACApplySheetGlass(UIViewController *controller) {
    if (!AutoACGlassOn(kGlassSheetKey) || !controller.isViewLoaded) return;
    UIView *sheet = AutoACFindClass(controller.view, @"YTDraggableView", 8);
    if (!sheet) {
        sheet = AutoACFindClass(controller.view, @"YTContextualWrapView", 8);
        if (sheet) AutoACClearShadows(sheet, controller.view.window);
    }
    if (!sheet || CGRectIsEmpty(sheet.bounds)) return;
    AutoACApplyPanelGlass(sheet, 24.0, NO);
}

static void AutoACApplyModalGlass(UIView *modal) {
    if (!AutoACGlassOn(kGlassSheetKey) || !modal.window) return;
    UIView *dialog = nil;
    @try { dialog = [modal valueForKey:@"_dialogView"]; } @catch (__unused NSException *e) {}
    if (![dialog isKindOfClass:UIView.class] || CGRectIsEmpty(dialog.bounds)) return;
    AutoACClearShadows(dialog, modal.superview);
    dialog.layer.shadowOpacity = 0.0;
    AutoACApplyPanelGlass(dialog, 28.0, YES);
    if (dialog.layer.cornerRadius < 12.0) { dialog.layer.cornerRadius = 28.0; dialog.layer.cornerCurve = kCACornerCurveContinuous; }
    dialog.clipsToBounds = YES;
}

static void AutoACApplySheetGlassLater(UIViewController *controller) {
    __weak UIViewController *weak = controller;
    for (NSNumber *delay in @[@0.05, @0.15, @0.3, @0.6, @1.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *c = weak;
            if (c && c.view.window) AutoACApplySheetGlass(c);
        });
    }
}

static void AutoACInstallGlassChromeHooks(void) {
    if (!ACGLiquidGlassAvailable()) return;
    // Trình phát
    for (NSString *name in @[@"layoutSubviews", @"didMoveToWindow"]) {
        AutoACHook(@"YTFrostedGlassView", name, NO, NULL, ^id(IMP original, SEL selector) {
            return ^void(UIView *self_) {
                if (original) ((void (*)(id, SEL))original)(self_, selector);
                if (selector == @selector(didMoveToWindow) && self_.window) [self_ setNeedsLayout];
                AutoACApplyPlayerGlass(self_);
            };
        });
    }
    // Thanh trên
    for (NSString *name in @[@"layoutSubviews", @"didMoveToWindow", @"didMoveToSuperview"]) {
        AutoACHook(@"YTRightNavigationButtons", name, NO, NULL, ^id(IMP original, SEL selector) {
            return ^void(UIView *self_) {
                if (original) ((void (*)(id, SEL))original)(self_, selector);
                AutoACUpdateRightGlass(self_);
            };
        });
    }
    for (NSString *name in @[@"layoutSubviews", @"didMoveToWindow"]) {
        AutoACHook(@"YTHeaderView", name, NO, NULL, ^id(IMP original, SEL selector) {
            return ^void(UIView *self_) {
                if (original) ((void (*)(id, SEL))original)(self_, selector);
                AutoACUpdateHeaderGlass(self_);
            };
        });
    }
    // Bảng chọn (view controller)
    for (NSString *cls in @[@"YTBottomSheetController", @"YTContextualSheetViewController"]) {
        AutoACHook(cls, @"viewWillLayoutSubviews", NO, NULL, ^id(IMP original, SEL selector) {
            return ^void(UIViewController *self_) {
                if (original) ((void (*)(id, SEL))original)(self_, selector);
                if (!AutoACGlassOn(kGlassSheetKey)) return;
                __weak UIViewController *weak = self_;
                dispatch_async(dispatch_get_main_queue(), ^{ if (weak) AutoACApplySheetGlass(weak); });
            };
        });
        AutoACHook(cls, @"viewWillAppear:", NO, NULL, ^id(IMP original, SEL selector) {
            return ^void(UIViewController *self_, BOOL animated) {
                if (original) ((void (*)(id, SEL, BOOL))original)(self_, selector, animated);
                if (!AutoACGlassOn(kGlassSheetKey)) return;
                [self_.view layoutIfNeeded];
                AutoACApplySheetGlass(self_);
            };
        });
        AutoACHook(cls, @"viewDidAppear:", NO, NULL, ^id(IMP original, SEL selector) {
            return ^void(UIViewController *self_, BOOL animated) {
                if (original) ((void (*)(id, SEL, BOOL))original)(self_, selector, animated);
                AutoACApplySheetGlass(self_);
                AutoACApplySheetGlassLater(self_);
            };
        });
    }
    AutoACHook(@"YTContextualSheetPresentationController", @"presentationTransitionWillBegin", NO, NULL, ^id(IMP original, SEL selector) {
        return ^void(UIPresentationController *self_) {
            if (original) ((void (*)(id, SEL))original)(self_, selector);
            UIViewController *presented = self_.presentedViewController;
            [presented.view layoutIfNeeded];
            AutoACApplySheetGlass(presented);
        };
    });
    AutoACHook(@"YTContextualSheetPresentationController", @"containerViewDidLayoutSubviews", NO, NULL, ^id(IMP original, SEL selector) {
        return ^void(UIPresentationController *self_) {
            if (original) ((void (*)(id, SEL))original)(self_, selector);
            AutoACApplySheetGlass(self_.presentedViewController);
        };
    });
    // Hộp thoại
    for (NSArray<NSString *> *entry in @[@[@"GOOAlertView", @"layoutSubviews"], @[@"GOOAlertView", @"revealDialog"],
                                         @[@"YTAlertView", @"layoutSubviews"],
                                         @[@"YTReportFormModalAlertView", @"layoutSubviews"], @[@"YTReportFormModalAlertView", @"revealDialog"],
                                         @[@"GOOModalView", @"show"], @[@"GOOModalView", @"reposition"]]) {
        AutoACHook(entry[0], entry[1], NO, NULL, ^id(IMP original, SEL selector) {
            return ^void(UIView *self_) {
                if (original) ((void (*)(id, SEL))original)(self_, selector);
                AutoACApplyModalGlass(self_);
            };
        });
    }
}

static void AutoACInstallContentHooks(void) {
    AutoACInstallShortsShelfHooks();
    AutoACHook(@"YTReelWatchRootView", @"layoutSubviews", NO, "v", ^id(IMP original, SEL selector) {
        return ^void(UIView *self_) {
            if (original) ((void (*)(id, SEL))original)(self_, selector);
            gACGReelRoot = self_;
            ACGExtendShortsRoot(self_);
        };
    });
    AutoACHook(@"_ASDisplayView", @"didMoveToWindow", NO, "v", ^id(IMP original, SEL selector) {
        return ^void(UIView *self_) {
            if (original) ((void (*)(id, SEL))original)(self_, selector);
            AutoACApplyContentRules(self_);
        };
    });
    AutoACHook(@"_ASDisplayView", @"setAccessibilityIdentifier:", NO, "v", ^id(IMP original, SEL selector) {
        return ^void(UIView *self_, NSString *identifier) {
            if (original) ((void (*)(id, SEL, id))original)(self_, selector, identifier);
            AutoACApplyContentRules(self_);
        };
    });
    for (NSString *cls in @[@"YTReelPausedStateCarouselView", @"YTReelPlayerPausedStateView"]) {
        AutoACHook(cls, @"layoutSubviews", NO, "v", ^id(IMP original, SEL selector) {
            return ^void(UIView *self_) {
                if (original) ((void (*)(id, SEL))original)(self_, selector);
                AutoACSetOwnedHidden(self_, [kPrefs boolForKey:kShortsPauseCardKey]);
            };
        });
    }
}


#pragma mark - Nút AutoAC trên trình phát (theo cách ytkace gắn nút vào lớp điều khiển)


// Mở bảng chức năng; `onlyTitles` != nil thì chỉ liệt kê các mục có tên trong danh sách (dùng cho Shorts)
static void AutoACShowPlayerMenuFiltered(NSArray<NSString *> *onlyTitles) {
    NSMutableArray<AutoACItem *> *list = [NSMutableArray array];
    for (AutoACItem *i in AutoACBuildItems()) {
        if (![i.category isEqualToString:AutoACT(@"Tải xuống")] || !i.action) continue;
        if (onlyTitles && ![onlyTitles containsObject:i.title]) continue;
        [list addObject:i];
    }
    NSLocale *vi = [NSLocale localeWithLocaleIdentifier:@"vi"];
    [list sortUsingComparator:^NSComparisonResult(AutoACItem *a, AutoACItem *b) {
        return [a.title compare:b.title options:0 range:NSMakeRange(0, a.title.length) locale:vi];
    }];
    if (list.count == 0) return;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (AutoACItem *i in list) [names addObject:i.title];
    AutoACPresentSheet(nil, nil, names, ^(NSInteger idx) {
        void (^action)(void) = list[idx].action;
        // chờ bảng chọn đóng hẳn rồi mới chạy, vì nhiều chức năng lại mở bảng chọn khác
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ if (action) action(); });
    });
}


// Điểm vào duy nhất cho mọi nút tải (nút phủ lên nút gốc, nút nổi trong video, nút nổi trong Shorts):
// xác định đúng video rồi mở cùng một bảng tải.
//   inShorts = YES: lấy mã Short đang phát từ lớp Shorts chứa nút.
//   inShorts = NO : lấy video của trình phát đang hoạt động, nếu không có mới thử dò từ nút.
static NSString *AutoACShortsVideoID(UIView *from);
static NSString *gShortsLastID = nil;
static void AutoACOpenDownloadMenu(UIView *from, BOOL inShorts) {
    AutoACSetPopAnchorFromView(from);
    gVideoIDOverride = nil;   // bỏ mã cũ để không tải nhầm video trước đó
    NSString *vid = nil;
    if (inShorts) {
        vid = from ? AutoACShortsVideoID(from) : nil;
        if (vid.length == 0) vid = AutoACCurrentVideoID();
        if (vid.length == 0) vid = gShortsLastID;
    } else {
        vid = AutoACCurrentVideoID();
        if (vid.length == 0 && from) vid = AutoACShortsVideoID(from);
    }
    if (vid.length == 0) {
        AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor, AutoACT(@"Chưa nhận diện được video"),
                      AutoACT(@"Chờ video phát vài giây rồi thử lại"), 2.4);
        return;
    }
    if (inShorts) gShortsLastID = [vid copy];
    gVideoIDOverride = vid;
    AutoACShowPlayerMenuFiltered(@[AutoACT(@"Tải video"), AutoACT(@"Tải âm thanh"), AutoACT(@"Sao chép"), AutoACT(@"Lưu ảnh bìa")]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([gVideoIDOverride isEqualToString:vid]) gVideoIDOverride = nil;
    });
}

// Tạo nút tròn nổi; đặt bằng frame (không dùng Auto Layout) để không phải bố cục lại trong layoutSubviews
static const CGFloat kFloatSize = 30;   // cỡ nút nổi, gần bằng icon gốc của YouTube
static UIButton *AutoACMakeFloatingButton(NSString *symbol, CGFloat glyph, void (^tap)(void)) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.accessibilityLabel = @"AutoAC";
    button.tintColor = UIColor.whiteColor;
    button.layer.shadowColor = UIColor.blackColor.CGColor;
    button.layer.shadowOpacity = 0.55f;
    button.layer.shadowRadius = 2.5f;
    button.layer.shadowOffset = CGSizeZero;
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:glyph weight:UIImageSymbolWeightRegular];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { tap(); }]
     forControlEvents:UIControlEventTouchUpInside];
    return button;
}

// ── Phủ nút AutoAC lên nút "Tải xuống" gốc của YouTube dưới video ──
static const char kAutoACDLOverlayKey = 0;
static NSHashTable<UIView *> *gDLOverlays = nil;

static BOOL AutoACViewInActionBar(UIView *view) {
    NSInteger depth = 0;
    for (UIView *v = view.superview; v && depth < 14; v = v.superview, depth++) {
        NSString *ident = v.accessibilityIdentifier.lowercaseString;
        if ([ident containsString:@"action_bar"] || [NSStringFromClass(v.class) containsString:@"ActionBar"]) return YES;
    }
    return NO;
}

static void AutoACAttachDownloadOverlay(UIView *view) {
    if (view.accessibilityIdentifier.length == 0 && view.accessibilityLabel.length == 0) return;   // phần lớn view không có nhãn: bỏ qua sớm, đỡ tốn CPU
    NSString *ident = view.accessibilityIdentifier.lowercaseString ?: @"";
    NSString *label = view.accessibilityLabel.lowercaseString ?: @"";
    BOOL byIdent = [ident containsString:@"offline"] || [ident containsString:@"download"];
    BOOL byLabel = [label isEqualToString:AutoACT(@"tải xuống")] || [label isEqualToString:@"download"];
    if (!(byIdent || byLabel)) return;
    if ([ident containsString:@"autoac"]) return;
    UIButton *overlay = objc_getAssociatedObject(view, &kAutoACDLOverlayKey);
    if (overlay) {
        overlay.hidden = ![kPrefs boolForKey:kPlayerButtonKey];
        if (!CGRectEqualToRect(overlay.frame, view.bounds)) overlay.frame = view.bounds;   // nút gốc đổi cỡ thì phủ lại cho khớp
        if (view.subviews.lastObject != overlay) [view bringSubviewToFront:overlay];
        return;
    }
    if (![kPrefs boolForKey:kPlayerButtonKey] || !AutoACViewInActionBar(view)) return;
    AutoACTrace("attach download overlay");
    overlay = [UIButton buttonWithType:UIButtonTypeCustom];
    overlay.accessibilityIdentifier = @"AutoACDownloadOverlay";
    overlay.accessibilityLabel = AutoACT(@"Tải xuống");
    overlay.backgroundColor = UIColor.clearColor;
    overlay.frame = view.bounds;
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    __weak UIView *weakView = view;
    [overlay addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        AutoACOpenDownloadMenu(weakView, NO);
    }] forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:overlay];
    objc_setAssociatedObject(view, &kAutoACDLOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!gDLOverlays) gDLOverlays = [NSHashTable weakObjectsHashTable];
    [gDLOverlays addObject:overlay];
}

// ── Nút tải trong Shorts (theo cách ytkace: gắn vào lớp phủ Shorts đang hiển thị, đặt bằng frame) ──
static UIButton *gShortsButton = nil;

static id AutoACObj(id receiver, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        SEL selector = NSSelectorFromString(name);
        if ([receiver respondsToSelector:selector]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
            if (value) return value;
        }
    }
    return nil;
}

// Tìm player response của Short từ một view/controller (đi dần qua các đối tượng liên quan, như ytkace)
static id AutoACShortsResponse(id object, NSHashTable *seen, NSUInteger depth) {
    if (!object || depth > 7 || [seen containsObject:object]) return nil;
    [seen addObject:object];
    id response = AutoACObj(object, @[@"contentPlayerResponse", @"playerResponse"]);
    if (response) return response;
    for (NSString *name in @[@"_youtubeiOSPlayerViewController", @"parentResponder", @"parentViewController",
                             @"eventsDelegate", @"playbackController", @"activeVideoPlayerOverlay"]) {
        id found = AutoACShortsResponse(AutoACObj(object, @[name]), seen, depth + 1);
        if (found) return found;
    }
    if ([object isKindOfClass:UIResponder.class]) {
        return AutoACShortsResponse(((UIResponder *)object).nextResponder, seen, depth + 1);
    }
    return nil;
}

static NSString *AutoACShortsVideoID(UIView *from) {
    // ưu tiên mã Short đang phát do lớp Shorts cung cấp (như ytkace)
    NSInteger depthCount = 0;
    for (UIResponder *r = from; r && depthCount < 18; r = r.nextResponder, depthCount++) {
        id v = AutoACObj(r, @[@"activeReelPlaybackVideoID"]);
        if ([v isKindOfClass:NSString.class] && [(NSString *)v length] > 0) return v;
    }
    depthCount = 0;
    for (UIResponder *r = from; r && depthCount < 18; r = r.nextResponder, depthCount++) {
        id model = AutoACObj(r, @[@"contentModel"]);
        id v = model ? AutoACObj(model, @[@"videoId", @"videoID"]) : nil;
        if ([v isKindOfClass:NSString.class] && [(NSString *)v length] > 0) return v;
    }
    id response = AutoACShortsResponse(from, [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality], 0);
    id data = AutoACObj(response, @[@"playerData"]);
    id details = AutoACObj(response, @[@"videoDetails"]) ?: AutoACObj(data, @[@"videoDetails"]) ?: data;
    id vid = AutoACObj(details, @[@"videoId", @"videoID"]) ?: AutoACObj(response, @[@"videoId", @"videoID"]);
    if ([vid isKindOfClass:NSString.class] && [(NSString *)vid length] > 0) return vid;
    // dự phòng: các đối tượng trên chuỗi responder có sẵn mã video
    NSInteger hops = 0;
    for (UIResponder *r = from; r && hops < 14; r = r.nextResponder, hops++) {
        id v = AutoACObj(r, @[@"currentVideoID", @"videoId", @"videoID"]);
        if ([v isKindOfClass:NSString.class] && [(NSString *)v length] == 11) return v;
    }
    return nil;
}

static BOOL AutoACHostIsOnScreen(UIView *host, UIWindow *w) {
    if (!host || host.window != w || host.hidden || host.alpha < 0.05) return NO;
    CGRect r = [host convertRect:host.bounds toView:w];
    return CGRectGetWidth(r) > 200 && CGRectGetHeight(r) > 300 &&
           CGRectContainsPoint(r, CGPointMake(CGRectGetMidX(w.bounds), CGRectGetMidY(w.bounds)));
}

static void AutoACShortsTapped(void) {
    AutoACOpenDownloadMenu(gShortsButton.superview ?: (UIView *)gShortsButton, YES);
}

// Gọi từ layoutSubviews của các lớp Shorts: một nút duy nhất, gắn vào lớp đang hiển thị giữa màn hình
// Nút Lưu của Shorts: nhận theo tên hiển thị (nhãn) vì mã định danh của nó không cố định
static const char kAutoACSaveScanKey = 0;
// Vị trí cột nút bên phải của Shorts (cập nhật khi quét): giữa cột theo trục ngang và mép trên của nút trên cùng
static CGFloat gColCenterX = 0, gColTopY = 0;
// Đáy nút "…" (menu thêm) ở góc trên bên phải của Shorts; 0 nếu chưa tìm thấy
static CGFloat gMoreBottomY = 0;

static void AutoACFindMoreButton(UIView *view, UIWindow *w, int depth, CGFloat *bestX, CGFloat *bottom) {
    if (depth > 12) return;
    for (UIView *sub in view.subviews) {
        if (sub.hidden || sub.alpha < 0.05) continue;
        NSString *label = (sub.accessibilityLabel ?: @"").lowercaseString;
        NSString *ident = (sub.accessibilityIdentifier ?: @"").lowercaseString;
        if (label.length || ident.length) {
            CGRect r = [sub convertRect:sub.bounds toView:w];
            BOOL topRight = CGRectGetMidX(r) > CGRectGetWidth(w.bounds) * 0.8 && CGRectGetMaxY(r) < CGRectGetHeight(w.bounds) * 0.25 &&
                            CGRectGetWidth(r) >= 20 && CGRectGetWidth(r) <= 80 && CGRectGetHeight(r) >= 20 && CGRectGetHeight(r) <= 80;
            if (topRight) {
                for (NSString *k in @[@"more", AutoACT(@"thêm"), @"menu", AutoACT(@"tùy chọn"), @"option", @"overflow"]) {
                    if ([label containsString:k] || [ident containsString:k]) {
                        if (CGRectGetMidX(r) > *bestX) { *bestX = CGRectGetMidX(r); *bottom = CGRectGetMaxY(r); }
                        break;
                    }
                }
            }
        }
        AutoACFindMoreButton(sub, w, depth + 1, bestX, bottom);
    }
}
static CFTimeInterval gColStamp = 0;

static void AutoACScanShortsColumn(UIView *view, UIWindow *w, int depth, NSMutableArray<NSNumber *> *xs, CGFloat *top) {
    if (depth > 10) return;
    BOOL hide = [kPrefs boolForKey:kShortsSaveKey];
    static NSSet<NSString *> *geometry;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        geometry = [NSSet setWithArray:@[@"id.reel_like_button", @"id.reel_comment_button", @"id.reel_share_button", @"id.reel_remix_button"]];
    });
    for (UIView *sub in view.subviews) {
        NSString *label = (sub.accessibilityLabel ?: @"").lowercaseString;
        NSString *ident = (sub.accessibilityIdentifier ?: @"").lowercaseString;
        BOOL match = NO;
        if (label.length || ident.length) {
            CGRect r = [sub convertRect:sub.bounds toView:w];
            BOOL inColumn = CGRectGetMidX(r) > CGRectGetWidth(w.bounds) * 0.72 && CGRectGetWidth(r) >= 24 && CGRectGetWidth(r) <= 120 &&
                            CGRectGetHeight(r) >= 24 && CGRectGetHeight(r) <= 140;
            if (inColumn) {
                if (!gReelSeen) gReelSeen = [NSMutableOrderedSet orderedSet];
                if (gReelSeen.count < 24) [gReelSeen addObject:[NSString stringWithFormat:@"%@ · %@", ident.length ? ident : @"-", label.length ? label : @"-"]];
                if ([geometry containsObject:ident] && !sub.hidden && sub.alpha > 0.05) {
                    [xs addObject:@(CGRectGetMidX(r))];
                    *top = MIN(*top, CGRectGetMinY(r));
                }
                for (NSString *k in @[AutoACT(@"lưu"), @"save", AutoACT(@"danh sách phát"), @"playlist", @"bookmark"]) {
                    if ([label containsString:k] || [ident containsString:k]) { match = YES; break; }
                }
            }
        }
        if (match) { AutoACSetOwnedHidden(sub, hide); continue; }
        AutoACScanShortsColumn(sub, w, depth + 1, xs, top);
    }
}

static NSHashTable<UIView *> *gShortsHosts = nil;
static NSTimer *gShortsTimer = nil;
static void AutoACEnsureShortsButton(UIView *host);

// Độ lệch của lớp so với giữa màn hình (nhỏ hơn = đang là Short hiện tại)
static CGFloat AutoACHostOffset(UIView *host, UIWindow *w) {
    CGRect r = [host convertRect:host.bounds toView:w];
    return fabs(CGRectGetMidY(r) - CGRectGetMidY(w.bounds)) + fabs(CGRectGetMidX(r) - CGRectGetMidX(w.bounds));
}

// Nhịp kiểm tra nhẹ: layoutSubviews không phải lúc nào cũng chạy sau khi cuộn sang Short mới,
// nên nút có thể còn dính ở lớp Short cũ hoặc mất khi lớp đó bị tái sử dụng
static void AutoACShortsButtonTick(void) {
    if (CACurrentMediaTime() - gShortsOnScreenAt > 8.0) { [gShortsTimer invalidate]; gShortsTimer = nil; return; }
    UIView *best = nil; CGFloat bestOff = CGFLOAT_MAX;
    for (UIView *h in gShortsHosts.allObjects) {
        UIWindow *w = h.window;
        if (!w || !AutoACHostIsOnScreen(h, w)) continue;
        CGFloat off = AutoACHostOffset(h, w);
        if (off < bestOff) { best = h; bestOff = off; }
    }
    if (best) AutoACEnsureShortsButton(best);
}

static void AutoACEnsureShortsButton(UIView *host) {
    if (!host) return;
    if (!gShortsHosts) gShortsHosts = [NSHashTable weakObjectsHashTable];
    [gShortsHosts addObject:host];
    if (!gShortsTimer) {
        gShortsTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { AutoACShortsButtonTick(); }];
    }
    UIWindow *w = host.window;   // nút tải trong Shorts luôn bật
    if (w && AutoACHostIsOnScreen(host, w)) {
        NSDate *last = objc_getAssociatedObject(host, &kAutoACSaveScanKey);
        if (!last || -last.timeIntervalSinceNow > 3.0) {   // quét nhẹ, tối đa mỗi 3 giây
            objc_setAssociatedObject(host, &kAutoACSaveScanKey, [NSDate date], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSMutableArray<NSNumber *> *xs = [NSMutableArray array];
            CGFloat top = CGFLOAT_MAX;
            AutoACScanShortsColumn(host, w, 0, xs, &top);
            { CGFloat bx = 0, bb = 0; AutoACFindMoreButton(w, w, 0, &bx, &bb); if (bb > 0) gMoreBottomY = bb; }
            if (xs.count >= 1) {
                CGFloat sum = 0;
                for (NSNumber *x in xs) sum += x.doubleValue;
                gColCenterX = sum / xs.count;
                gColTopY = top;
                gColStamp = CACurrentMediaTime();
            }
        }
    }
    if (!w || !AutoACHostIsOnScreen(host, w)) return;
    gShortsOnScreenAt = CACurrentMediaTime();
    if (!gShortsButton) AutoACTrace("create shorts button");
    if (!gShortsButton) gShortsButton = AutoACMakeFloatingButton(@"arrow.down.circle", 17, ^{ AutoACShortsTapped(); });
    UIView *current = gShortsButton.superview;
    if (current != host) {
        // Lớp cũ vẫn còn trên màn hình nhưng lớp mới gần giữa hơn (đang chuyển Short): chuyển nút sang lớp mới
        if (current && current.window == w && AutoACHostIsOnScreen(current, w) &&
            AutoACHostOffset(current, w) <= AutoACHostOffset(host, w) + 1.0) return;
        [host addSubview:gShortsButton];
    }
    UIEdgeInsets safe = w.safeAreaInsets;
    // Chưa quét được cột nút: đặt ở mép phải, khoảng giữa màn hình (vùng cột nút), tránh dải chip và tiêu đề phía trên
    // Cùng cột với cột nút, dịch phải một chút; nằm dưới nút "…" khoảng 1,1 cm (≈ 70 điểm)
    CGFloat centerX = gColStamp > 0 ? gColCenterX : CGRectGetWidth(w.bounds) - safe.right - 52 + kFloatSize / 2;
    CGFloat moreBottom = gMoreBottomY > 0 ? gMoreBottomY : safe.top + 44;
    CGFloat y = moreBottom + 70;   // 96 trừ khoảng 26 điểm (≈ 0,4 cm) dịch lên
    if (gColStamp > 0) y = MIN(y, gColTopY - 4 - kFloatSize);   // không đè lên nút tim
    CGFloat maxX = CGRectGetWidth(w.bounds) - safe.right - 4 - kFloatSize;
    CGPoint target = CGPointMake(MIN(centerX + 3 - kFloatSize / 2, maxX), y);   // dịch phải 3 điểm (bớt 3 so với trước)
    CGPoint p = [host convertPoint:target fromView:w];
    CGRect frame = CGRectMake(round(p.x), round(p.y), kFloatSize, kFloatSize);
    if (!CGRectEqualToRect(gShortsButton.frame, frame)) gShortsButton.frame = frame;
    gShortsButton.hidden = NO;
    if (host.subviews.lastObject != gShortsButton) [host bringSubviewToFront:gShortsButton];
}

static void AutoACRelayoutPlayerButton(void) {
    BOOL on = [kPrefs boolForKey:kPlayerButtonKey];
    for (UIView *v in gDLOverlays.allObjects) v.hidden = !on;
}

// Các lớp điều khiển trình phát đang sống: đổi công tắc icon tải thì bố trí lại ngay, không cần mở lại app
static NSHashTable<UIView *> *gControlsOverlays = nil;
static NSHashTable<UIView *> *gBottomBars = nil;   // thanh điều khiển phía dưới (hàng Overlay dưới)
static void AutoACRelayoutPlayerTools(void) {
    for (UIView *v in gControlsOverlays.allObjects) [v setNeedsLayout];
    for (UIView *v in gBottomBars.allObjects) [v setNeedsLayout];
}


@interface AutoACSpeedReset : NSObject
+ (instancetype)shared;
- (void)handle:(UILongPressGestureRecognizer *)g;
@end

static double AutoACPlayerDouble(id player, NSArray<NSString *> *names);

// ── Chọn tốc độ kiểu bánh xe số (nhỏ gọn) ──
// ── PiP (hình trong hình): phát luồng của video bằng AVPlayer ẩn rồi bật PiP, theo cách ytkace ──
@interface AutoACPiP : NSObject <AVPictureInPictureControllerDelegate>
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *layer;
@property (nonatomic, strong) UIView *host;
@property (nonatomic, strong) AVPictureInPictureController *controller;
@property (nonatomic) BOOL busy;
@property (nonatomic) CFTimeInterval startedAt;
@property (nonatomic) double lastTime;   // giây đang phát trong PiP, nhớ lúc sắp thoát để đưa trình phát YouTube về đúng chỗ
+ (instancetype)shared;
- (void)toggle;
- (void)stopForYouTube;
@end
@implementation AutoACPiP
+ (instancetype)shared { static AutoACPiP *i; static dispatch_once_t o; dispatch_once(&o, ^{ i = [AutoACPiP new]; }); return i; }
- (void)callOnYouTube:(NSArray<NSString *> *)names {
    for (NSString *name in names) {
        SEL sel = NSSelectorFromString(name);
        if ([gPlayerVC respondsToSelector:sel]) { ((void (*)(id, SEL))objc_msgSend)(gPlayerVC, sel); return; }
    }
}
- (void)cleanup {
    [self.player pause];
    [self.host removeFromSuperview];
    self.host = nil; self.layer = nil; self.player = nil; self.controller = nil; self.busy = NO;
    self.lastTime = 0;
}
- (double)currentSeconds {
    double s = CMTimeGetSeconds(self.player.currentTime);
    return (isfinite(s) && s > 0) ? s : 0;
}
// YouTube vừa phát một video (video mới hoặc tiếp tục phát): đóng PiP để không phát hai video cùng lúc
- (void)stopForYouTube {
    if (!self.controller && !self.busy) return;
    if (CACurrentMediaTime() - self.startedAt < 2.0) return;   // vừa mở PiP: bỏ qua nhịp cuối của chính trình phát đang bị tạm dừng
    if (self.controller.isPictureInPictureActive) [self.controller stopPictureInPicture];
    [self cleanup];
}
- (void)toggle {
    if (self.controller.isPictureInPictureActive) { [self.controller stopPictureInPicture]; return; }
    if (self.busy) return;
    if (![AVPictureInPictureController isPictureInPictureSupported]) {
        AutoACShowHub(@"pip.exit", UIColor.systemOrangeColor, AutoACT(@"Thiết bị không hỗ trợ PiP"), @"", 2.2);
        return;
    }
    NSString *videoID = AutoACCurrentVideoID();
    if (videoID.length == 0) { AutoACShowHub(@"play.slash.fill", UIColor.systemOrangeColor, AutoACT(@"Hãy mở một video trước"), @"", 2.2); return; }
    self.busy = YES;
    self.startedAt = CACurrentMediaTime();
    double time = AutoACPlayerDouble(gPlayerVC, @[@"currentVideoMediaTime", @"currentVideoTime"]);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *json = AutoACFetchPlayer(videoID, AutoACFetchVisitor());
        NSDictionary *streaming = [json[@"streamingData"] isKindOfClass:NSDictionary.class] ? json[@"streamingData"] : nil;
        NSURL *url = nil;
        NSInteger bestHeight = -1;
        for (NSDictionary *f in streaming[@"formats"]) {   // luồng đã gộp tiếng + hình
            NSString *u = f[@"url"];
            if (![u isKindOfClass:NSString.class] || ![[f[@"mimeType"] description] containsString:@"video/mp4"]) continue;
            if ([f[@"height"] integerValue] > bestHeight) { bestHeight = [f[@"height"] integerValue]; url = [NSURL URLWithString:u]; }
        }
        if (!url && [streaming[@"hlsManifestUrl"] isKindOfClass:NSString.class]) url = [NSURL URLWithString:streaming[@"hlsManifestUrl"]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!url) {
                self.busy = NO;
                AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor, AutoACT(@"Video này không mở được PiP"), @"", 2.6);
                return;
            }
            [self callOnYouTube:@[@"pause", @"suspendPlayback"]];
            self.player = [AVPlayer playerWithURL:url];
            self.player.allowsExternalPlayback = YES;
            self.host = [[UIView alloc] initWithFrame:CGRectMake(-1000, -1000, 400, 300)];
            self.layer = [AVPlayerLayer playerLayerWithPlayer:self.player];
            self.layer.frame = self.host.bounds;
            [self.host.layer addSublayer:self.layer];
            [AutoACKeyWindow() addSubview:self.host];
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
            self.controller = [[AVPictureInPictureController alloc] initWithPlayerLayer:self.layer];
            self.controller.delegate = self;
            if (time > 0) [self.player seekToTime:CMTimeMakeWithSeconds(time, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
            [self tryStart:12];
        });
    });
}
- (void)tryStart:(NSInteger)attempts {
    if (self.controller.isPictureInPicturePossible) {
        [self.player play];
        [self.controller startPictureInPicture];
        return;
    }
    if (attempts <= 0) {
        AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor, AutoACT(@"Không bật được PiP"), @"", 2.6);
        [self cleanup];
        [self callOnYouTube:@[@"play", @"resumePlayback"]];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self tryStart:attempts - 1]; });
}
- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)c { self.busy = NO; }
- (void)pictureInPictureController:(AVPictureInPictureController *)c failedToStartPictureInPictureWithError:(NSError *)error {
    AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor, AutoACT(@"Không bật được PiP"), error.localizedDescription ?: @"", 2.8);
    [self cleanup];
    [self callOnYouTube:@[@"play", @"resumePlayback"]];
}
- (void)pictureInPictureControllerWillStopPictureInPicture:(AVPictureInPictureController *)c {
    double s = [self currentSeconds];
    if (s > 0) self.lastTime = s;
}
- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)c {
    BOOL wasOurs = self.controller != nil;   // đã bị stopForYouTube dọn trước đó thì không bật lại trình phát
    double at = [self currentSeconds];
    if (at <= 0) at = self.lastTime;
    [self cleanup];
    if (!wasOurs) return;
    // Trình phát YouTube đã tạm dừng từ lúc mở PiP nên đang đứng ở thời điểm cũ: đưa nó tới chỗ PiP vừa phát rồi mới phát tiếp
    if (at > 0) AutoACSeekSeconds(gPlayerVC, at);
    [self callOnYouTube:@[@"play", @"resumePlayback"]];
    if (at > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            double now = AutoACPlayerDouble(gPlayerVC, @[@"currentVideoMediaTime", @"currentVideoTime"]);
            if (fabs(now - at) > 2.5) AutoACSeekSeconds(gPlayerVC, at);   // YouTube nạp lại chậm hơn lần tua đầu
        });
    }
}
@end

static const CGFloat kSpeedRow = 26;
static __weak UIView *gSpeedBackdrop;
static __weak UIView *gSpeedCard;
static __weak UIView *gSpeedButton;

// Thu gọn bảng tốc độ về icon tốc độ rồi gỡ đi
static void AutoACCollapseSpeedPicker(void) {
    UIView *backdrop = gSpeedBackdrop, *card = gSpeedCard, *button = gSpeedButton;
    if (!backdrop) return;
    gSpeedBackdrop = nil;
    backdrop.userInteractionEnabled = NO;
    CGPoint target = card.center;
    if (button.window) target = [button.superview convertPoint:CGPointMake(CGRectGetMidX(button.frame), CGRectGetMidY(button.frame)) toView:backdrop];
    [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:1.0 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        card.center = target;
        card.transform = CGAffineTransformMakeScale(0.16, 0.16);
        card.alpha = 0;
    } completion:^(BOOL f) { [backdrop removeFromSuperview]; }];
}

@interface AutoACSpeedSource : NSObject <UIScrollViewDelegate>
@property (nonatomic, strong) NSArray<UILabel *> *labels;
@property (nonatomic, strong) NSIndexSet *accentRows;   // hàng nổi bật (mặc định, tắt): chạm tới thì rung mạnh hơn
@property (nonatomic, copy) void (^onChange)(NSInteger row);   // gọi ngay khi cuộn qua từng hàng (tốc độ)
@property (nonatomic, copy) void (^onSettle)(NSInteger row);   // gọi một lần khi dừng hẳn sau khi đổi hàng (hẹn giờ)
@property (nonatomic) BOOL changed;
@property (nonatomic) NSInteger lastRow;
@property (nonatomic) NSUInteger token;
- (void)refresh:(UIScrollView *)sv;
- (void)releasedAfter:(NSTimeInterval)delay;
@end
@implementation AutoACSpeedSource
- (NSInteger)rowFor:(UIScrollView *)sv {
    NSInteger row = (NSInteger)llround(sv.contentOffset.y / kSpeedRow);
    return MAX(0, MIN(row, (NSInteger)self.labels.count - 1));
}
- (void)refresh:(UIScrollView *)sv {
    CGFloat pos = sv.contentOffset.y / kSpeedRow;
    for (NSUInteger i = 0; i < self.labels.count; i++) {
        CGFloat d = fabs((CGFloat)i - pos);
        UILabel *l = self.labels[i];
        l.alpha = MAX(0.2, 1 - 0.42 * d);
        CGFloat sc = 1 - 0.07 * MIN(d, 2);
        l.transform = CGAffineTransformMakeScale(sc, sc);
    }
}
- (void)scrollViewDidScroll:(UIScrollView *)sv {
    [self refresh:sv];
    if (!sv.isTracking && !sv.isDragging && !sv.isDecelerating) return;
    NSInteger row = [self rowFor:sv];
    if (row == self.lastRow) return;
    self.lastRow = row;
    self.changed = YES;
    if (self.onChange) self.onChange(row);
    BOOL accent = [self.accentRows containsIndex:(NSUInteger)row];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:accent ? UIImpactFeedbackStyleMedium : UIImpactFeedbackStyleLight] impactOccurred];
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)sv { self.token++; }
- (void)scrollViewWillEndDragging:(UIScrollView *)sv withVelocity:(CGPoint)v targetContentOffset:(inout CGPoint *)target {
    NSInteger row = (NSInteger)llround(target->y / kSpeedRow);
    row = MAX(0, MIN(row, (NSInteger)self.labels.count - 1));
    target->y = row * kSpeedRow;
}
- (void)releasedAfter:(NSTimeInterval)delay {   // thả tay: chờ một nhịp rồi tự thu gọn về icon
    NSUInteger t = ++self.token;
    __weak AutoACSpeedSource *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakSelf && weakSelf.token == t) AutoACCollapseSpeedPicker();
    });
}
- (void)settle:(UIScrollView *)sv {   // chỉ áp dụng khi người dùng thật sự đổi hàng, thả tay ở đúng hàng ban đầu thì giữ nguyên
    if (!self.changed) return;
    self.changed = NO;
    if (self.onSettle) self.onSettle([self rowFor:sv]);
}
- (void)scrollViewDidEndDragging:(UIScrollView *)sv willDecelerate:(BOOL)decelerate { if (!decelerate) { [self settle:sv]; [self releasedAfter:0.7]; } }
- (void)scrollViewDidEndDecelerating:(UIScrollView *)sv { [self settle:sv]; [self releasedAfter:0.7]; }
@end

@implementation AutoACSpeedReset
+ (instancetype)shared { static AutoACSpeedReset *i; static dispatch_once_t o; dispatch_once(&o, ^{ i = [AutoACSpeedReset new]; }); return i; }
- (void)handle:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    AutoACApplyRate(gPlayerVC, 1.0, 0);
    [kPrefs setDouble:1.0 forKey:@"kAutoACLastPickedRate"];
    [[UIImpactFeedbackGenerator new] impactOccurred];
    AutoACShowHub(@"speedometer", UIColor.systemBlueColor, AutoACT(@"Tốc độ"), AutoACT(@"Mặc định"), 1.4);
}
@end

static AutoACSpeedSource *gSpeedSource;

// Bánh xe số nhỏ gọn dùng chung (tốc độ, hẹn giờ ngủ): mở ra từ icon của nút, tự thu gọn khi thả tay
static void AutoACShowWheel(UIView *button, NSArray<NSString *> *texts, NSIndexSet *accentRows, NSInteger startRow,
                            void (^onChange)(NSInteger), void (^onSettle)(NSInteger)) {
    UIWindow *window = button.window ?: AutoACKeyWindow();
    if (!window || texts.count == 0) return;
    if (gSpeedBackdrop) { AutoACCollapseSpeedPicker(); return; }
    gSpeedSource = [AutoACSpeedSource new];
    gSpeedSource.accentRows = accentRows;
    gSpeedSource.onChange = onChange;
    gSpeedSource.onSettle = onSettle;

    UIButton *backdrop = [UIButton buttonWithType:UIButtonTypeCustom];
    backdrop.frame = window.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backdrop.backgroundColor = UIColor.clearColor;
    [backdrop addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { AutoACCollapseSpeedPicker(); }]
       forControlEvents:UIControlEventTouchUpInside];

    CGPoint anchor = button ? [button.superview convertPoint:CGPointMake(CGRectGetMidX(button.frame), CGRectGetMidY(button.frame)) toView:window]
                            : CGPointMake(CGRectGetMaxX(window.bounds) - 60, 120);
    const CGFloat w = 84, h = 92;
    UIEdgeInsets safe = window.safeAreaInsets;
    // nổi sang bên trái icon, ngang tầm icon (không đặt phía dưới vì dễ sát mép màn hình)
    CGFloat x = anchor.x - 15 - 10 - w;
    if (x < 8 + safe.left) x = anchor.x + 15 + 10;
    CGFloat y = MIN(MAX(anchor.y - h / 2, safe.top + 8), CGRectGetHeight(window.bounds) - safe.bottom - h - 8);
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, h)];
    AutoACStyleShadow(card, 0.16, 10, CGSizeMake(0, 4));
    UIVisualEffectView *blur = AutoACMakeGlass(20);   // kính lỏng, bo cong hơn một chút
    blur.frame = card.bounds;
    [card addSubview:blur];

    CGFloat inset = (h - kSpeedRow) / 2;
    UIView *mark = [[UIView alloc] initWithFrame:CGRectMake(5, inset, w - 10, kSpeedRow)];
    mark.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.12];
    mark.layer.cornerRadius = kSpeedRow / 2;   // ô chọn bo tròn như viên thuốc
    mark.layer.borderWidth = 0.5;
    mark.layer.borderColor = [UIColor.labelColor colorWithAlphaComponent:0.18].CGColor;
    [blur.contentView addSubview:mark];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    scroll.showsVerticalScrollIndicator = NO;
    scroll.decelerationRate = UIScrollViewDecelerationRateFast;
    UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];   // mặt nạ phải đặt trên khung cố định, không đặt trên scroll (bounds của scroll dịch theo nội dung)
    scroll.contentSize = CGSizeMake(w, texts.count * kSpeedRow + 2 * inset);
    scroll.delegate = gSpeedSource;
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    for (NSUInteger i = 0; i < texts.count; i++) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, inset + i * kSpeedRow, w, kSpeedRow)];
        l.textAlignment = NSTextAlignmentCenter;
        l.adjustsFontSizeToFitWidth = YES;
        l.minimumScaleFactor = 0.7;
        l.text = texts[i];
        if ([accentRows containsIndex:i]) {   // hàng mặc định / tắt: cùng màu nhấn với thông báo tốc độ
            l.textColor = AutoACSpeedAccent();
            l.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
        } else {
            l.textColor = UIColor.labelColor;
            l.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
        }
        [scroll addSubview:l];
        [labels addObject:l];
    }
    gSpeedSource.labels = labels;
    [holder addSubview:scroll];
    [blur.contentView addSubview:holder];
    NSInteger row = MAX(0, MIN(startRow, (NSInteger)texts.count - 1));
    gSpeedSource.lastRow = row;
    scroll.contentOffset = CGPointMake(0, row * kSpeedRow);
    [gSpeedSource refresh:scroll];
    // mờ dần hai đầu cho mềm
    CAGradientLayer *fade = [CAGradientLayer layer];
    fade.frame = holder.bounds;
    fade.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
    fade.locations = @[@0, @0.24, @0.76, @1];
    holder.layer.mask = fade;

    [backdrop addSubview:card];
    [window addSubview:backdrop];
    gSpeedBackdrop = backdrop; gSpeedCard = card; gSpeedButton = button;
    // mở ra từ icon
    card.center = anchor;
    card.transform = CGAffineTransformMakeScale(0.16, 0.16);
    card.alpha = 0;
    CGPoint finalCenter = CGPointMake(x + w / 2, y + h / 2);
    [UIView animateWithDuration:0.46 delay:0 usingSpringWithDamping:0.74 initialSpringVelocity:0.55
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        card.center = finalCenter;
        card.transform = CGAffineTransformIdentity;
        card.alpha = 1;
    } completion:nil];
    // nếu không chạm vào bảng thì cũng tự thu gọn sau một lúc
    [gSpeedSource releasedAfter:2.5];
}

static void AutoACShowSpeedPicker(UIView *button) {
    NSArray<NSNumber *> *rates = @[@0.1, @0.25, @0.5, @0.75, @1.0, @1.25, @1.5, @2.0, @3.0];   // như YouTube gốc, thêm các mức chậm
    static NSNumberFormatter *fmt;
    if (!fmt) { fmt = [NSNumberFormatter new]; fmt.minimumFractionDigits = 1; fmt.maximumFractionDigits = 2; fmt.locale = NSLocale.currentLocale; }
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    NSMutableIndexSet *accent = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < rates.count; i++) {
        if (fabs(rates[i].doubleValue - 1.0) < 0.001) { [texts addObject:@"Default"]; [accent addIndex:i]; }
        else [texts addObject:[fmt stringFromNumber:rates[i]]];
    }
    double current = AutoACPlayerDouble(gPlayerVC, @[@"currentPlaybackRate", @"playbackRate", @"currentRate"]);
    double saved = [kPrefs doubleForKey:@"kAutoACLastPickedRate"];
    if (saved > 0) current = saved;   // ưu tiên mức đã chọn lần trước
    if (current <= 0) current = 1;
    NSInteger row = 0; double best = 1e9;
    for (NSUInteger i = 0; i < rates.count; i++) { double d = fabs(rates[i].doubleValue - current); if (d < best) { best = d; row = (NSInteger)i; } }
    AutoACShowWheel(button, texts, accent, row, ^(NSInteger r) {
        double picked = rates[r].doubleValue;
        AutoACApplyRate(gPlayerVC, picked, 0);
        [kPrefs setDouble:picked forKey:@"kAutoACLastPickedRate"];
    }, nil);
}

// Hẹn giờ ngủ: cùng bánh xe với tốc độ. Hàng đầu là Tắt; thời gian ghi "số + min" (min: tiếng Anh và tiếng Việt đều hiểu).
// Đặt hẹn giờ khi cuộn dừng hẳn, không đặt lại ở từng hàng đi ngang qua
static void AutoACShowSleepWheel(UIView *button) {
    NSArray<NSNumber *> *minutes = @[@0, @5, @10, @15, @20, @30, @45, @60, @90, @120, @(-1)];   // 0 = tắt, -1 = End (hết video), đặt cuối cùng
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSNumber *m in minutes) {
        NSInteger v = m.integerValue;
        [texts addObject:v == 0 ? AutoACT(@"Tắt") : (v < 0 ? AutoACT(@"End") : [NSString stringWithFormat:@"%@ min", m])];
    }
    NSInteger endRow = (NSInteger)minutes.count - 1;
    NSInteger start = 0;
    if (gSleepAtEnd) start = endRow;
    else if (gSleepEnd) {   // đang hẹn giờ: đặt bánh xe ở mức gần thời gian còn lại nhất
        double left = MAX(0, gSleepEnd.timeIntervalSinceNow) / 60.0, best = 1e9;
        for (NSInteger i = 1; i < endRow; i++) { double d = fabs(minutes[(NSUInteger)i].doubleValue - left); if (d < best) { best = d; start = i; } }
    }
    NSMutableIndexSet *accent = [NSMutableIndexSet indexSetWithIndex:0];
    [accent addIndex:(NSUInteger)endRow];
    AutoACShowWheel(button, texts, accent, start, nil, ^(NSInteger r) {
        NSInteger m = minutes[(NSUInteger)r].integerValue;
        if (m == 0 && !AutoACSleepActive()) return;   // chưa hẹn giờ mà chọn Tắt: không có gì để tắt
        AutoACSetSleepTimer(m);
    });
}

// ── Chất lượng video: bánh xe chọn độ phân giải của video đang xem (đặt ràng buộc định dạng lên activeVideo, như YTKACE) ──
static NSString *gQualityPickedLabel = nil, *gQualityPickedVideo = nil;

static NSInteger AutoACQualityResolution(NSString *label) {
    NSScanner *scanner = [NSScanner scannerWithString:label ?: @""];
    NSInteger value = 0;
    return [scanner scanInteger:&value] ? value : 0;
}

static BOOL AutoACApplyQualityLabel(id video, NSString *label) {
    Class constraintClass = NSClassFromString(@"MLQuickMenuVideoQualitySettingFormatConstraint");
    SEL initializer = NSSelectorFromString(@"initWithVideoQualitySetting:formatSelectionReason:qualityLabel:");
    SEL setter = NSSelectorFromString(@"setVideoFormatConstraint:");
    if (!video || label.length == 0 || !constraintClass || ![video respondsToSelector:setter]) return NO;
    id allocated = [constraintClass alloc];
    if (![allocated respondsToSelector:initializer]) return NO;
    id constraint = ((id (*)(id, SEL, NSInteger, NSInteger, id))objc_msgSend)(allocated, initializer, 3, 2, label);
    if (!constraint) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(video, setter, constraint);
    return YES;
}

static void AutoACShowQualityPicker(UIView *button) {
    id video = AutoACObj(gPlayerVC, @[@"activeVideo"]);
    id formats = AutoACObj(video, @[@"selectableVideoFormats"]);
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    if ([formats isKindOfClass:NSArray.class]) {
        for (id format in formats) {
            id label = AutoACObj(format, @[@"qualityLabel"]);
            if ([label isKindOfClass:NSString.class] && [(NSString *)label length] > 0 && ![labels containsObject:label]) [labels addObject:label];
        }
    }
    if (labels.count == 0) {
        AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor, AutoACT(@"Chưa có danh sách chất lượng"),
                      AutoACT(@"Hãy thử lại khi video đã phát"), 2.4);
        return;
    }
    [labels sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {   // độ phân giải cao ở trên cùng
        NSInteger ra = AutoACQualityResolution(a), rb = AutoACQualityResolution(b);
        if (ra != rb) return ra > rb ? NSOrderedAscending : NSOrderedDescending;
        return [b compare:a options:NSNumericSearch];
    }];
    NSInteger start = 0;
    NSString *videoID = AutoACCurrentVideoID();
    if (gQualityPickedLabel && videoID && [gQualityPickedVideo isEqualToString:videoID]) {
        NSUInteger found = [labels indexOfObject:gQualityPickedLabel];
        if (found != NSNotFound) start = (NSInteger)found;
    }
    NSArray<NSString *> *rows = [labels copy];
    AutoACShowWheel(button, rows, [NSIndexSet indexSet], start, nil, ^(NSInteger r) {   // chỉ áp dụng khi cuộn dừng hẳn
        if (r < 0 || r >= (NSInteger)rows.count) return;
        NSString *label = rows[(NSUInteger)r];
        id current = AutoACObj(gPlayerVC, @[@"activeVideo"]);
        if (AutoACApplyQualityLabel(current, label)) {
            gQualityPickedLabel = [label copy];
            gQualityPickedVideo = [AutoACCurrentVideoID() copy];
            AutoACShowHub(@"checkmark.circle.fill", UIColor.systemGreenColor, label, AutoACT(@"Chất lượng"), 1.6);
        } else {
            AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor, AutoACT(@"Không đổi được chất lượng"), @"", 2.2);
        }
    });
}

// ── Lặp video: lặp lại video đang xem. Chỉ áp dụng cho video hiện tại, chuyển sang video khác thì tự tắt ──
static NSString *gLoopVideoID = nil;
static const char kAutoACLoopArmedKey = 0;

static BOOL AutoACLoopActive(void) {
    NSString *current = AutoACCurrentVideoID();
    return gLoopVideoID.length > 0 && current.length > 0 && [gLoopVideoID isEqualToString:current];
}

static void AutoACToggleLoop(void) {
    NSString *current = AutoACCurrentVideoID();
    if (current.length == 0) {
        AutoACShowHub(@"exclamationmark.triangle.fill", UIColor.systemOrangeColor, AutoACT(@"Chưa xác định được video"), @"", 2.2);
        return;
    }
    BOOL wasOn = AutoACLoopActive();
    gLoopVideoID = wasOn ? nil : [current copy];
    objc_setAssociatedObject(gPlayerVC, &kAutoACLoopArmedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    AutoACRefreshSleepButton();   // cũng làm mới biểu tượng nút lặp
    AutoACShowHub(wasOn ? @"repeat" : @"repeat.1", wasOn ? UIColor.systemGrayColor : UIColor.systemGreenColor,
                  wasOn ? AutoACT(@"Đã tắt lặp video") : AutoACT(@"Đã bật lặp video"), @"", 1.6);
}

// Gọi mỗi lần thời gian phát đổi: khi video còn ~1 giây thì hẹn giờ tua về đầu (trước khi YouTube kịp tự chuyển video)
static void AutoACLoopTick(id player) {
    if (gLoopVideoID.length == 0) return;
    NSString *current = AutoACCurrentVideoID();
    if (current.length == 0) return;
    if (![current isEqualToString:gLoopVideoID]) {   // đã sang video khác: tắt lặp
        gLoopVideoID = nil;
        AutoACRefreshSleepButton();
        return;
    }
    double duration = AutoACPlayerDouble(player, @[@"currentVideoTotalMediaTime", @"currentVideoTotalTime", @"currentVideoDuration", @"totalMediaTime"]);
    if (duration <= 3) return;
    double time = AutoACPlayerDouble(player, @[@"currentVideoMediaTime", @"currentVideoTime"]);
    if (time < duration * 0.5) {
        objc_setAssociatedObject(player, &kAutoACLoopArmedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    double rate = MAX(AutoACPlayerDouble(player, @[@"currentPlaybackRate", @"playbackRate", @"currentRate"]), 0.25);
    double remaining = duration - time;
    if (remaining > 1.4 * MAX(rate, 1.0)) return;
    if ([objc_getAssociatedObject(player, &kAutoACLoopArmedKey) boolValue]) return;
    objc_setAssociatedObject(player, &kAutoACLoopArmedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak id weakPlayer = player;
    NSString *videoID = [gLoopVideoID copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(remaining / rate - 0.15, 0.0) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        id p = weakPlayer;
        if (!p || ![gLoopVideoID isEqualToString:videoID] || !AutoACLoopActive()) return;
        double now = AutoACPlayerDouble(p, @[@"currentVideoMediaTime", @"currentVideoTime"]);
        if (now > 0 && now < duration * 0.5) return;   // người xem đã tua lại
        AutoACSeekSeconds(p, 0);
        if ([p respondsToSelector:@selector(play)]) ((void (*)(id, SEL))objc_msgSend)(p, @selector(play));
    });
}

// Tạo một nút công cụ từ mô tả của AutoACPlayerTools (dùng chung cho hàng trên và hàng dưới)
static UIButton *AutoACMakeToolButton(NSDictionary *tool) {
    NSString *title = tool[@"title"];
    void (^tap)(UIView *) = tool[@"tap"];
    __block __weak UIButton *weakButton = nil;
    UIButton *b = AutoACMakeFloatingButton(tool[@"symbol"], [tool[@"glyph"] doubleValue], ^{ tap(weakButton); });
    weakButton = b;
    b.accessibilityLabel = title;
    if ([title isEqualToString:AutoACT(@"Tốc độ")]) {   // nhấn giữ biểu tượng: về tốc độ gốc
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[AutoACSpeedReset shared]
                                                                                         action:@selector(handle:)];
        lp.minimumPressDuration = 0.5;
        [b addGestureRecognizer:lp];
    }
    return b;
}

// Các nút công cụ của một hàng (hàng dưới hay hàng trên) theo thứ tự đã sắp trong Tuỳ chỉnh Overlay, trái → phải
static NSArray<NSDictionary *> *AutoACPlayerToolsForRow(BOOL bottomRow) {
    NSArray<NSString *> *top = nil, *bottom = nil;
    AutoACOverlayLayout(&top, &bottom, NULL);
    NSMutableArray<NSDictionary *> *tools = [NSMutableArray array];
    for (NSString *ident in (bottomRow ? bottom : top)) {
        NSDictionary *entry = AutoACOverlayEntry(ident);
        if (!entry) continue;
        NSString *symbol = entry[@"symbol"];
        void (^tap)(UIView *) = nil;
        if ([ident isEqualToString:@"download"]) tap = ^(UIView *sender) { AutoACOpenDownloadMenu(sender, NO); };
        else if ([ident isEqualToString:@"speed"]) tap = ^(UIView *sender) { AutoACShowSpeedPicker(sender); };
        else if ([ident isEqualToString:@"pip"]) tap = ^(UIView *sender) { [[AutoACPiP shared] toggle]; };
        else if ([ident isEqualToString:@"sleep"]) {
            symbol = AutoACSleepActive() ? @"moon.zzz.fill" : @"moon.zzz";
            tap = ^(UIView *sender) { AutoACShowSleepWheel(sender); };
        }
        else if ([ident isEqualToString:@"external"]) tap = ^(UIView *sender) { AutoACShowExternalMenu(); };
        else if ([ident isEqualToString:@"quality"]) tap = ^(UIView *sender) { AutoACShowQualityPicker(sender); };
        else if ([ident isEqualToString:@"loop"]) {
            symbol = AutoACLoopActive() ? @"repeat.1" : @"repeat";
            tap = ^(UIView *sender) { AutoACToggleLoop(); };
        }
        if (!tap) continue;
        [tools addObject:@{@"id": ident, @"title": entry[@"title"], @"symbol": symbol, @"size": @30, @"glyph": @17, @"tap": tap}];
    }
    return tools;
}

static const char kAutoACToolsKey = 0, kAutoACGearKey = 0;
static const void *kAutoACBottomToolsKey = &kAutoACBottomToolsKey;
static const void *kAutoACBottomLinkKey = &kAutoACBottomLinkKey;
static const void *kAutoACBottomSigKey = &kAutoACBottomSigKey;

static UIView *AutoACFindGear(UIView *root, int depth) {
    if (depth > 5) return nil;
    for (UIView *sub in root.subviews) {
        if (sub.hidden || CGRectGetWidth(sub.bounds) > 90 || CGRectGetWidth(sub.bounds) < 16) {
            UIView *deep = AutoACFindGear(sub, depth + 1);
            if (deep) return deep;
            continue;
        }
        NSString *label = (sub.accessibilityLabel ?: @"").lowercaseString;
        NSString *ident = (sub.accessibilityIdentifier ?: @"").lowercaseString;
        if ([label isEqualToString:AutoACT(@"cài đặt")] || [label isEqualToString:@"settings"] ||
            [label containsString:AutoACT(@"cài đặt")] || [ident containsString:@"settings"] || [ident containsString:@"overflow"]) {
            if (![sub.accessibilityLabel isEqualToString:@"AutoAC"]) return sub;
        }
        UIView *deep = AutoACFindGear(sub, depth + 1);
        if (deep) return deep;
    }
    return nil;
}

// Đồng bộ độ mờ / ẩn của các nút với nút bánh răng để chúng tự ẩn cùng thanh điều khiển của YouTube
static const char kAutoACFloatLinkKey = 0;

@interface AutoACFloatSync : NSObject
@property (nonatomic, weak) UIView *overlay;
- (void)tick:(CADisplayLink *)link;
@end
@implementation AutoACFloatSync
- (void)tick:(CADisplayLink *)link {
    UIView *overlay = self.overlay;
    if (!overlay || !overlay.window) {
        [link invalidate];
        if (overlay) objc_setAssociatedObject(overlay, &kAutoACFloatLinkKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    NSMutableDictionary<NSString *, UIButton *> *buttons = objc_getAssociatedObject(overlay, &kAutoACToolsKey);
    if (!buttons.count) return;
    UIView *gear = objc_getAssociatedObject(overlay, &kAutoACGearKey);
    if (!gear.window || gear.window != overlay.window) {
        gear = AutoACFindGear(overlay, 0);
        objc_setAssociatedObject(overlay, &kAutoACGearKey, gear, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!gear) return;
    // độ mờ thực đang hiển thị của nút bánh răng (kể cả lúc YouTube đang chạy hiệu ứng ẩn) → các nút của AutoAC mờ cùng nhịp
    CGFloat alpha = 1;
    for (UIView *v = gear; v && v != overlay; v = v.superview) {
        if (v.hidden) { alpha = 0; break; }
        CALayer *l = v.layer.presentationLayer ?: v.layer;
        alpha *= l.opacity;
    }
    for (UIButton *b in buttons.allValues) {
        if (b.hidden) continue;
        if (fabs(b.alpha - alpha) > 0.01) b.alpha = alpha;
        b.userInteractionEnabled = alpha > 0.05;
    }
}
@end

// Tâm ngang (phải → trái) của các icon gốc cùng hàng với bánh răng (bánh răng, CC, cast…): các nút của AutoAC xếp thẳng cột với chúng
static NSArray<NSNumber *> *AutoACNativeColumns(UIView *overlay, UIView *gear, NSSet<UIView *> *ours) {
    NSMutableArray<NSNumber *> *columns = [NSMutableArray array];
    if (!gear) return columns;
    CGRect gr = [overlay convertRect:gear.bounds fromView:gear];
    CGFloat midY = CGRectGetMidY(gr), gearX = CGRectGetMidX(gr);
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:overlay];
    NSUInteger visited = 0;
    while (queue.count && visited++ < 400) {
        UIView *v = queue.firstObject; [queue removeObjectAtIndex:0];
        for (UIView *sub in v.subviews) {
            if ([ours containsObject:sub] || sub.hidden) continue;
            CGRect r = [overlay convertRect:sub.bounds fromView:sub];
            CGFloat cw = CGRectGetWidth(r), ch = CGRectGetHeight(r);
            if (cw >= 16 && cw <= 64 && ch >= 16 && ch <= 64 && fabs(CGRectGetMidY(r) - midY) < 10 &&
                CGRectGetMidX(r) <= gearX + 2) {
                BOOL dup = NO;
                for (NSNumber *c in columns) if (fabs(c.doubleValue - CGRectGetMidX(r)) < 8) { dup = YES; break; }
                if (!dup) [columns addObject:@(CGRectGetMidX(r))];
            } else if (cw > 64 || ch > 64 || cw < 16) {
                [queue addObject:sub];
            }
        }
    }
    [columns sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [b compare:a]; }];
    return columns;
}

// Khoảng cách tâm-tâm giữa hai cột icon gốc liền nhau (mặc định 46): hàng trên và hàng dưới đều xếp nút theo bước này
static CGFloat AutoACColumnsStep(NSArray<NSNumber *> *columns) {
    CGFloat step = columns.count > 1 ? columns[0].doubleValue - columns[1].doubleValue : 46;
    return (step < 30 || step > 90) ? 46 : step;
}

// Bước của hàng trên đo từ một lớp điều khiển đang hiển thị (cả khi hàng trên không có nút); 0 nếu chưa đo được
static CGFloat AutoACMeasureTopStep(UIWindow *window) {
    for (UIView *overlay in gControlsOverlays.allObjects) {
        if (!overlay.window || (window && overlay.window != window) || CGRectGetWidth(overlay.bounds) < 200) continue;
        UIView *gear = objc_getAssociatedObject(overlay, &kAutoACGearKey);
        if (!gear || gear.window != overlay.window) gear = AutoACFindGear(overlay, 0);
        if (!gear) continue;
        NSDictionary<NSString *, UIButton *> *buttons = objc_getAssociatedObject(overlay, &kAutoACToolsKey);
        NSArray<NSNumber *> *columns = AutoACNativeColumns(overlay, gear, [NSSet setWithArray:buttons.allValues ?: @[]]);
        if (columns.count > 1) return AutoACColumnsStep(columns);
    }
    return 0;
}

static void AutoACEnsurePlayerFloat(UIView *overlay) {
    if (!objc_getAssociatedObject(overlay, &kAutoACFloatLinkKey)) {
        AutoACFloatSync *sync = [AutoACFloatSync new];
        sync.overlay = overlay;
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:sync selector:@selector(tick:)];
        link.preferredFramesPerSecond = 10;
        [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        objc_setAssociatedObject(overlay, &kAutoACFloatLinkKey, sync, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSMutableDictionary<NSString *, UIButton *> *buttons = objc_getAssociatedObject(overlay, &kAutoACToolsKey);
    CGFloat w = CGRectGetWidth(overlay.bounds);
    NSArray<NSDictionary *> *tools = AutoACPlayerToolsForRow(NO);   // hàng trên không có nút nào: ẩn hết
    if (w < 200 || tools.count == 0) {
        for (UIButton *b in buttons.allValues) b.hidden = YES;
        return;
    }
    if (!buttons) {
        buttons = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(overlay, &kAutoACToolsKey, buttons, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *gear = objc_getAssociatedObject(overlay, &kAutoACGearKey);
    if (!gear || gear.window != overlay.window) {
        gear = AutoACFindGear(overlay, 0);
        objc_setAssociatedObject(overlay, &kAutoACGearKey, gear, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat x, y;
    if (gear) {
        CGRect g = [overlay convertRect:gear.bounds fromView:gear];
        x = CGRectGetMidX(g) - kFloatSize / 2;   // nút cuối nằm ngay dưới bánh răng, các nút còn lại xếp ngang về bên trái
        y = CGRectGetMaxY(g) + 2;
    } else {
        x = w - overlay.safeAreaInsets.right - 50;
        y = 54;
    }
    // không có gì thay đổi (cỡ khung, vị trí bánh răng, danh sách nút) thì khỏi bố trí lại: hàm này chạy rất thường xuyên
    CGRect gRect = gear ? [overlay convertRect:gear.bounds fromView:gear] : CGRectZero;
    NSMutableString *sig = [NSMutableString stringWithFormat:@"%.0f|%.0f,%.0f,%.0f,%.0f|", w, CGRectGetMinX(gRect), CGRectGetMinY(gRect), CGRectGetWidth(gRect), CGRectGetHeight(gRect)];
    BOOL allPresent = YES;
    for (NSDictionary *tool in tools) {
        [sig appendString:tool[@"title"]];
        UIButton *existing = buttons[tool[@"title"]];
        if (!existing || existing.superview != overlay || existing.hidden) allPresent = NO;
    }
    static const char kAutoACFloatSigKey = 0;
    if (allPresent && [sig isEqualToString:objc_getAssociatedObject(overlay, &kAutoACFloatSigKey) ?: @""]) return;
    objc_setAssociatedObject(overlay, &kAutoACFloatSigKey, [sig copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSUInteger index = 0, total = tools.count;
    // các nút xếp thẳng cột với icon gốc cùng hàng bánh răng (bánh răng, CC, cast…)
    NSArray<NSNumber *> *columns = AutoACNativeColumns(overlay, gear, [NSSet setWithArray:buttons.allValues]);
    CGFloat step = AutoACColumnsStep(columns);
    if (columns.count > 1) gAutoACToolStep = step;
    NSMutableSet<NSString *> *wanted = [NSMutableSet set];
    for (NSDictionary *tool in tools) {
        NSString *title = tool[@"title"];
        [wanted addObject:title];
        UIButton *b = buttons[title];
        if (!b) {
            AutoACTrace("create player tool button");
            b = AutoACMakeToolButton(tool);
            buttons[title] = b;
        }
        if (b.superview != overlay) [overlay addSubview:b];
        CGFloat size = [tool[@"size"] doubleValue];
        NSUInteger k = total - 1 - index;   // 0 = ngay dưới bánh răng
        CGFloat cx = k < columns.count ? columns[k].doubleValue
                   : (columns.count ? columns.lastObject.doubleValue : x + kFloatSize / 2) - (CGFloat)(k - MAX((NSInteger)columns.count - 1, 0)) * step;
        CGRect frame = CGRectMake(round(cx - size / 2), round(y), size, size);
        if (!CGRectEqualToRect(b.frame, frame)) b.frame = frame;
        b.hidden = NO;
        index++;
    }
    for (NSString *title in buttons) buttons[title].hidden = ![wanted containsObject:title];
    AutoACRefreshSleepButton();
    for (UIButton *b in buttons.allValues) if (!b.hidden && overlay.subviews.lastObject != b) [overlay bringSubviewToFront:b];
}

// Nút hẹn giờ: biểu tượng đặc và màu nhạt khi đang hẹn giờ, rỗng và trắng khi không
static void AutoACRefreshSleepButton(void) {
    NSString *title = AutoACT(@"Hẹn giờ");
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
    NSMutableArray<UIButton *> *sleepButtons = [NSMutableArray array];
    for (UIView *overlay in gControlsOverlays.allObjects) {
        UIButton *b = ((NSDictionary<NSString *, UIButton *> *)objc_getAssociatedObject(overlay, &kAutoACToolsKey))[title];
        if (b) [sleepButtons addObject:b];
    }
    for (UIView *bar in gBottomBars.allObjects) {
        UIButton *b = ((NSDictionary<NSString *, UIButton *> *)objc_getAssociatedObject(bar, kAutoACBottomToolsKey))[title];
        if (b) [sleepButtons addObject:b];
    }
    for (UIButton *b in sleepButtons) {
        [b setImage:[UIImage systemImageNamed:AutoACSleepActive() ? @"moon.zzz.fill" : @"moon.zzz" withConfiguration:cfg] forState:UIControlStateNormal];
        b.tintColor = AutoACSleepActive() ? [UIColor colorWithRed:0.62 green:0.66 blue:1.0 alpha:1] : UIColor.whiteColor;
    }
    // nút lặp video: biểu tượng "repeat.1" và màu xanh khi đang lặp
    NSString *loopTitle = AutoACT(@"Lặp video");
    BOOL loopOn = AutoACLoopActive();
    NSMutableArray<UIButton *> *loopButtons = [NSMutableArray array];
    for (UIView *overlay in gControlsOverlays.allObjects) {
        UIButton *b = ((NSDictionary<NSString *, UIButton *> *)objc_getAssociatedObject(overlay, &kAutoACToolsKey))[loopTitle];
        if (b) [loopButtons addObject:b];
    }
    for (UIView *bar in gBottomBars.allObjects) {
        UIButton *b = ((NSDictionary<NSString *, UIButton *> *)objc_getAssociatedObject(bar, kAutoACBottomToolsKey))[loopTitle];
        if (b) [loopButtons addObject:b];
    }
    for (UIButton *b in loopButtons) {
        [b setImage:[UIImage systemImageNamed:loopOn ? @"repeat.1" : @"repeat" withConfiguration:cfg] forState:UIControlStateNormal];
        b.tintColor = loopOn ? [UIColor colorWithRed:0.45 green:0.92 blue:0.55 alpha:1] : UIColor.whiteColor;
    }
}

// ── Overlay hàng dưới: cùng bộ nút, đặt bên trái nút toàn màn hình của thanh điều khiển phía dưới (theo cách YTVideoOverlay) ──
static id AutoACGetter(id obj, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    return [obj respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

static BOOL AutoACControlShown(UIView *v) {
    return [v isKindOfClass:UIView.class] && v.window && !v.hidden && CGRectGetWidth(v.bounds) > 1;   // không xét alpha: độ mờ được đồng bộ riêng để hai hàng mờ cùng nhịp
}

static UIView *AutoACFullscreenControl(UIView *bar) {
    for (NSString *name in @[@"enterFullscreenButton", @"exitFullscreenButton", @"enterExitFullscreenButton"]) {
        UIView *v = AutoACGetter(bar, name);
        if (AutoACControlShown(v)) return v;
    }
    return nil;
}

static void AutoACEnsureBottomRow(UIView *bar, BOOL alphaOnly);

@interface AutoACBottomSync : NSObject
@property (nonatomic, weak) UIView *bar;
- (void)tick:(CADisplayLink *)link;
@end
@implementation AutoACBottomSync
- (void)tick:(CADisplayLink *)link {
    UIView *bar = self.bar;
    if (!bar || !bar.window) {
        [link invalidate];
        if (bar) objc_setAssociatedObject(bar, kAutoACBottomLinkKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    AutoACEnsureBottomRow(bar, YES);   // chỉ đồng bộ độ mờ với nút toàn màn hình để hai hàng ẩn/hiện cùng nhịp
}
@end

static void AutoACEnsureBottomRow(UIView *bar, BOOL alphaOnly) {
    NSMutableDictionary<NSString *, UIButton *> *buttons = objc_getAssociatedObject(bar, kAutoACBottomToolsKey);
    NSArray<NSDictionary *> *tools = AutoACPlayerToolsForRow(YES);
    UIView *fs = tools.count ? AutoACFullscreenControl(bar) : nil;
    NSInteger layout = 0;
    SEL layoutSel = NSSelectorFromString(@"layout");
    if ([bar respondsToSelector:layoutSel]) layout = ((NSInteger (*)(id, SEL))objc_msgSend)(bar, layoutSel);
    UIView *peek = AutoACGetter(bar, @"peekableView");
    UIView *host = (layout == 3 && [peek isKindOfClass:UIView.class]) ? peek : bar;   // toàn màn hình: các nút nằm trong peekableView
    if (tools.count == 0 || !fs) {
        for (UIButton *b in buttons.allValues) b.hidden = YES;
        return;
    }
    if (!objc_getAssociatedObject(bar, kAutoACBottomLinkKey)) {
        AutoACBottomSync *sync = [AutoACBottomSync new];
        sync.bar = bar;
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:sync selector:@selector(tick:)];
        link.preferredFramesPerSecond = 10;
        [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        objc_setAssociatedObject(bar, kAutoACBottomLinkKey, sync, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // độ mờ thực đang hiển thị của nút toàn màn hình (kể cả lúc YouTube chạy hiệu ứng ẩn)
    CGFloat alpha = 1;
    for (UIView *v = fs; v && v != host; v = v.superview) {
        if (v.hidden) { alpha = 0; break; }
        CALayer *l = v.layer.presentationLayer ?: v.layer;
        alpha *= l.opacity;
    }
    for (UIButton *b in buttons.allValues) {
        if (b.hidden) continue;
        if (fabs(b.alpha - alpha) > 0.01) b.alpha = alpha;
        b.userInteractionEnabled = alpha > 0.05;
    }
    if (alphaOnly) return;

    CGRect fsRect = [host convertRect:fs.bounds fromView:fs];
    if (CGRectIsEmpty(fsRect) || fsRect.origin.x <= 0 || fsRect.origin.y < -4) {
        for (UIButton *b in buttons.allValues) b.hidden = YES;
        return;
    }
    if (!buttons) {
        buttons = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(bar, kAutoACBottomToolsKey, buttons, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSMutableString *sig = [NSMutableString stringWithFormat:@"%p|%.0f,%.0f,%.0f,%.0f|%.0f|", host, fsRect.origin.x, fsRect.origin.y, fsRect.size.width, fsRect.size.height, gAutoACToolStep];
    BOOL allPresent = YES;
    for (NSDictionary *tool in tools) {
        [sig appendString:tool[@"title"]];
        UIButton *existing = buttons[tool[@"title"]];
        if (!existing || existing.superview != host || existing.hidden) allPresent = NO;
    }
    if (allPresent && [sig isEqualToString:objc_getAssociatedObject(bar, kAutoACBottomSigKey) ?: @""]) return;
    objc_setAssociatedObject(bar, kAutoACBottomSigKey, [sig copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // mép trái của cụm icon gốc đang nằm sát nút toàn màn hình (CC, tắt tiếng...): các nút của AutoAC xếp tiếp về bên trái
    NSMutableSet<UIView *> *ours = [NSMutableSet setWithArray:buttons.allValues];
    NSMutableArray<NSValue *> *near = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:host];
    NSUInteger visited = 0;
    while (queue.count && visited++ < 300) {
        UIView *v = queue.firstObject; [queue removeObjectAtIndex:0];
        for (UIView *sub in v.subviews) {
            if ([ours containsObject:sub] || sub.hidden || sub.alpha < 0.01 || sub == fs) continue;
            CGRect r = [host convertRect:sub.bounds fromView:sub];
            CGFloat cw = CGRectGetWidth(r), ch = CGRectGetHeight(r);
            if (cw >= 16 && cw <= 64 && ch >= 16 && ch <= 64 && fabs(CGRectGetMidY(r) - CGRectGetMidY(fsRect)) < 14 &&
                CGRectGetMaxX(r) <= CGRectGetMinX(fsRect) + 2) {
                [near addObject:[NSValue valueWithCGRect:r]];
            } else if (cw > 64 || ch > 64) {
                [queue addObject:sub];
            }
        }
    }
    [near sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        CGFloat x = CGRectGetMaxX(a.CGRectValue), y = CGRectGetMaxX(b.CGRectValue);
        return x > y ? NSOrderedAscending : (x < y ? NSOrderedDescending : NSOrderedSame);
    }];
    CGFloat edge = CGRectGetMinX(fsRect), anchorMid = CGRectGetMidX(fsRect);   // anchorMid: tâm icon ngoài cùng bên trái của cụm gốc
    NSMutableArray<NSNumber *> *clusterMids = [NSMutableArray arrayWithObject:@(anchorMid)];
    for (NSValue *v in near) {
        CGRect r = v.CGRectValue;
        if (CGRectGetMaxX(r) > edge + 2) continue;
        if (edge - CGRectGetMaxX(r) < 24) { edge = CGRectGetMinX(r); anchorMid = CGRectGetMidX(r); [clusterMids addObject:@(anchorMid)]; } else break;
    }
    UIView *multi = AutoACGetter(bar, @"multiFeedElementView");
    if (AutoACControlShown(multi)) {
        CGRect mr = [host convertRect:multi.bounds fromView:multi];
        if (CGRectGetMinX(mr) < edge) { edge = CGRectGetMinX(mr); anchorMid = CGRectGetMidX(mr); [clusterMids addObject:@(anchorMid)]; }
    }

    // cùng bước với hàng trên (đo từ cột icon gốc cạnh bánh răng); chưa đo được thì lấy bước giữa hai icon gốc cạnh nhau ở hàng dưới, cuối cùng 46
    CGFloat step = AutoACMeasureTopStep(bar.window);
    if (step > 0) gAutoACToolStep = step; else step = gAutoACToolStep;
    if (step <= 0 && clusterMids.count > 1) step = AutoACColumnsStep(@[clusterMids[clusterMids.count - 2], clusterMids.lastObject]);
    if (step <= 0) step = 46;
    CGFloat size = kFloatSize, x = anchorMid - step - size / 2, y = CGRectGetMidY(fsRect) - size / 2;
    NSMutableSet<NSString *> *wanted = [NSMutableSet set];
    for (NSDictionary *tool in [tools reverseObjectEnumerator]) {   // nút cuối danh sách đứng sát cụm icon gốc / nút toàn màn hình, các nút trước nối tiếp về bên trái
        NSString *title = tool[@"title"];
        [wanted addObject:title];
        UIButton *b = buttons[title];
        if (!b) {
            AutoACTrace("create bottom tool button");
            b = AutoACMakeToolButton(tool);
            b.alpha = alpha;
            buttons[title] = b;
        }
        if (b.superview != host) [host addSubview:b];
        CGRect frame = CGRectMake(round(MAX(x, 0)), round(y), size, size);
        if (!CGRectEqualToRect(b.frame, frame)) b.frame = frame;
        b.hidden = NO;
        x -= step;
    }
    for (NSString *title in buttons) buttons[title].hidden = ![wanted containsObject:title];
    AutoACRefreshSleepButton();
}

static void AutoACInstallPlayerFloatHook(void) {
    AutoACHook(@"YTMainAppControlsOverlayView", @"layoutSubviews", NO, "v", ^id(IMP original, SEL selector) {
        return ^void(UIView *self_) {
            if (original) ((void (*)(id, SEL))original)(self_, selector);
            if (!gControlsOverlays) gControlsOverlays = [NSHashTable weakObjectsHashTable];
            [gControlsOverlays addObject:self_];
            AutoACEnsurePlayerFloat(self_);
        };
    });
    AutoACHook(@"YTInlinePlayerBarContainerView", @"layoutSubviews", NO, "v", ^id(IMP original, SEL selector) {
        return ^void(UIView *self_) {
            if (original) ((void (*)(id, SEL))original)(self_, selector);
            if (!gBottomBars) gBottomBars = [NSHashTable weakObjectsHashTable];
            [gBottomBars addObject:self_];
            AutoACEnsureBottomRow(self_, NO);
        };
    });
}

static void AutoACInstallShortsButtonHooks(void) {
    for (NSString *cls in @[@"YTReelWatchPlaybackOverlayView", @"YTReelContainerView", @"YTReelContentView",
                            @"YTReelPlayerView", @"YTShortsPlayerView", @"YTShortsPlayerViewControllerView"]) {
        AutoACHook(cls, @"layoutSubviews", NO, "v16", ^id(IMP original, SEL selector) {
            return ^void(UIView *self_) {
                if (original) ((void (*)(id, SEL))original)(self_, selector);
                AutoACEnsureShortsButton(self_);
            };
        });
    }
    for (NSString *cls in @[@"YTShortsPlayerViewController", @"YTReelPlayerViewController", @"YTReelWatchRootViewController",
                            @"YTAppReelWatchRootViewController", @"YTReelContainerViewController"]) {
        AutoACHook(cls, @"viewDidLayoutSubviews", NO, "v", ^id(IMP original, SEL selector) {
            return ^void(UIViewController *self_) {
                if (original) ((void (*)(id, SEL))original)(self_, selector);
                if (self_.isViewLoaded) AutoACEnsureShortsButton(self_.view);
            };
        });
    }
}


static void AutoACInstallPostToolsHooks(void) {
    AutoACInstallCommentCellHook();
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(),
                       ^{ AutoACAttachCommentGestures(); });
    }];
    AutoACHook(@"YTImageZoomNode", @"didEnterVisibleState", NO, "v", ^id(IMP original, SEL selector) {
        return ^void(id receiver) {
            if (original) ((void (*)(id, SEL))original)(receiver, selector);
            if (![kPrefs boolForKey:kPostImageKey]) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                UIView *view = AutoACNodeValue(receiver, @"view");
                if (![view isKindOfClass:UIView.class] || !view.window) return;
                UIResponder *r = view;
                while (r && ![r isKindOfClass:UIViewController.class]) r = r.nextResponder;
                Class viewer = NSClassFromString(@"YTInterstitialElementsViewControllerImpl");
                if (!viewer || ![r isKindOfClass:viewer]) return;
                gZoomNode = receiver;
                AutoACAttachPostSaveButton(((UIViewController *)r).view);
            });
        };
    });
}


#pragma mark - Tự cuộn Shorts (theo ytkace)

static id AutoACParentVC(id receiver) {
    SEL selector = NSSelectorFromString(@"parentViewController");
    return [receiver respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector) : nil;
}

static id AutoACFindShortsController(id receiver) {
    id current = receiver;
    for (NSInteger i = 0; current && i < 10; i++) {
        NSString *name = NSStringFromClass([current class]).lowercaseString;
        if ([name containsString:@"shorts"] || [name containsString:@"reel"]) return current;
        id parent = AutoACParentVC(current);
        if (parent && parent != current) current = parent;
        else if ([current isKindOfClass:UIResponder.class]) current = ((UIResponder *)current).nextResponder;
        else break;
    }
    return nil;
}

static BOOL AutoACAdvanceShort(id controller, id sender) {
    for (NSString *name in @[@"reelContentViewRequestsAdvanceToNextVideo:", @"advanceToNextVideo:",
                             @"advanceToNextVideo", @"scrollToNextVideo"]) {
        SEL selector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod([controller class], selector);
        if (!method) continue;
        if (method_getNumberOfArguments(method) == 3) ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, sender);
        else ((void (*)(id, SEL))objc_msgSend)(controller, selector);
        return YES;
    }
    SEL reelAdvance = NSSelectorFromString(@"advanceToNextReelWithTransitionType:");
    id current = controller;
    for (NSInteger depth = 0; current && depth < 8; depth++) {
        Method method = class_getInstanceMethod([current class], reelAdvance);
        if (method) {
            char type[8] = {0};
            method_getArgumentType(method, 2, type, sizeof(type));
            if (strchr("qQiIlL", type[0]) && type[1] == 0) {
                ((void (*)(id, SEL, long long))objc_msgSend)(current, reelAdvance, 0);
                return YES;
            }
        }
        id parent = AutoACParentVC(current);
        current = parent && parent != current ? parent
            : ([current isKindOfClass:UIResponder.class] ? ((UIResponder *)current).nextResponder : nil);
    }
    UIView *view = [controller isKindOfClass:UIViewController.class] ? ((UIViewController *)controller).view : nil;
    for (UIView *candidate = view.superview; candidate; candidate = candidate.superview) {
        if (![candidate isKindOfClass:UIScrollView.class]) continue;
        UIScrollView *pager = (UIScrollView *)candidate;
        CGFloat page = CGRectGetHeight(pager.bounds);
        if (page < 100 || page < CGRectGetHeight(view.bounds) * 0.9) continue;
        CGFloat next = round(pager.contentOffset.y / page) * page + page;
        if (next > pager.contentSize.height - page + 1) break;
        [pager setContentOffset:CGPointMake(pager.contentOffset.x, next) animated:YES];
        return YES;
    }
    return NO;
}

static const char kAutoACShortsSkipKey = 0;

static double AutoACPlayerDouble(id player, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        SEL selector = NSSelectorFromString(name);
        if ([player respondsToSelector:selector]) {
            double v = ((double (*)(id, SEL))objc_msgSend)(player, selector);
            if (v > 0) return v;
        }
    }
    return 0;
}

// Gọi mỗi lần thời gian phát đổi. Bản cũ chỉ ra tay khi còn dưới 0,35 giây, nhưng nhịp báo thời gian thưa hơn thế
// nên thường bỏ lỡ và Short vẫn lặp. Nay hẹn giờ ngay khi còn dưới 1,2 giây để hành động đúng lúc Short sắp hết.
static void AutoACShortsTick(id player) {
    double duration = AutoACPlayerDouble(player, @[@"currentVideoTotalMediaTime", @"currentVideoTotalTime",
                                                    @"currentVideoDuration", @"totalMediaTime"]);
    if (duration <= 1) return;
    double time = AutoACPlayerDouble(player, @[@"currentVideoMediaTime", @"currentVideoTime"]);
    if (time < duration * 0.5) {
        objc_setAssociatedObject(player, &kAutoACShortsSkipKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    double remaining = duration - time;
    if (remaining > 1.2) return;
    if ([objc_getAssociatedObject(player, &kAutoACShortsSkipKey) boolValue]) return;
    id shorts = AutoACFindShortsController(player);
    if (!shorts) return;
    objc_setAssociatedObject(player, &kAutoACShortsSkipKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gAdvTickArmed++;
    AutoACTrace("shorts end armed: no loop");
    __weak id weakPlayer = player;
    __weak id weakShorts = shorts;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(remaining - 0.12, 0.0) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        id p = weakPlayer, s = weakShorts;
        if (!p || !s || ![kPrefs boolForKey:kShortsNoLoopKey]) return;
        double now = AutoACPlayerDouble(p, @[@"currentVideoMediaTime", @"currentVideoTime"]);
        if (now > 0 && now < duration * 0.5) return;   // người dùng đã tua lại hoặc đã sang Short khác
        // Không lặp: chuyển sang Short kế nếu cho phép cuộn, ngược lại dừng ở cuối
        BOOL advanced = NO;
        if (![kPrefs boolForKey:kShortsNoScrollKey]) {
            advanced = AutoACAdvanceShort(s, p);
            if (!advanced) {   // lần đầu chưa cuộn được (YouTube chưa sẵn sàng): thử lại một lần trước khi dừng
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    id p2 = weakPlayer, s2 = weakShorts;
                    if (!p2 || !s2 || [kPrefs boolForKey:kShortsNoScrollKey]) return;
                    if (!AutoACAdvanceShort(s2, p2) && [p2 respondsToSelector:@selector(pause)]) ((void (*)(id, SEL))objc_msgSend)(p2, @selector(pause));
                });
                return;
            }
        }
        if (!advanced && [p respondsToSelector:@selector(pause)]) ((void (*)(id, SEL))objc_msgSend)(p, @selector(pause));
    });
}

// Chặn YouTube tự cuộn sang Short kế khi Short phát hết (công tắc Tắt cuộn Short).
// Ngoài các lớp đã biết, dò thêm mọi lớp Reel/Shorts có hàm "…RequestsAdvance…" để không phụ thuộc tên lớp của từng bản YouTube.

#pragma mark - Tắt lỗi phát (từ YTKACE PlaybackFixHooks, chế độ Reload)
static double gPFTime = 0;
static BOOL gPFRetry = NO;

static id AutoACPFCall(id o, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    return [o respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(o, sel) : nil;
}

static BOOL AutoACPFReload(id pvc) {
    id video = AutoACPFCall(pvc, @"activeVideo");
    SEL reloadSel = NSSelectorFromString(@"player:reloadWithContext:");
    Class ctxClass = NSClassFromString(@"MLPlayerReloadContext");
    SEL ctxInit = NSSelectorFromString(@"initWithStartPlayback:refreshStreamingData:");
    if (!video || !ctxClass || ![video respondsToSelector:reloadSel]) return NO;
    id media = AutoACPFCall(video, @"mediaPlayer");
    if (!media) return NO;
    id alloc = [ctxClass alloc];
    if (![alloc respondsToSelector:ctxInit]) return NO;
    id ctx = ((id (*)(id, SEL, BOOL, BOOL))objc_msgSend)(alloc, ctxInit, YES, YES);
    if (!ctx) return NO;
    ((void (*)(id, SEL, id, id))objc_msgSend)(video, reloadSel, media, ctx);
    return YES;
}

static void AutoACPFRetryEvent(id overlay) {
    id responder = AutoACPFCall(overlay, @"parentResponder");
    Class ec = NSClassFromString(@"YTPlayerTapToRetryResponderEvent");
    SEL f = NSSelectorFromString(@"eventWithFirstResponder:");
    if (!responder || !ec || ![ec respondsToSelector:f]) return;
    id ev = ((id (*)(Class, SEL, id))objc_msgSend)(ec, f, responder);
    SEL send = NSSelectorFromString(@"send");
    if (ev && [ev respondsToSelector:send]) ((void (*)(id, SEL))objc_msgSend)(ev, send);
}

static double AutoACPFPos(id pvc) {
    SEL t = NSSelectorFromString(@"currentVideoMediaTime");
    return [pvc respondsToSelector:t] ? ((double (*)(id, SEL))objc_msgSend)(pvc, t) : -1;
}

static void AutoACPFSeek(id pvc, double pos) {
    AutoACSeekSeconds(pvc, pos);
}

static void AutoACInstallNoAutoplayHook(void) {
    AutoACHook(@"YTPlaybackConfig", @"setStartPlayback:", NO, "v", ^id(IMP original, SEL selector) {
        return ^void(id self_, BOOL start) {
            // Đang ở Shorts thì giữ nguyên: ép NO ở đây làm Short kế tiếp không tự phát khi cuộn sang, trông như Short không tự cuộn
            BOOL inShorts = gShortsOnScreenAt > 0 && CACurrentMediaTime() - gShortsOnScreenAt < 2.0;
            if (original) ((void (*)(id, SEL, BOOL))original)(self_, selector, inShorts ? start : NO);   // ngoài Shorts: không tự bắt đầu phát
        };
    });
}

static void AutoACInstallPlayFixHooks(void) {
    AutoACHook(@"YTPlayerViewController", @"currentVideoMediaTime", NO, "d", ^id(IMP original, SEL selector) {
        return ^double(id self_) {
            double v = original ? ((double (*)(id, SEL))original)(self_, selector) : 0;
            gPFTime = v;
            return v;
        };
    });
    AutoACHook(@"YTMainAppVideoPlayerOverlayViewController", @"handleError:", NO, "v", ^id(IMP original, SEL selector) {
        return ^void(id self_, id error) {
            NSError *e = [error isKindOfClass:NSError.class] ? error : nil;
            if (gPFRetry || !e || ![e.domain isEqualToString:@"com.google.ios.youtube.ErrorDomain.playback"] || !(e.code == 14 || e.code == 0)) {
                if (original) ((void (*)(id, SEL, id))original)(self_, selector, error);
                return;
            }
            gPFRetry = YES;
            id pvc = AutoACPFCall(self_, @"parentViewController");
            double saved = gPFTime;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (AutoACPFPos(pvc) > saved + 0.15) { gPFRetry = NO; return; }   // vẫn đang phát bình thường
                if (!AutoACPFReload(pvc)) AutoACPFRetryEvent(self_);
                if (!pvc) { gPFRetry = NO; return; }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    AutoACPFSeek(pvc, saved);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if (AutoACPFPos(pvc) <= saved + 0.05) {   // vẫn kẹt: thử lần cuối
                            if (!AutoACPFReload(pvc)) AutoACPFRetryEvent(self_);
                            AutoACPFSeek(pvc, saved);
                        }
                        gPFRetry = NO;
                    });
                });
            });
        };
    });
}

static void AutoACInstallShortsNoScrollHook(void) {
    NSMutableSet<NSString *> *done = [NSMutableSet set];
    void (^hookAdvance)(NSString *, NSString *) = ^(NSString *cls, NSString *selName) {
        NSString *key = [cls stringByAppendingString:selName];
        if ([done containsObject:key]) return;
        [done addObject:key];
        AutoACHook(cls, selName, NO, "v", ^id(IMP original, SEL selector) {
            return ^void(id self_, id sender) {
                gAdvSeen++; gAdvLast = [NSString stringWithFormat:@"%@ %@", cls, selName];
                if ([kPrefs boolForKey:kShortsNoScrollKey]) { gAdvBlocked++; AutoACTrace("shorts advance blocked"); return; }
                if (original) ((void (*)(id, SEL, id))original)(self_, selector, sender);
            };
        });
    };
    for (NSString *cls in @[@"YTShortsPlayerViewController", @"YTReelPlayerViewController", @"YTReelWatchRootViewController",
                            @"YTAppReelWatchRootViewController", @"YTReelContainerViewController", @"YTReelPlaybackViewController"]) {
        hookAdvance(cls, @"reelContentViewRequestsAdvanceToNextVideo:");
    }
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        const char *cname = class_getName(classes[i]);
        if (!cname || !(strstr(cname, "Reel") || strstr(cname, "Short"))) continue;
        unsigned int mcount = 0;
        Method *methods = class_copyMethodList(classes[i], &mcount);
        for (unsigned int m = 0; m < mcount; m++) {
            NSString *name = NSStringFromSelector(method_getName(methods[m]));
            if (![name containsString:@"RequestsAdvance"] || method_getNumberOfArguments(methods[m]) != 3) continue;
            char ret[8] = {0};
            method_getReturnType(methods[m], ret, sizeof(ret));
            if (ret[0] == 'v') hookAdvance(@(cname), name);
        }
        free(methods);
    }
    free(classes);
}

static void AutoACInstallFeatureHooks(void) {
    if (gSafeLevel >= 3) return;
    if (gSafeLevel >= 2) return;
    AutoACTrace("install hooks");
    ACGInstallTabBarHooks();
    if (gSafeLevel < 1) ACGInstallLiquidGlassDesign();
    AutoACInstallShortsNoScrollHook();
    if ([kPrefs boolForKey:kPlayFixKey]) AutoACInstallPlayFixHooks();
    if ([kPrefs boolForKey:kNoAutoplayKey]) AutoACInstallNoAutoplayHook();
    AutoACInstallShortsButtonHooks();
    AutoACInstallPlayerFloatHook();
    AutoACInstallPostToolsHooks();
    AutoACInstallContentHooks();
    AutoACInstallPromoHooks();
    AutoACInstallPaidPromoHooks();
    AutoACInstallStartupHooks();
    AutoACInstallGlassChromeHooks();

    // ── Ghi nhớ trình phát đang hoạt động (cho tải xuống, hẹn giờ, sao chép liên kết) ──
    AutoACHook(@"YTPlayerViewController", @"playbackController:didActivateVideo:withPlaybackData:", NO, "v40",
               ^id(IMP original, SEL selector) {
        return ^void(id self_, id a, id b, id c) {
            AutoACInstallCrashHandlers();
            AutoACTrace("didActivate: begin");
            ((void (*)(id, SEL, id, id, id))original)(self_, selector, a, b, c);
            AutoACTrace("didActivate: original done");
            gPlayerVC = self_;
            [[AutoACPiP shared] stopForYouTube];
            AutoACSponsorLoad(AutoACCurrentVideoID());
            AutoACTrace("didActivate: end");
        };
    });


    // ── SponsorBlock: kiểm tra mỗi lần thời gian phát thay đổi ──
    for (NSString *name in @[@"singleVideo:currentVideoTimeDidChange:", @"potentiallyMutatedSingleVideo:currentVideoTimeDidChange:"]) {
        AutoACHook(@"YTPlayerViewController", name, NO, "v", ^id(IMP original, SEL selector) {
            return ^void(id self_, id video, id time) {
                if (original) ((void (*)(id, SEL, id, id))original)(self_, selector, video, time);
                { static BOOL once; if (!once) { once = YES; AutoACTrace("first time tick"); } }
                [[AutoACPiP shared] stopForYouTube];
                if ([kPrefs boolForKey:kShortsNoLoopKey]) AutoACShortsTick(self_);
                AutoACLoopTick(self_);
                if (!gSponsorSegments) return;
                static CFTimeInterval lastEval = 0;   // không cần kiểm tra SponsorBlock ở mọi nhịp thời gian (đoạn bỏ qua cách mép 0,4 giây)
                CFTimeInterval nowT = CACurrentMediaTime();
                if (nowT - lastEval < 0.25) return;
                lastEval = nowT;
                double current = 0;
                SEL getter = NSSelectorFromString(@"currentVideoMediaTime");
                if ([self_ respondsToSelector:getter]) {
                    double v = ((double (*)(id, SEL))objc_msgSend)(self_, getter);
                    if (v > 0) current = v;
                }
                AutoACSponsorEvaluate(self_, current);
            };
        });
    }

}

%ctor {
    %init;
    AutoACSetupTrace();
    {   // build mới: bắt đầu lại từ đầu, không giữ mức an toàn của bản cũ
        if (![[kPrefs stringForKey:kBuildIDKey] isEqualToString:kCurrentBuildID]) {
            [kPrefs setObject:kCurrentBuildID forKey:kBuildIDKey];
            [kPrefs setInteger:0 forKey:kSafeLevelKey];
            [kPrefs setBool:NO forKey:kRunningFlagKey];
        }
    }

    // Phát hiện lần chạy trước bị thoát bất ngờ (cờ chạy còn nguyên) rồi tự tắt dần nhóm rủi ro
    {
        NSInteger level = [kPrefs integerForKey:kSafeLevelKey];
        BOOL wasDirty = [kPrefs boolForKey:kRunningFlagKey];
        if (wasDirty && level < 3 && [gPreviousTrace containsString:@"CRASH"]) {   // chỉ crash thật mới tắt bớt; bị hệ thống tắt thì không
            level++;
            [kPrefs setInteger:level forKey:kSafeLevelKey];
        }
        gSafeLevel = level;
        [kPrefs setBool:YES forKey:kRunningFlagKey];
        [kPrefs synchronize];
        void (^clear)(NSNotification *) = ^(NSNotification *n) {
            [kPrefs setBool:NO forKey:kRunningFlagKey];
            [kPrefs synchronize];
        };
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                          object:nil queue:nil usingBlock:clear];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillTerminateNotification
                                                          object:nil queue:nil usingBlock:clear];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                          object:nil queue:nil usingBlock:^(NSNotification *n) {
            [kPrefs setBool:YES forKey:kRunningFlagKey];
        }];
        // Không còn hộp thoại bật lên: nguyên nhân thoát lần trước nằm trong mục "Chẩn đoán hệ thống" (nút i)
        gPrevRunNote = wasDirty ? ([gPreviousTrace containsString:@"CRASH"] ? AutoACT(@"lần chạy trước: CRASH (xem nhật ký bên dưới)")
                                   : AutoACT(@"lần chạy trước: app bị hệ thống tắt (thiếu bộ nhớ/treo), không phải lỗi AutoAC")) : AutoACT(@"lần chạy trước: bình thường");
    }

    // Mặc định BẬT tự dọn cache, chặn quảng cáo, phát nền (YouTube X) và thanh tab kính lỏng.
    // Ẩn tab Shorts, lặp video, tắt tự phát mặc định tắt.
    // Hai nút tải trong trình phát (nút thay nút Tải xuống gốc dưới video, icon tải cạnh nút tốc độ): mặc định BẬT cả hai, mỗi công tắc độc lập.
    // Một lần: bật cả hai cho cả người đang để icon tải TẮT (giá trị do bản cũ đặt); sau đó tắt/bật tuỳ ý.
    if (![kPrefs boolForKey:@"kDLBothDefault1"]) {
        [kPrefs setBool:YES forKey:kPlayerButtonKey];
        [kPrefs setBool:YES forKey:kPlayerFloatKey];
        [kPrefs setBool:YES forKey:@"kDLBothDefault1"];
    }
    [kPrefs registerDefaults:@{kAutoClearCacheKey: @YES, kYTXAdsKey: @YES, kYTXBackgroundKey: @YES,
                                                              kAskQualityKey: @YES, kShareAfterKey: @YES,
                               kAskDestKey: @YES, kHidePromosKey: @YES, kHidePaidPromoKey: @YES, kShortsFullBleedKey: @YES, kGlassTopKey: @NO, kGlassSheetKey: @NO, kGlassPlayerKey: @NO, kSponsorAlertKey: @YES,
                               kDiagKey: @YES, kPlayerButtonKey: @YES, kCommentToolsKey: @YES, kPostImageKey: @YES, kPlayerFloatKey: @YES, kPlayerSpeedBtnKey: @YES, kPlayerPiPKey: @YES, kPlayerSleepBtnKey: @YES, kPlayerExternalKey: @YES, kShortsNoLoopKey: @YES}];
    [kPrefs removeObjectForKey:@"ACG.Preference.Tabs.ShortsDarkOff"];   // 2.1.66-2.1.68: công tắc Dock tối ở Short đã bỏ
    AutoACOverlayMigrateLegacy();   // 2.1.64: hai công tắc hàng trên/hàng dưới → Tuỳ chỉnh Overlay
    [kPrefs removeObjectForKey:@"kOLEDMode"];   // chế độ OLED đã bỏ: xoá giá trị cũ
    if (![kPrefs boolForKey:@"kShortsNoLoopDefault1"]) {   // một lần: bật Tắt lặp Short cho cả người đã có giá trị cũ
        [kPrefs setBool:YES forKey:kShortsNoLoopKey];
        [kPrefs setBool:YES forKey:@"kShortsNoLoopDefault1"];
    }
    [kPrefs registerDefaults:@{
        @"ACG.Preference.Tabs.Startup": @"",
        @"ACG.Preference.Tabs.GlassMinimize": @NO,
        @"ACG.Preference.Tabs.SelectedTint": @0,
        @"ACG.Preference.Tabs.Hidden.Create": @NO,
        @"ACG.Preference.Tabs.Hidden.Music": @YES,
        @"ACG.Preference.Tabs.Hidden.Live": @YES,
        @"ACG.Preference.Tabs.Hidden.Gaming": @YES,
        @"ACG.Preference.Tabs.Hidden.News": @YES,
        @"ACG.Preference.Tabs.Hidden.Posts": @YES,
        @"ACG.Preference.Tabs.Hidden.Sports": @YES,
        @"ACG.Preference.Tabs.Hidden.Learning": @YES,
        @"ACG.Preference.Tabs.Hidden.Fashion": @YES,
        @"ACG.Preference.Tabs.Hidden.Playlists": @YES,
        @"ACG.Preference.Tabs.Hidden.History": @YES,
        @"ACG.Preference.Tabs.Hidden.Notifs": @YES,
        @"ACG.Preference.Tabs.Hidden.WatchLater": @YES}];
    if ([kPrefs boolForKey:kHideShortsKey]) {   // công tắc Ẩn Shorts cũ đã bỏ: chuyển sang ẩn tab Shorts trong Tuỳ chỉnh tab
        [kPrefs setBool:YES forKey:@"ACG.Preference.Tabs.Hidden.Shorts"];
        [kPrefs removeObjectForKey:kHideShortsKey];
    }
    AutoACInstallFeatureHooks();
    AutoACTrace("hooks installed");

    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidEnterBackgroundNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) { AutoACCleanOnBackground(); }];

    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) {
        AutoACAttachToWindow(AutoACKeyWindow());
        AutoACAutoCleanOnce();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AutoACResumeDownloadsOnce(); });
    }];

    // Phòng khi app đã active trước lúc dylib nạp xong
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AutoACAttachToWindow(AutoACKeyWindow());
        AutoACAutoCleanOnce();
    });
}

#pragma mark - Ngôn ngữ (tự theo hệ thống: tiếng Việt → giữ nguyên; ngôn ngữ khác → tiếng Anh)
// Tìm AutoAC.bundle (chứa en.lproj / vi.lproj/Localizable.strings) ở các vị trí thường gặp khi inject hoặc cài bằng .deb
static NSBundle *AutoACLanguageBundle(void) {
    static NSBundle *bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *main = NSBundle.mainBundle.bundlePath;
        NSArray<NSString *> *paths = @[
            [main stringByAppendingPathComponent:@"AutoAC.bundle"],
            [main stringByAppendingPathComponent:@"Frameworks/AutoAC.bundle"],
            @"/var/jb/Library/Application Support/AutoAC.bundle",
            @"/Library/Application Support/AutoAC.bundle"];
        for (NSString *path in paths) {
            if ([NSFileManager.defaultManager fileExistsAtPath:path]) { bundle = [NSBundle bundleWithPath:path]; if (bundle) break; }
        }
    });
    return bundle;
}

// Ngôn ngữ đang dùng: lấy theo hệ thống trong số các ngôn ngữ AutoAC có (vi, en); không khớp thì dùng tiếng Anh
static NSString *AutoACLanguageCode(void) {
    static NSString *code;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *available = @[@"vi", @"en"];
        NSBundle *bundle = AutoACLanguageBundle();
        if (bundle.localizations.count) available = bundle.localizations;
        NSString *best = [NSBundle preferredLocalizationsFromArray:available forPreferences:NSLocale.preferredLanguages].firstObject;
        NSString *first = (NSLocale.preferredLanguages.firstObject ?: @"en").lowercaseString;
        if ([first hasPrefix:@"vi"]) best = @"vi";
        code = best.length ? best : @"en";
    });
    return code;
}

static BOOL AutoACUseVietnamese(void) {
    return [AutoACLanguageCode() hasPrefix:@"vi"];
}

static NSDictionary<NSString *, NSString *> *AutoACBundleStrings(void) {
    static NSDictionary *strings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSBundle *bundle = AutoACLanguageBundle();
        NSString *file = [bundle pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:AutoACLanguageCode()];
        strings = file ? [NSDictionary dictionaryWithContentsOfFile:file] : nil;
        if (!strings) strings = @{};
    });
    return strings;
}

static NSDictionary<NSString *, NSString *> *AutoACEnglishTable(void) {
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
        @" Áp dụng khi cuộn tới Short mới hoặc mở lại app.": @" Applies when you scroll to a new Short or reopen the app.",
        @"%g giây": @"%g sec",
        @"Không phát được luồng này": @"Could not play this stream",
        @"Ẩn thẻ sản phẩm": @"Hide product tags",
        @"Sản phẩm, giỏ hàng": @"Products, cart",
        @"Ẩn thẻ sản phẩm và giỏ hàng gắn trên Short. Chỉ tác động lên lớp phủ của Short đang xem, không quét trang chủ hay danh sách nên không gây trắng trang hay lag.": @"Hides product tags and carts attached to a Short. Only affects the overlay of the Short being watched; it never scans the home feed or lists, so it cannot cause blank pages or lag.",
        @"Mã lớp phủ Shorts": @"Shorts overlay IDs",
        @"Tiếp tục tải video dở": @"Resuming unfinished downloads",
        @"Ẩn chơi game": @"Hide games",
        @"Ẩn mục Chơi game (Playables) xuất hiện giữa các video trong trang chủ. Có thể để lại khoảng trống nhỏ. Cần mở lại app.": @"Hides the Games (Playables) section between videos on the home feed. May leave a small gap. Restart the app to apply.",
        @"Hàng đợi": @"Queue",
        @"Đã thêm vào hàng đợi tải": @"Added to download queue",
        @"Sao lưu cài đặt": @"Back up settings",
        @"Xuất ra tệp": @"Export to file",
        @"Xuất toàn bộ cài đặt của AutoAC (kể cả thanh tab) ra một tệp .plist để lưu vào Tệp hoặc gửi đi. Dùng Khôi phục cài đặt để nhập lại.": @"Exports all AutoAC settings (including the tab bar) to a .plist file you can save to Files or send. Use Restore settings to import it back.",
        @"Khôi phục cài đặt": @"Restore settings",
        @"Nhập từ tệp": @"Import from file",
        @"Chọn tệp .plist đã sao lưu để khôi phục cài đặt của AutoAC. Chỉ nhận các tuỳ chọn của AutoAC. Cần mở lại app để áp dụng.": @"Pick a backed-up .plist file to restore AutoAC settings. Only AutoAC options are accepted. Restart the app to apply.",
        @"Đã khôi phục cài đặt": @"Settings restored",
        @"Tệp sao lưu không hợp lệ": @"Invalid backup file",
        @"Không tạo được tệp sao lưu": @"Could not create backup file",
        @"đang tính…\n": @"calculating…\n",
        @"\n[Dung lượng] mục lớn nhất:\n%@": @"\n[Storage] largest items:\n%@",
        @"Tùy chỉnh YouTube\n": @"Customize YouTube\n",
        @"tự dọn cache khi thoát app": @"auto-clean cache when leaving the app",
        @"thanh tab Glass, thêm và sắp xếp tab, ẩn hiệu ứng mở, bài đăng, Mix, Short ở trang chủ": @"Glass tab bar, add and reorder tabs, hide launch animation, posts, Mixes and Shorts on Home",
        @"tốc độ, PiP, tự thử lại khi lỗi, tắt tự động phát, tắt lặp và tắt cuộn Short": @"speed, PiP, auto-retry on errors, disable autoplay, disable Short loop and auto-scroll",
        @"ẩn nút Thích, bình luận, chia sẻ, lưu, Remix, âm thanh, thẻ tạm dừng": @"hide Like, Comment, Share, Save, Remix, Sound and pause card",
        @"video, âm thanh, ảnh bìa, ảnh bài đăng, sao chép và dịch bình luận": @"video, audio, thumbnails, post images, copy and translate comments",
        @"Bài đăng": @"Posts",
        @"Bài đăng cộng đồng": @"Community posts",
        @"Báo khi bỏ qua": @"Notify on skip",
        @"Bình luận": @"Comments",
        @"Bạn": @"You",
        @"Bản dịch": @"Translation",
        @"Bảng chia sẻ / Tệp": @"Share sheet / Files",
        @"Bật nhãn": @"Show labels",
        @"Bật thu gọn": @"Minimize bar",
        @"Bật tự bỏ qua": @"Auto skip",
        @"Bộ nhớ": @"Storage",
        @"CHẨN ĐOÁN HỆ THỐNG": @"SYSTEM DIAGNOSTICS",
        @"CHẾ ĐỘ AN TOÀN": @"SAFE MODE",
        @"CHỨC NĂNG CHÍNH\n": @"MAIN FEATURES\n",
        @"Cache đã sạch": @"Cache is clean",
        @"Chú thích các chức năng": @"Feature notes",
        @"Chưa cài Infuse": @"Infuse not installed",
        @"Chưa cài VLC": @"VLC not installed",
        @"Chưa nhận diện được video": @"Video not recognized",
        @"Chạm nút Tải xuống gốc của YouTube (hàng nút dưới video) sẽ mở bảng tải của AutoAC thay cho bảng của YouTube. Có thể bật cùng Nút icon tải khi cần.": @"Tapping YouTube's own Download button (the row under the video) opens the AutoAC download sheet instead of YouTube's. Can be combined with the Download icon button.",
        @"Chất lượng video": @"Video quality",
        @"Chặn popup và thẻ mời Premium": @"Block Premium popups and upsell cards",
        @"Chặn quảng cáo": @"Block ads",
        @"Chặn quảng cáo trong video, trang chủ và Shorts (YouTube X). Cần mở lại app.": @"Blocks ads in videos, the home feed and Shorts (YouTube X). Restart the app to apply.",
        @"Chỉ chữ": @"Text only",
        @"Chọn chất lượng": @"Choose quality",
        @"Chọn các loại đoạn SponsorBlock sẽ tự bỏ qua: tài trợ, tự quảng bá, nhắc tương tác, mở đầu, kết, xem trước, phần không phải nhạc, đoạn thừa.": @"Choose which SponsorBlock segment types are skipped automatically: sponsor, self-promo, interaction reminders, intro, outro, preview, non-music and filler.",
        @"Chọn loại đoạn tự bỏ qua": @"Choose segment types to skip",
        @"Chọn phụ đề": @"Choose subtitles",
        @"Chọn trước khi tải": @"Choose before downloading",
        @"Chọn tốc độ phát khi mở video (0.5x đến 3x) và số giây tua khi chạm đúp (5 đến 60 giây). Chọn Theo YouTube để dùng mặc định.": @"Choose the playback speed used when a video opens (0.5x to 3x) and how many seconds a double-tap skips (5 to 60). Choose Follow YouTube to keep the default.",
        @"Chờ video phát vài giây rồi thử lại": @"Let the video play for a few seconds, then try again",
        @"Cột nút bên phải": @"Right button column",
        @"Dưới nút bánh răng": @"Below the gear button",
        @"Dịch sang ": @"Translate to ",
        @"Dịch và sao chép": @"Translate and copy",
        @"Dọn cache ngay": @"Clean cache now",
        @"Dọn cache tự động": @"Auto clean cache",
        @"Dọn được %@ · cache %@": @"%@ can be freed · cache %@",
        @"Dừng sau %ld phút": @"Stops in %ld min",
        @"Dữ liệu từ sponsor.ajay.app": @"Data from sponsor.ajay.app",
        @"Ghép video và âm thanh thất bại": @"Failed to merge video and audio",
        @"Giao diện": @"Appearance",
        @"Hiện bảng chọn độ phân giải trước khi tải video. Tắt đi sẽ tải chất lượng cao nhất có thể.": @"Shows a resolution picker before downloading a video. When off, the highest quality available is downloaded.",
        @"Hiện nút lưu ở góc trên bên trái khi xem ảnh trong bài đăng cộng đồng, lưu bản gốc vào Ảnh. Cần mở lại app.": @"Shows a save button in the top-left corner when viewing images in community posts and saves the original to Photos. Restart the app to apply.",
        @"Hiện thông báo ngắn cho biết loại đoạn vừa được bỏ qua.": @"Shows a short notice telling which segment type was just skipped.",
        @"Hiện thông báo nhỏ": @"Show small notice",
        @"Hiện tên dưới icon": @"Show icon under tab",
        @"Hiện tại: ": @"Current: ",
        @"Huỷ": @"Cancel",
        @"Huỷ tải": @"Cancel download",
        @"Hãy mở một video trước": @"Open a video first",
        @"Hãy đóng và mở lại YouTube": @"Close and reopen YouTube",
        @"Hẹn giờ": @"Timer",
        @"Học tập": @"Learning",
        @"Hỏi chất lượng": @"Ask quality",
        @"Hỏi nơi lưu": @"Ask where to save",
        @"Khi chạm dừng video": @"When tapping to pause a video",
        @"Khi tắt màn hình": @"When the screen turns off",
        @"Khi video báo \"Đã xảy ra lỗi, nhấn để thử lại\" hoặc đứng hình, AutoAC tự tải lại luồng phát và tua về đúng vị trí đang xem (theo Playback Fix của YTKACE, chế độ Reload). Cần mở lại app.": @"When a video shows \"An error occurred, tap to retry\" or freezes, AutoAC reloads the stream and seeks back to where you were (based on YTKACE Playback Fix, Reload mode). Restart the app to apply.",
        @"Khám phá": @"Explore",
        @"Khôi phục mặc định": @"Restore defaults",
        @"Không bật được PiP": @"Could not start PiP",
        @"Không có gì để dọn · cache ": @"Nothing to clean · cache ",
        @"Không có thông tin": @"No information",
        @"Không dịch được": @"Could not translate",
        @"Không ghép được video và âm thanh": @"Could not merge video and audio",
        @"Không lưu được vào Ảnh": @"Could not save to Photos",
        @"Không lưu được, hãy cấp quyền Ảnh": @"Could not save, please allow Photos access",
        @"Không lấy được phụ đề": @"Could not get subtitles",
        @"Không phát lặp lại một Short": @"Do not loop a Short",
        @"Không tải được video": @"Could not download video",
        @"Không tải được âm thanh": @"Could not download audio",
        @"Không tải được ảnh": @"Could not download image",
        @"Không tải được ảnh bìa": @"Could not download cover image",
        @"Không tự sang Short kế": @"Do not auto-advance to the next Short",
        @"Không đọc được bình luận": @"Could not read comments",
        @"Khỏi trang chủ": @"Off the home feed",
        @"Kiểm tra kết nối mạng": @"Check your network connection",
        @"Kiểu màu": @"Color",
        @"Kiểu màu tab": @"Tab color style",
        @"Kiểu thanh tab": @"Tab bar style",
        @"Kênh đăng ký": @"Subscriptions",
        @"Liên kết tại thời điểm này": @"Link at this moment",
        @"Liên kết video": @"Video link",
        @"Liên kết, tiêu đề, mô tả": @"Link, title, description",
        @"Loại đoạn tự bỏ qua": @"Segment types to skip",
        @"Lưu": @"Save",
        @"Lưu sau khi tải": @"Save after download",
        @"Lưu thành tệp .txt": @"Save as .txt file",
        @"Lưu video vào đâu?": @"Save video where?",
        @"Lưu vào Ảnh": @"Save to Photos",
        @"Lưu ảnh bài đăng": @"Save post images",
        @"Lưu ảnh bìa": @"Save cover image",
        @"Lịch sử": @"History",
        @"MÃ NGUỒN THAM KHẢO\n": @"REFERENCE SOURCES\n",
        @"Màu chữ, icon tab chọn": @"Text and icon color of selected tab",
        @"Màu tab đang chọn": @"Selected tab color",
        @"Mô tả": @"Description",
        @"Mặc định": @"Default",
        @"Mặc định hoặc Glass": @"Default or Glass",
        @"Khi thoát app": @"When leaving the app",
        @"Mở bảng chia sẻ": @"Open share sheet",
        @"Mở chia sẻ": @"Open share sheet",
        @"Mở lại app để áp dụng": @"Restart the app to apply",
        @"Mở từ nút Tải xuống. Lưu ảnh bìa độ phân giải cao nhất của video hoặc Short đang xem vào thư viện Ảnh.": @"Opens from the Download button. Saves the highest-resolution cover image of the current video or Short to your Photos library.",
        @"Mở từ nút Tải xuống. Sao chép liên kết ngắn, liên kết tại thời điểm đang xem, tiêu đề, mô tả, hoặc phụ đề (thường, kèm thời gian, dịch sang tiếng Việt, có thể lưu thành tệp .txt).": @"Opens from the Download button. Copies the short link, the link at the current time, the title, the description or subtitles (plain, timestamped, translated to your language, can be saved as a .txt file).",
        @"Mở từ nút Tải xuống. Tải video hoặc Short đang xem kèm âm thanh (MP4, H.264). Có thể chọn chất lượng và nơi lưu (Ảnh hoặc bảng chia sẻ) trước khi tải.": @"Opens from the Download button. Downloads the current video or Short with audio (MP4, H.264). You can choose quality and where to save (Photos or share sheet) before downloading.",
        @"Mở từ nút Tải xuống. Tải âm thanh chất lượng cao nhất (M4A) của video hoặc Short đang xem, rồi lưu vào Tệp hoặc app khác qua bảng chia sẻ.": @"Opens from the Download button. Downloads the highest-quality audio (M4A) of the current video or Short and saves it to Files or another app via the share sheet.",
        @"Mở video, chạm đúp": @"On video open, double-tap",
        @"Nhạc": @"Music",
        @"Nhấn giữ bình luận": @"Long-press a comment",
        @"Nhắc tương tác (like, đăng ký)": @"Interaction reminder (like, subscribe)",
        @"Nút lưu khi xem ảnh": @"Save button for images",
        @"Nút tải xuống": @"Download button",
        @"Phát bằng": @"Play with",
        @"Phát lại": @"Playback",
        @"Phát ngoài": @"Play externally",
        @"Chất lượng": @"Quality",
        @"Lặp video": @"Loop video",
        @"Chưa có danh sách chất lượng": @"No quality list yet",
        @"Hãy thử lại khi video đã phát": @"Try again once the video is playing",
        @"Không đổi được chất lượng": @"Could not change quality",
        @"Chưa xác định được video": @"Could not identify the video",
        @"Đã bật lặp video": @"Loop on",
        @"Đã tắt lặp video": @"Loop off",
        @"Phát nền": @"Background play",
        @"Phần không phải nhạc": @"Non-music section",
        @"Phụ đề": @"Subtitles",
        @"Phụ đề dịch theo ngôn ngữ thiết bị": @"Subtitles translated to device language",
        @"Phụ đề kèm thời gian": @"Timestamped subtitles",
        @"Quay lại menu": @"Back to menu",
        @"Quảng cáo": @"Ads",
        @"Sao chép": @"Copy",
        @"Sao chép bản dịch": @"Copy translation",
        @"Sao chép dịch": @"Copy translated",
        @"Sao chép dịch: nhấn giữ vào một bình luận để sao chép nội dung, dịch sang ngôn ngữ của thiết bị hoặc dịch rồi sao chép.": @"Copy translation: long-press a comment to copy its text, translate it to your device language, or translate and copy.",
        @"Short phát hết sẽ không lặp lại. Nếu Tắt cuộn Short đang tắt thì tự chuyển sang Short kế tiếp; nếu Tắt cuộn Short đang bật thì dừng lại ở cuối Short.": @"A Short that finishes will not loop. If Disable Short scroll is off it moves on to the next Short; if it is on it stops at the end of the Short.",
        @"TAB ĐANG HIỆN": @"VISIBLE TABS",
        @"TAB ĐANG ẨN": @"HIDDEN TABS",
        @"Tab hiện khi mở app": @"Tab shown at launch",
        @"Tab khi mở app": @"Tab at launch",
        @"Tab, thứ tự, Liquid Glass": @"Tabs, order, Liquid Glass",
        @"Thay nút Tải xuống gốc": @"Replace the original Download button",
        @"Thiết bị không hỗ trợ PiP": @"This device does not support PiP",
        @"Thoát chế độ an toàn": @"Exit safe mode",
        @"Thu nhỏ khi cuộn": @"Minimize on scroll",
        @"Thông báo": @"Notifications",
        @"Thông tin": @"Info",
        @"Thẻ đề xuất trong bảng tin": @"Suggestion cards in the feed",
        @"Thể thao": @"Sports",
        @"Thời trang": @"Fashion",
        @"Thứ tự, ẩn hiện, Liquid Glass": @"Order, show or hide, Liquid Glass",
        @"Tin tức": @"News",
        @"Tiêu đề": @"Title",
        @"Tiếp tục": @"Resume",
        @"Tiếp tục phát khi thoát app hoặc tắt màn hình (YouTube X). Cần mở lại app.": @"Keeps playing when you leave the app or turn off the screen (YouTube X). Restart the app to apply.",
        @"Trang chủ": @"Home",
        @"Trong trình phát": @"In the player",
        @"Trình phát hệ thống": @"System player",
        @"Trò chơi": @"Gaming",
        @"Trước khi tải video, hỏi lưu vào Ảnh hay mở bảng chia sẻ. Tắt đi sẽ theo tuỳ chọn Mở bảng chia sẻ.": @"Before downloading a video, asks whether to save to Photos or open the share sheet. When off, follows the Open share sheet option.",
        @"Trực tiếp": @"Live",
        @"Tua chạm đúp: ": @"Double-tap skip: ",
        @"Tua khi chạm đúp": @"Double-tap skip",
        @"Tuỳ chỉnh tab": @"Customize tabs",
        @"Tuỳ chỉnh thanh tab dưới cùng: đổi thứ tự, ẩn hoặc hiện tab (kể cả Shorts), thêm tab (Nhạc, Trực tiếp, Trò chơi, Tin tức, Thể thao, Học tập, Thời trang, Playlist, Lịch sử, Thông báo, Xem sau, Bài đăng), đổi tên tab, chọn tab khi mở app, kiểu thanh tab Mặc định hoặc Glass, thu nhỏ khi cuộn và màu tab đang chọn. Cần mở lại app để áp dụng.": @"Customize the bottom tab bar: reorder, show or hide tabs (including Shorts), add tabs (Music, Live, Gaming, News, Sports, Learning, Fashion, Playlist, History, Notifications, Watch later, Posts), rename tabs, choose the tab shown at launch, bar style Default or Glass, minimize on scroll and the selected tab color. Restart the app to apply.",
        @"TÁC GIẢ\n": @"AUTHOR\n",
        @"Tài khoản": @"Account",
        @"Tài trợ": @"Sponsor",
        @"Tác vụ nhanh": @"Quick actions",
        @"Tùy chỉnh YouTube": @"Customize YouTube",
        @"Tạm dừng": @"Pause",
        @"Tạo": @"Create",
        @"Tải không thành công": @"Download failed",
        @"Tải video": @"Download video",
        @"Tải xuống": @"Download",
        @"Tải âm thanh": @"Download audio",
        @"Tắt": @"Off",
        @"Tắt cuộn Short": @"Disable Short scroll",
        @"Tắt lặp Short": @"Disable Short loop",
        @"Tắt lặp Short ~": @"Disable Short loop ~",
        @"Tắt lỗi phát": @"Disable playback errors",
        @"Tắt tự động cuộn Short: khi bật, Short phát hết sẽ ở lại và lặp lại, không tự chuyển sang Short tiếp theo. Vuốt tay vẫn chuyển bình thường. Kết hợp với Tắt lặp Short để dừng hẳn ở cuối.": @"Disable auto scroll for Shorts: when on, a Short that finishes stays and repeats instead of moving to the next one. Swiping still works normally. Combine with Disable Short loop to stop completely at the end.",
        @"Tốc độ": @"Speed",
        @"Tốc độ khi mở video": @"Speed when opening a video",
        @"Tốc độ khi mở video: ": @"Speed when opening a video: ",
        @"Tốc độ và tua": @"Speed and skip",
        @"Tự mở bảng chia sẻ khi tải xong để lưu vào Tệp, Ảnh hoặc gửi cho app khác.": @"Opens the share sheet automatically after downloading so you can save to Files, Photos or send to another app.",
        @"Tự quảng bá": @"Self-promo",
        @"Tự thử lại khi video báo lỗi": @"Auto retry when a video reports an error",
        @"Tự tua qua các đoạn tài trợ, tự quảng bá, nhắc like và đăng ký do cộng đồng SponsorBlock đánh dấu. Chọn các loại đoạn ở mục Sponsor block. Áp dụng từ video tiếp theo.": @"Automatically skips sponsor, self-promo, like and subscribe reminders marked by the SponsorBlock community. Choose segment types in the Sponsor block section. Applies from the next video.",
        @"Tự xoá cache và tệp tạm của YouTube cũ quá 30 phút mỗi khi thoát app. Không đụng tới video đã tải hay cài đặt.": @"Clears YouTube cache and temporary files older than 30 minutes whenever you leave the app. Does not touch downloaded videos or settings.",
        @"Video có thể không có phụ đề": @"Video may have no subtitles",
        @"Video không có phụ đề": @"Video has no subtitles",
        @"Video này không có luồng để phát ngoài": @"This video has no stream to play externally",
        @"Video này không hỗ trợ tải": @"This video cannot be downloaded",
        @"Video này không mở được PiP": @"This video cannot open PiP",
        @"Video, trang chủ, Shorts": @"Videos, home, Shorts",
        @"Vào thẳng trang chủ": @"Straight to home",
        @"Vào Ảnh": @"To Photos",
        @"Xem trước, tóm tắt": @"Preview, recap",
        @"Xoá các tệp cache không còn dùng của YouTube, giữ nguyên dữ liệu đăng nhập, rồi báo dung lượng đã giải phóng. Dọn cache tự động chỉ xoá tệp cũ hơn 30 phút. Không ảnh hưởng video đã tải hay cài đặt.": @"Deletes YouTube cache files that are no longer needed, keeping your login data, then reports the space freed. Auto clean only removes files older than 30 minutes. Does not affect downloaded videos or settings.",
        @"[Nhật ký crash]\n%@\n": @"[Crash log]\n%@\n",
        @"\n[Shorts] nút cột phải:\n%@\n": @"\n[Shorts] right column buttons:\n%@\n",
        @"\n[Tab] hook %@ · đã nhận %ld tab, hiện %ld\n%@\n": @"\n[Tab] hook %@ · received %ld tabs, showing %ld\n%@\n",
        @"an toàn mức %ld · kính lỏng %@\n": @"safe level %ld · liquid glass %@\n",
        @"bài đăng": @"posts",
        @"bản %@ · iOS %@ · %@\n": @"build %@ · iOS %@ · %@\n",
        @"bật": @"on",
        @"chưa gắn": @"not attached",
        @"chặn quảng cáo, ẩn popup Premium, Sponsor block": @"ad blocking, hide Premium popups, Sponsor block",
        @"cài đặt": @"settings",
        @"có": @"yes",
        @"cửa sổ %.0f×%.0f · vùng an toàn T%.0f D%.0f Tr%.0f Ph%.0f\n": @"window %.0f×%.0f · safe area T%.0f B%.0f L%.0f R%.0f\n",
        @"danh sách phát": @"playlist",
        @"học tập": @"learning",
        @"không": @"no",
        @"kiểu %@ · thu nhỏ %@ · tab ẩn %lu · thứ tự %lu · tên riêng %lu": @"kind %@ · minimize %@ · hidden tabs %lu · order %lu · custom names %lu",
        @"kính lỏng iOS 26: %@ · hook kính: %@\n": @"liquid glass iOS 26: %@ · glass hook: %@\n",
        @"lưu": @"save",
        @"lần chạy trước: CRASH (xem nhật ký bên dưới)": @"last run: CRASH (see log below)",
        @"lần chạy trước: app bị hệ thống tắt (thiếu bộ nhớ/treo), không phải lỗi AutoAC": @"last run: killed by the system (low memory/hang), not an AutoAC error",
        @"lần chạy trước: bình thường": @"last run: normal",
        @"lần chạy trước: không rõ": @"last run: unknown",
        @"lịch sử": @"history",
        @"nhạc": @"music",
        @"nút tải phủ %@ · nút icon tải %@ · tốc độ %@ · PiP %@\n": @"download overlay %@ · download icon button %@ · speed %@ · PiP %@\n",
        @"thông báo": @"notifications",
        @"thể thao": @"sports",
        @"thời trang": @"fashion",
        @"tin tức": @"news",
        @"trò chơi": @"gaming",
        @"trực tiếp": @"live",
        @"tải xuống": @"download",
        @"tắt": @"off",
        @"âm thanh": @"audio",
        @"Đang bật mức %ld: AutoAC đã tắt bớt một số nhóm chức năng vì app từng crash (mức 1: kính lỏng gốc; mức 2: thêm hook trình phát; mức 3: chỉ còn menu).": @"Safe mode level %ld is on: AutoAC turned off some feature groups because the app crashed (level 1: native liquid glass and OLED; level 2: plus player hooks; level 3: menu only).",
        @"Đang chuẩn bị": @"Preparing",
        @"Đang dịch": @"Translating",
        @"Đang ghép tệp": @"Merging files",
        @"Đang lưu ảnh": @"Saving image",
        @"Đang lấy phụ đề": @"Getting subtitles",
        @"Đang lấy thông tin": @"Getting info",
        @"Đang tính…": @"Calculating…",
        @"Đang tải video": @"Downloading video",
        @"Đang tải âm thanh": @"Downloading audio",
        @"Đang tải ảnh bìa": @"Downloading cover image",
        @"Đang tắt. Chỉ tự bật khi app crash thật; app bị hệ thống tắt không tính.": @"Off. Turns on only after a real crash; being killed by the system does not count.",
        @"Đoạn kết, credit": @"Outro, credits",
        @"Đoạn mở đầu": @"Intro",
        @"Đoạn thừa": @"Filler",
        @"Đã bỏ qua": @"Skipped",
        @"Đã dịch và sao chép": @"Translated and copied",
        @"Đã dọn %@": @"Cleaned %@",
        @"Đã huỷ tải": @"Download cancelled",
        @"Đã lưu vào Ảnh": @"Saved to Photos",
        @"Đã lưu ảnh bìa vào Ảnh": @"Cover image saved to Photos",
        @"Đã lưu ảnh vào Ảnh": @"Image saved to Photos",
        @"Đã sao chép": @"Copied",
        @"Đã sao chép bình luận": @"Comment copied",
        @"Đã sao chép bản dịch": @"Translation copied",
        @"Đã sao chép liên kết": @"Link copied",
        @"Đã sao chép mô tả": @"Description copied",
        @"Đã sao chép tiêu đề": @"Title copied",
        @"Đã thoát chế độ an toàn": @"Left safe mode",
        @"Đã tích hợp: %@\n": @"Integrated: %@\n",
        @"Đã tạm dừng": @"Paused",
        @"Đã tải xong": @"Download complete",
        @"Đã tắt hẹn giờ": @"Timer turned off",
        @"Đĩa nhạc góc dưới": @"Music disc, bottom corner",
        @"Đưa toàn bộ tuỳ chọn của AutoAC về giá trị mặc định. Cần mở lại app để áp dụng.": @"Resets every AutoAC option to its default value. Restart the app to apply.",
        @"Đặt lại cài đặt": @"Reset settings",
        @"Để trống để dùng lại tên mặc định.": @"Leave empty to use the default name.",
        @"Đổi tên tab": @"Rename tab",
        @"đã gắn": @"attached",
        @"Ảnh chưa tải xong": @"Image not finished downloading",
        @"Ảnh hoặc bảng chia sẻ": @"Photos or share sheet",
        @"Ẩn Remix": @"Hide Remix",
        @"Ẩn bài đăng": @"Hide posts",
        @"Ẩn bình luận": @"Hide comments",
        @"Ẩn chia sẻ": @"Hide share",
        @"Ẩn các bài đăng cộng đồng (bài viết của kênh) xuất hiện trong trang chủ. Có thể để lại khoảng trống nhỏ. Cần mở lại app.": @"Hides community posts (channel posts) that appear in the home feed. May leave a small gap. Restart the app to apply.",
        @"Ẩn các hàng video Short xuất hiện giữa các video trong trang chủ. Không ảnh hưởng tab Shorts. Có thể để lại khoảng trống nhỏ. Cần mở lại app.": @"Hides rows of Short videos that appear between videos in the home feed. Does not affect the Shorts tab. May leave a small gap. Restart the app to apply.",
        @"Ẩn gợi ý Mix": @"Hide Mix suggestions",
        @"Ẩn hiệu ứng logo YouTube lúc khởi động để vào app nhanh hơn.": @"Hides the YouTube logo animation at launch so the app opens faster.",
        @"Ẩn hiệu ứng mở": @"Hide launch animation",
        @"Ẩn nút Bình luận trong Shorts.": @"Hides the Comments button in Shorts.",
        @"Ẩn nút Chia sẻ trong Shorts.": @"Hides the Share button in Shorts.",
        @"Ẩn nút Lưu vào danh sách phát trong Shorts.": @"Hides the Save to playlist button in Shorts.",
        @"Ẩn nút Remix trong Shorts.": @"Hides the Remix button in Shorts.",
        @"Ẩn nút Thích": @"Hide Like button",
        @"Ẩn nút Thích trong Shorts.": @"Hides the Like button in Shorts.",
        @"Ẩn nút lưu": @"Hide save button",
        @"Ẩn nút âm thanh (đĩa nhạc) trong Shorts.": @"Hides the sound button (music disc) in Shorts.",
        @"Ẩn thẻ gợi ý (nudge) và Mix trong bảng tin. Cần mở lại app.": @"Hides suggestion cards (nudges) and Mix in the feed. Restart the app to apply.",
        @"Ẩn thẻ gợi ý hiện ra khi bạn chạm để dừng một Short.": @"Hides the suggestion card that appears when you tap to pause a Short.",
        @"Ẩn thẻ tạm dừng": @"Hide pause card",
        @"Ẩn video Short": @"Hide Short videos",
        @"Ẩn âm thanh": @"Hide sound",
        @"ẩn nút lưu Shorts %@ · tốc độ đã chọn %g\n": @"hide Shorts save button %@ · picked speed %g\n",
        @"Xong": @"Done",
        @"Tắt tự động phát": @"Disable autoplay",
        @"Không tự phát khi mở video": @"No autoplay when opening a video",
        @"Video ở trang chủ không tự phát xem trước, và khi chọn một video bất kỳ để xem thì video đó không phát ngay mà chờ bạn bấm phát. Cần mở lại app.": @"Videos on the home feed do not autoplay a preview, and when you open any video it does not start right away; it waits for you to press play. Restart the app to apply.",
        @"Tắt lặp Short ~~": @"Disable Short loop ~~",
        @"Chạm lần nữa để đặt lại": @"Tap again to reset",
        @"Khôi phục tab mặc định": @"Restore default tabs",
        @"Ẩn nhãn trả phí": @"Hide paid-promotion label",
        @"Có quảng cáo trả phí": @"Includes paid promotion",
        @"Ẩn nhãn \"Có quảng cáo trả phí\" hiện trên trình phát khi video có nội dung được tài trợ. Chỉ ẩn nhãn, không chặn nội dung của video.": @"Hides the \"Includes paid promotion\" label shown on the player when a video has sponsored content. It only hides the label; it does not block the video's content.",
        @"No premium: chặn các popup, thanh gợi ý và hộp thoại mời dùng thử hoặc mua YouTube Premium, đồng thời gỡ khỏi bảng tin các thẻ mời dùng thử hoặc mua YouTube Music Premium (không để lại khoảng trống). Khi bản build có NoYTPremium thì công tắc này bật tắt luôn cả phần đó (chặn khảo sát, mục dùng thử trong cài đặt). Cần mở lại app.": @"No premium: blocks the popups, suggestion bars and dialogs that invite you to try or buy YouTube Premium, and also removes cards inviting you to try or buy YouTube Music Premium from the feed (leaving no gap). When the build includes NoYTPremium, this switch also turns that part on and off (survey blocking, the trial entry in settings). Requires restarting the app.",
        @"Cạnh nút toàn màn hình": @"Next to the fullscreen button",
        @"Chạm lần nữa để khôi phục tab": @"Tap again to restore tabs",
        @"Đã khôi phục tab mặc định": @"Default tabs restored",
        @"Trong 4 giây": @"Within 4 seconds",
        @"Quảng cáo trả phí trong video": @"Paid promotion inside the video",
        @"Tự giới thiệu hàng, kênh": @"Plugging own products or channels",
        @"Xin thích, đăng ký, theo dõi": @"Asks to like, subscribe or follow",
        @"Đoạn mở đầu lặp lại": @"Repeated opening segment",
        @"Màn hình kết, credit": @"End cards and credits",
        @"Cảnh xem trước, tóm tắt": @"Previews and recaps",
        @"Đoạn nói trong video nhạc": @"Talking in music videos",
        @"Đoạn lan man, ít quan trọng": @"Tangents and low-value filler",
        @"Xem sau": @"Watch later",
        @"Theo YouTube": @"Follow YouTube",
        @"Tuỳ chỉnh Overlay": @"Customize overlay",
        @"Nút trên trình phát": @"Player buttons",
        @"Chọn và sắp xếp các nút AutoAC trên trình phát (tải xuống, tốc độ, PiP, hẹn giờ, phát ngoài): đặt ở hàng trên (dưới nút bánh răng) hoặc hàng dưới (cạnh nút toàn màn hình), kéo để đổi thứ tự hoặc chuyển hàng, hoặc tắt hẳn từng nút. Nhấn giữ biểu tượng Tốc độ để về tốc độ gốc. Nút tải chỉ áp dụng trong video; nút tải trong Shorts luôn bật.": @"Choose and arrange AutoAC's player buttons (download, speed, PiP, sleep timer, external player): place them in the top row (under the gear button) or the bottom row (next to the fullscreen button), drag to reorder or move between rows, or switch each one off. Long-press the Speed icon to return to the original speed. The download button only applies in videos; the download button in Shorts is always on.",
        @"Hàng trên, hàng dưới, thứ tự": @"Top row, bottom row, order",
        @"Khôi phục Overlay mặc định": @"Restore default overlay",
        @"Đã khôi phục Overlay mặc định": @"Default overlay restored",
        @"Chạm lần nữa để khôi phục Overlay": @"Tap again to restore the overlay",
        @"HÀNG TRÊN": @"TOP ROW",
        @"HÀNG DƯỚI": @"BOTTOM ROW",
        @"ĐANG TẮT": @"OFF",
        @"Kéo nút vào đây": @"Drag a button here",
        @"End": @"End",
        @"Dừng khi hết video": @"Stops when the video ends",
        @"Hết video": @"Video ended",
        @"Shorts tràn xuống thanh tab": @"Shorts fill down to the tab bar",
        @"Dock trong suốt, không dải trắng/đen": @"Transparent dock, no white/black strip",
        @"Kính lỏng thanh trên": @"Liquid glass top bar",
        @"Nút tìm kiếm, thông báo, quay lại": @"Search, notifications and back buttons",
        @"Kính lỏng bảng chọn": @"Liquid glass sheets",
        @"Bảng, menu và hộp thoại": @"Sheets, menus and dialogs",
        @"Kính lỏng trình phát": @"Liquid glass player",
        @"Nút nổi trên video": @"Floating buttons on the video",
        @"Hiện": @"Show",
        @"Ẩn": @"Hide",
        @"Không hiện trên thanh tab": @"Not shown on the tab bar",
        @"Kéo tab vào đây": @"Drag a tab here",
        @"Trên thanh tab, từ trái sang phải": @"On the tab bar, left to right",
        @"Đang hiện trên thanh tab": @"Shown on the tab bar",
        @"Đang ẩn": @"Hidden",
        @"Nhấn giữ một tab rồi kéo để đổi thứ tự hoặc chuyển giữa hai dải. Chạm một tab để chọn, rồi ẩn/hiện hoặc đổi tên ở thẻ bên dưới. Thay đổi tab có hiệu lực sau khi mở lại app.": @"Press and hold a tab, then drag it to reorder or to move it between the two strips. Tap a tab to select it, then show/hide or rename it in the card below. Tab changes take effect after restarting the app.",
        @"Không hiện": @"Hidden",
        @"Vị trí Overlay": @"Overlay position",
        @"Nhấn giữ một nút rồi kéo để đổi thứ tự hoặc sang hàng khác. Chạm một nút để chọn, rồi đặt vị trí bằng nút kính ở trên (Tất cả = cả hai hàng). Thứ tự đọc từ trái sang phải: nút cuối cùng nằm sát nút bánh răng (hàng trên) hoặc sát nút toàn màn hình (hàng dưới).": @"Press and hold a button, then drag to reorder it or move it to another row. Tap a button to select it, then set its position with the glass button above (All = both rows). Order reads left to right: the last button sits next to the gear button (top row) or the fullscreen button (bottom row).",
        @"Tất cả": @"All",
        @"Dưới": @"Bottom",
        @"Trên": @"Top",
        @"Cache: Dọn cache ngay xoá được phần cũ": @"Cache: Clean cache now removes the old part",
        @"Dữ liệu web (đăng nhập, bộ nhớ trang)": @"Web data (sign-in, page storage)",
        @"Dữ liệu của app": @"App data",
        @"Ảnh chụp trạng thái app": @"App state snapshots",
        @"Tệp của app (video đã tải, cơ sở dữ liệu)": @"App files (downloaded videos, databases)",
        @"Tệp tạm": @"Temporary files",
        @"Tổng dung lượng thư mục dữ liệu của YouTube trên máy (Documents, Library, tmp). Các mục lớn nhất:": @"Total size of YouTube's data folder on this device (Documents, Library, tmp). Largest items:",
        @"Không có mục nào từ 20 MB trở lên.": @"No item is 20 MB or larger.",
        @"Dung lượng ứng dụng": @"App storage",
        @"Mục lớn nhất trong thư mục của YouTube": @"Largest items in YouTube's folder",
        @"Tính lại": @"Recalculate",
        @"Thư mục nào đang chiếm bộ nhớ": @"Which folders use the space",
        @"Xem tổng dung lượng thư mục dữ liệu của YouTube và các mục lớn nhất (Documents, Caches, WebKit…), kèm ghi chú mục nào dọn được. Mở thẳng từ đây, không cần vào trang (i) hay bật Chẩn đoán.": @"See the total size of YouTube's data folder and its largest items (Documents, Caches, WebKit…), with notes on which can be cleaned. Opens right from here, no need to open the (i) page or turn on Diagnostics.",
        };
    });
    return table;
}

static NSString *AutoACT(NSString *vi) {
    if (AutoACUseVietnamese()) return vi;
    return AutoACBundleStrings()[vi] ?: AutoACEnglishTable()[vi] ?: vi;   // ưu tiên file .strings, thiếu thì dùng bảng trong code
}
