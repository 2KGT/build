#import <SampleTweakheaders/SampleTweakheaders.h>

// - Khởi tạo dự án mới từ lò luyện Vô Ảnh
// + Tối ưu hóa hiệu năng ban đầu

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    NSLog(@"[Vô Ảnh Phong Thần] Linh đan SampleTweak đã được kích hoạt!");
}
%end
