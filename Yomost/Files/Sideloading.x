// sideloading.x
#import "Headers.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <Security/Security.h>

#define YT_BUNDLE_ID @"com.google.ios.youtube"
#define YT_NAME @"YouTube"

@interface SSOConfiguration : NSObject
@end

%group gSideloading

// Keychain patching - Đã sửa lỗi rò rỉ bộ nhớ CoreFoundation (Memory Leak)
static NSString *accessGroupID() {
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
                           (__bridge NSString *)kSecClassGenericPassword, (__bridge NSString *)kSecClass,
                           @"bundleSeedID", kSecAttrAccount,
                           @"", kSecAttrService,
                           (id)kCFBooleanTrue, kSecReturnAttributes,
                           nil];
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound) {
        status = SecItemAdd((__bridge CFDictionaryRef)query, &result);
    }
    
    if (status != errSecSuccess || result == NULL) {
        if (result) CFRelease(result);
        return nil;
    }
    
    // Sử dụng __bridge_transfer để bàn giao quyền quản lý bộ nhớ cho ARC tự động giải phóng
    NSDictionary *resultDict = (__bridge_transfer NSDictionary *)result;
    NSString *accessGroup = [resultDict objectForKey:(__bridge NSString *)kSecAttrAccessGroup];

    return accessGroup;
}

// Hàm isSelf cải tiến: Kiểm tra chính xác thực thể thực thi chính của YouTube, chống nhận diện sai
BOOL isSelf() {
    NSArray *address = [NSThread callStackReturnAddresses];
    if (address.count < 3) return NO;
    
    Dl_info info = {0};
    if (dladdr((void *)[address[2] longLongValue], &info) == 0) return NO;
    if (info.dli_fname == NULL) return NO;
    
    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    
    // Kiểm tra nghiêm ngặt xem luồng gọi có nguồn gốc từ chính file thực thi chính của YouTube hay không
    return [path containsString:@"YouTube.app/YouTube"];
}

// IAmYouTube
%hook YTVersionUtils
+ (NSString *)appName { return YT_NAME; }
+ (NSString *)appID { return YT_BUNDLE_ID; }
%end

%hook GCKBUtils
+ (NSString *)appIdentifier { return YT_BUNDLE_ID; }
%end

%hook GPCDeviceInfo
+ (NSString *)bundleId { return YT_BUNDLE_ID; }
%end

%hook OGLBundle
+ (NSString *)shortAppName { return YT_NAME; }
%end

%hook GVROverlayView
+ (NSString *)appName { return YT_NAME; }
%end

%hook OGLPhenotypeFlagServiceImpl
- (NSString *)bundleId { return YT_BUNDLE_ID; }
%end

%hook APMAEU
+ (BOOL)isFAS { return YES; }
%end

%hook GULAppEnvironmentUtil
+ (BOOL)isFromAppStore { return YES; }
%end

%hook SSOConfiguration
- (id)initWithClientID:(id)clientID supportedAccountServices:(id)supportedAccountServices {
    self = %orig;
    if (self) {
        @try {
            [self setValue:YT_NAME forKey:@"_shortAppName"];
            [self setValue:YT_BUNDLE_ID forKey:@"_applicationIdentifier"];
        } @catch (NSException *e) {}
    }
    return self;
}
%end

%hook NSBundle
- (NSString *)bundleIdentifier {
    return isSelf() ? YT_BUNDLE_ID : %orig;
}

- (NSDictionary *)infoDictionary {
    NSDictionary *dict = %orig;
    if (!isSelf() || !dict)
        return %orig;
        
    NSMutableDictionary *info = [dict mutableCopy];
    if (info[@"CFBundleIdentifier"]) info[@"CFBundleIdentifier"] = YT_BUNDLE_ID;
    if (info[@"CFBundleDisplayName"]) info[@"CFBundleDisplayName"] = YT_NAME;
    if (info[@"CFBundleName"]) info[@"CFBundleName"] = YT_NAME;
    return info;
}

- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (!isSelf())
        return %orig;
    if ([key isEqualToString:@"CFBundleIdentifier"])
        return YT_BUNDLE_ID;
    if ([key isEqualToString:@"CFBundleDisplayName"] || [key isEqualToString:@"CFBundleName"])
        return YT_NAME;
    return %orig;
}
%end

// Fix login cho YouTube bản mới
%hook SSOKeychainHelper
+ (NSString *)accessGroup { return accessGroupID(); }
+ (NSString *)sharedAccessGroup { return accessGroupID(); }
%end

// Fix login cho YouTube bản cũ
%hook SSOKeychainCore
+ (NSString *)accessGroup { return accessGroupID(); }
+ (NSString *)sharedAccessGroup { return accessGroupID(); }
%end

// Bẻ hướng thư mục App Group về thư mục Documents an toàn trong Sandbox của App lậu
%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    if (groupIdentifier != nil) {
        @try {
            NSArray *paths = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
            NSURL *documentsURL = [paths lastObject];
            NSURL *appGroupURL = [documentsURL URLByAppendingPathComponent:@"AppGroup"];
            
            // Tự động tạo thư mục giả lập nếu chưa tồn tại để tránh lỗi ghi file thất bại
            [[NSFileManager defaultManager] createDirectoryAtURL:appGroupURL withIntermediateDirectories:YES attributes:nil error:nil];
            return appGroupURL;
        } @catch (NSException *e) {}
    }
    return %orig(groupIdentifier);
}
%end
%end

%ctor {
    // SỬA LỖI ĐỆ QUY CHÍ MẠNG: Dùng NSHomeDirectory() thuần C, tuyệt đối không gọi NSBundle ở đây
    @try {
        NSString *homePath = NSHomeDirectory();
        if (homePath && [homePath containsString:@"/Containers/Data/Application/"]) {
            // Chỉ kích hoạt bộ vá lỗi đăng nhập nếu phát hiện môi trường Sideload/Chạy độc lập
            %init(gSideloading);
        }
    } @catch (NSException *e) {}
}
