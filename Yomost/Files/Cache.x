// cache.x
#import "Headers.h"

// Định nghĩa Interface để tránh cảnh báo biên dịch (Compiler Warnings)
@interface YTAppDelegate (YomostCache)
- (void)YomostSmartClearCache;
- (uint64_t)getFolderSizeAtPath:(NSString *)folderPath;
- (NSString *)getFriendlyCacheSize;
- (void)manualClearCacheWithCompletion:(void (^)(NSString *newSize))completion;
@end

%hook YTAppDelegate

// ==========================================
// 1. TỰ ĐỘNG XÓA CACHE KHI KHỞI ĐỘNG APP
// ==========================================
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;
    
    // Đảm bảo bọc kiểm tra an toàn macro tránh lỗi thiết lập trống
    @try {
        if (IS_ENABLED(AutoClearCache)) {
            // Sử dụng hàng đợi BACKGROUND (ưu tiên thấp) giúp máy tập trung load UI mượt mà, không bị nóng/lag lúc mở app
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                [self YomostSmartClearCache];
            });
        }
    } @catch (NSException *exception) {}
    
    return result;
}

// ==========================================
// 2. LOGIC DỌN DẸP THÔNG MINH (SMART CLEAN)
// ==========================================
%new
- (void)YomostSmartClearCache {
    // Sử dụng @autoreleasepool để giải phóng bộ nhớ đệm ngay lập tức trong vòng lặp luồng nền, tránh tràn RAM
    @autoreleasepool {
        NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *tmpPath = NSTemporaryDirectory();
        NSFileManager *fileManager = [[NSFileManager alloc] init]; // Dùng instance riêng cho thread-safe
        
        NSArray *pathsToClean = @[cachePath, tmpPath];
        
        // DANH SÁCH TRẮNG: Mở rộng bảo vệ các tệp cấu hình cốt lõi của YouTube và Tweak
        NSSet *whiteList = [NSSet setWithObjects:@"Snapshots", @"Preferences", @"WebKit", @"com.apple.metal", @"CloudKit", nil];

        for (NSString *basePath in pathsToClean) {
            if (!basePath) continue;
            NSError *error = nil;
            NSArray *contents = [fileManager contentsOfDirectoryAtPath:basePath error:&error];
            if (error || !contents) continue;

            for (NSString *file in contents) {
                if ([whiteList containsObject:file]) continue;
                
                // Tránh xóa file tệp cấu hình .plist lưu cài đặt tweak của bạn
                if ([file hasSuffix:@".plist"]) continue;
                
                NSString *fullPath = [basePath stringByAppendingPathComponent:file];
                
                // Kiểm tra an toàn trước khi xóa
                if ([fileManager fileExistsAtPath:fullPath]) {
                    @try {
                        [fileManager removeItemAtPath:fullPath error:nil];
                    } @catch (NSException *e) {}
                }
            }
        }
    }
}

// ==========================================
// 3. TÍNH TOÁN DUNG LƯỢNG ĐỂ HIỂN THỊ LÊN UI
// ==========================================
%new
- (uint64_t)getFolderSizeAtPath:(NSString *)folderPath {
    if (!folderPath) return 0;
    
    __block uint64_t totalSize = 0;
    
    @autoreleasepool {
        NSFileManager *fileManager = [[NSFileManager alloc] init]; // Thread-safe instance
        // Thay thế enumeratorAtPath bằng phương thức hệ thống an toàn, tránh lỗi xung đột tệp tin đang ghi ngầm
        NSURL *diskURL = [NSURL fileURLWithPath:folderPath];
        
        NSError *error = nil;
        NSArray *allFiles = [fileManager subpathsOfDirectoryAtPath:folderPath error:&error];
        
        if (!error && allFiles) {
            for (NSString *fileName in allFiles) {
                NSString *filePath = [folderPath stringByAppendingPathComponent:fileName];
                @try {
                    NSDictionary *attributes = [fileManager attributesOfItemAtPath:filePath error:nil];
                    if (attributes) {
                        totalSize += [attributes fileSize];
                    }
                } @catch (NSException *e) {}
            }
        }
    }
    return totalSize;
}

// Trả về chuỗi dung lượng định dạng chuẩn Apple (Ví dụ: "124.5 MB" hoặc "0 KB")
%new
- (NSString *)getFriendlyCacheSize {
    NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *tmpPath = NSTemporaryDirectory();
    
    uint64_t totalBytes = [self getFolderSizeAtPath:cachePath] + [self getFolderSizeAtPath:tmpPath];
    
    // Định dạng Byte sang KB/MB/GB tự động một cách trực quan
    return [NSByteCountFormatter stringFromByteCount:totalBytes countStyle:NSByteCountFormatterCountStyleFile];
}

// ==========================================
// 4. HÀM HỖ TRỢ XÓA THỦ CÔNG TỪ UI SETTINGS
// ==========================================
%new
- (void)manualClearCacheWithCompletion:(void (^)(NSString *newSize))completion {
    // Chạy ngầm tác vụ dọn dẹp để không gây đơ màn hình (Block UI)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self YomostSmartClearCache];
        
        // Tính toán lại dung lượng mới sau khi xóa
        NSString *updatedSize = [self getFriendlyCacheSize];
        
        // Trả kết quả về Luồng chính (Main Thread) để cập nhật giao diện và hiển thị thông báo thành công
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(updatedSize);
            }
        });
    });
}

%end
