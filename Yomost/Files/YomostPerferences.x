// YomostPerferences.x
#import "Headers.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Khắc phục lỗi trùng lặp/định nghĩa đè Macro LOC
#ifdef LOC
#undef LOC
#endif
#define LOC(x) [YomostBundle() localizedStringForKey:x value:nil table:nil]

%hook YomostPrefsManager

- (void)presentImportPickerInViewController:(UIViewController *)vc {
    if (!vc) return;
    
    UIDocumentPickerViewController *picker = nil;

    @try {
        // Sử dụng UTType hiện đại của iOS 14+ để tránh lỗi phân tích cú pháp chuỗi
        if (@available(iOS 14.0, *)) {
            Class UTTypeClass = NSClassFromString(@"UTType");
            if (UTTypeClass && [UTTypeClass respondsToSelector:@selector(typeWithIdentifier:)]) {
                id plistType = [UTTypeClass performSelector:@selector(typeWithIdentifier:) withObject:@"com.apple.property-list"];
                id dataType = [UTTypeClass performSelector:@selector(typeWithIdentifier:) withObject:@"public.data"];
                
                NSMutableArray *contentTypes = [NSMutableArray array];
                if (plistType) [contentTypes addObject:plistType];
                if (dataType) [contentTypes addObject:dataType];
                
                picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes asCopy:YES];
            }
        }
        
        // Phương án dự phòng cho iOS thấp hơn
        if (!picker) {
            NSArray *types = @[@"com.apple.property-list", @"public.data"];
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:types inMode:UIDocumentPickerModeImport];
            #pragma clang diagnostic pop
        }

        picker.delegate = (id<UIDocumentPickerDelegate>)self;
        picker.modalPresentationStyle = UIModalPresentationFormSheet;
        
        // SỬA LỖI CRASH IPAD: Cấu hình Popover an toàn tuyệt đối
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            picker.modalPresentationStyle = UIModalPresentationPopover;
            UIPopoverPresentationController *popover = picker.popoverPresentationController;
            if (popover) {
                popover.sourceView = vc.view;
                popover.sourceRect = CGRectMake(vc.view.bounds.size.width / 2, vc.view.bounds.size.height / 2, 1, 1);
                popover.permittedArrowDirections = 0; // Ẩn mũi tên chỉ hướng
            }
        }

        // Gọi hàm cấu hình tùy biến nếu có sẵn trong hệ thống
        if ([self respondsToSelector:@selector(configurePopoverForPicker:inViewController:)]) {
            [self configurePopoverForPicker:picker inViewController:vc];
        }
        
        // Thực thi hiển thị trên luồng chính (Main Thread Safe)
        dispatch_async(dispatch_get_main_queue(), ^{
            [vc presentViewController:picker animated:YES completion:nil];
        });

    } @catch (NSException *e) {}
}

- (void)presentExportPickerForURL:(NSURL *)fileURL inViewController:(UIViewController *)vc {
    if (!fileURL || !vc) return;
    
    UIDocumentPickerViewController *picker = nil;

    @try {
        if (@available(iOS 14.0, *)) {
            picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[fileURL] asCopy:YES];
        } else {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            picker = [[UIDocumentPickerViewController alloc] initWithURL:fileURL inMode:UIDocumentPickerModeExportToService];
            #pragma clang diagnostic pop
        }

        picker.delegate = (id<UIDocumentPickerDelegate>)self;
        picker.modalPresentationStyle = UIModalPresentationFormSheet;
        
        // SỬA LỖI CRASH IPAD: Cấu hình Popover an toàn tuyệt đối khi Export
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            picker.modalPresentationStyle = UIModalPresentationPopover;
            UIPopoverPresentationController *popover = picker.popoverPresentationController;
            if (popover) {
                popover.sourceView = vc.view;
                popover.sourceRect = CGRectMake(vc.view.bounds.size.width / 2, vc.view.bounds.size.height / 2, 1, 1);
                popover.permittedArrowDirections = 0;
            }
        }

        if ([self respondsToSelector:@selector(configurePopoverForPicker:inViewController:)]) {
            [self configurePopoverForPicker:picker inViewController:vc];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [vc presentViewController:picker animated:YES completion:nil];
        });

    } @catch (NSException *e) {}
}

%end
