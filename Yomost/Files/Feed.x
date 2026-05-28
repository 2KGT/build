// Feed.x
#import "Headers.h"

// ==========================================
// 1. LOGIC ẨN SHORTS SHELF KHỎI FEED (YTUnShorts)
// ==========================================
static NSMutableArray *filteredShortsArray(NSArray *array) {
    if (!array || array.count == 0) return [NSMutableArray array];
    NSMutableArray *newArray = [array mutableCopy];
    
    NSMutableIndexSet *removeIndexes = [NSMutableIndexSet indexSet];
    
    [newArray enumerateObjectsUsingBlock:^(id sectionRenderer, NSUInteger idx, BOOL *stop) {
        // Kiểm tra an toàn cho kiểu YTIShelfRenderer
        if ([sectionRenderer isKindOfClass:NSClassFromString(@"YTIShelfRenderer")]) {
            id content = [sectionRenderer respondsToSelector:@selector(content)] ? [sectionRenderer content] : nil;
            if (content && [content respondsToSelector:@selector(horizontalListRenderer)]) {
                id horizontalListRenderer = [content horizontalListRenderer];
                if (horizontalListRenderer && [horizontalListRenderer respondsToSelector:@selector(itemsArray)]) {
                    NSMutableArray *itemsArray = [horizontalListRenderer itemsArray];
                    NSMutableIndexSet *removeItemsIndexes = [NSMutableIndexSet indexSet];
                    
                    [itemsArray enumerateObjectsUsingBlock:^(id item, NSUInteger idx2, BOOL *stop2) {
                        if ([item respondsToSelector:@selector(elementRenderer)]) {
                            id elementRenderer = [item elementRenderer];
                            NSString *description = [elementRenderer description];
                            if (description && [description containsString:@"shorts_video_cell"]) {
                                [removeItemsIndexes addIndex:idx2];
                            }
                        }
                    }];
                    if (removeItemsIndexes.count > 0) {
                        [itemsArray removeObjectsAtIndexes:removeItemsIndexes];
                    }
                }
            }
        }
        
        // Kiểm tra trực tiếp chuỗi định danh của Section
        if ([sectionRenderer isKindOfClass:NSClassFromString(@"YTIItemSectionRenderer")]) {
            NSString *description = [sectionRenderer description];
            if (description && [description containsString:@"shorts_shelf.eml"]) {
                [removeIndexes addIndex:idx];
            }
        }
    }];
    
    [newArray removeObjectsAtIndexes:removeIndexes];
    return newArray;
}

%group Shorts
%hook YTInnerTubeCollectionViewController

- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer {
    @try {
        id sectionRenderers = [self valueForKey:@"_sectionRenderers"];
        if (sectionRenderers) {
            [self setValue:filteredShortsArray(sectionRenderers) forKey:@"_sectionRenderers"];
        }
    } @catch (NSException *exception) {}
    %orig;
}

- (void)addSectionsFromArray:(id)array {
    if (array && [array isKindOfClass:[NSArray class]]) {
        %orig(filteredShortsArray(array));
    } else {
        %orig;
    }
}

%end
%end

// ==========================================
// 2. ẨN THANH DANH MỤC PHỤ (HIDE SUBBAR / CHIPS)
// ==========================================
%hook YTMySubsFilterHeaderView
- (void)setChipFilterView:(id)arg1 { 
    if (!IS_ENABLED(HideSubbar)) %orig; 
}
%end

%hook YTHeaderContentComboView
- (void)enableSubheaderBarWithView:(id)arg1 { 
    if (!IS_ENABLED(HideSubbar)) %orig; 
}
- (void)setFeedHeaderScrollMode:(int)arg1 { 
    IS_ENABLED(HideSubbar) ? %orig(0) : %orig; 
}
%end

%hook YTChipCloudCell
- (void)layoutSubviews {
    %orig;
    // Sửa lỗi gọi removeFromSuperview gây crash: Chỉ ẩn view an toàn bằng thuộc tính hidden
    if (IS_ENABLED(HideSubbar)) {
        self.hidden = YES;
        self.frame = CGRectZero;
    }
}
%end

// ==========================================
// 3. ẨN NÚT TÌM KIẾM GIỌNG NÓI & LỊCH SỬ TÌM KIẾM
// ==========================================
%hook YTSearchViewController
- (void)viewDidLoad {
    %orig;
    @try {
        if (IS_ENABLED(HideVoiceSearch)) {
            [self setValue:@(NO) forKey:@"_isVoiceSearchAllowed"];
        }
    } @catch (NSException *e) {}
}
- (void)setSuggestions:(id)arg1 { 
    if (!IS_ENABLED(HideSearchHis)) %orig; 
}
%end

%hook YTPersonalizedSuggestionsCacheProvider
- (id)activeCache { 
    return IS_ENABLED(HideSearchHis) ? nil : %orig; 
}
%end

// ==========================================
// 4. KHỞI TẠO CẤU TRÚC (CONSTRUCTOR)
// ==========================================
%ctor {
    %init;
    @try {
        if (IS_ENABLED(HideShortsShelf)) {
            %init(Shorts);
        }
    } @catch (NSException *exception) {}
}
