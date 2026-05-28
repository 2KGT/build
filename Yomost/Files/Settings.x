// Settings.x
// Thanks to the original codes from YTUHD by PoomSmart
#import "Headers.h"

#define TweakName @"Yomost"
#define LOC(x) [YomostBundle() localizedStringForKey:x value:nil table:nil]

static const NSInteger TweakSection = 'ytys'; // Đổi ID mới

static NSBundle *YomostBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:TweakName ofType:@"bundle"];
        if (tweakBundlePath)
            bundle = [NSBundle bundleWithPath:tweakBundlePath];
        else
            bundle = [NSBundle bundleWithPath:[NSString stringWithFormat:PS_ROOT_PATH_NS(@"/Library/Application Support/%@.bundle"), TweakName]];
    });
    return bundle;
}

static NSString *GetCacheSize() {
    NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *filesArray = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:cachePath error:nil];
    unsigned long long int folderSize = 0;
    for (NSString *fileName in filesArray) {
        NSString *filePath = [cachePath stringByAppendingPathComponent:fileName];
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        folderSize += [fileAttributes fileSize];
    }
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    return [formatter stringFromByteCount:folderSize];
}

#define BASIC_SWITCH(title, description, key) \
    [YTSettingsSectionItemClass switchItemWithTitle:title \
        titleDescription:description \
        accessibilityIdentifier:nil \
        switchOn:IS_ENABLED(key) \
        switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) { \
            [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:key]; \
            return YES; \
        } \
        settingItemId:0]

#define SETTINGS_HEADER \
    [YTSettingsSectionItemClass itemWithTitle:nil \
        titleDescription:LOC(@"SETTINGS") \
        accessibilityIdentifier:nil \
        detailTextBlock:nil \
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) { return NO; }]

%hook YTSettingsGroupData
- (NSArray <NSNumber *> *)orderedCategories {
    if (self.type != 1 || class_getClassMethod(objc_getClass("YTSettingsGroupData"), @selector(tweaks))) return %orig;
    NSMutableArray *mutableCategories = %orig.mutableCopy;
    [mutableCategories insertObject:@(TweakSection) atIndex:0];
    return mutableCategories.copy;
}
%end

%hook YTAppSettingsPresentationData
+ (NSArray <NSNumber *> *)settingsCategoryOrder {
    NSArray <NSNumber *> *order = %orig;
    NSUInteger insertIndex = [order indexOfObject:@(1)];
    if (insertIndex != NSNotFound) {
        NSMutableArray <NSNumber *> *mutableOrder = [order mutableCopy];
        [mutableOrder insertObject:@(TweakSection) atIndex:insertIndex + 1];
        order = mutableOrder.copy;
    }
    return order;
}
%end

%hook YTSettingsSectionItemManager
%new(v@:@)
- (void)updateYomostSectionWithEntry:(id)entry {
    NSMutableArray <YTSettingsSectionItem *> *sectionItems = [NSMutableArray array];
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);
    YTSettingsViewController *settingsViewController = [self valueForKey:@"_settingsViewControllerDelegate"];

    // 0. Section Logo
    YTSettingsSectionItem *centerytlogo = BASIC_SWITCH(LOC(@"CENTER_YT_LOGO"), LOC(@"CENTER_YT_LOGO_DESC"), CenterYTLogo);
    [sectionItems addObject:centerytlogo];

    // 1. Downloading
    YTSettingsSectionItem *downloadinggroup = [YTSettingsSectionItemClass itemWithTitle:LOC(@"DOWNLOADING") accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        NSArray <YTSettingsSectionItem *> *rows = @[SETTINGS_HEADER, BASIC_SWITCH(LOC(@"DOWNLOAD_MANAGER"), LOC(@"DOWNLOAD_MANAGER_DESC"), DownloadManager), BASIC_SWITCH(LOC(@"DOWNLOAD_SAVE_PHOTOS"), LOC(@"DOWNLOAD_SAVE_PHOTOS_DESC"), DownloadSaveToPhotos), BASIC_SWITCH(LOC(@"DOWNLOAD_DRC_AUDIO"), LOC(@"DOWNLOAD_DRC_AUDIO"), DownloadPreferDRCAudio)];
        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"DOWNLOADING") pickerSectionTitle:nil rows:rows selectedItemIndex:0 parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];
    [sectionItems addObject:downloadinggroup];

    // 2. Appearance
    YTSettingsSectionItem *appergroup = [YTSettingsSectionItemClass itemWithTitle:LOC(@"APPEARANCE") accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        NSArray <YTSettingsSectionItem *> *rows = @[SETTINGS_HEADER, BASIC_SWITCH(LOC(@"OLED_THEME"), LOC(@"OLED_THEME_DESC"), OLEDTheme), BASIC_SWITCH(LOC(@"OLED_KEYBOARD"), LOC(@"OLED_KEYBOARD_DESC"), OLEDKeyboard)];        
        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"APPEARANCE") pickerSectionTitle:nil rows:rows selectedItemIndex:0 parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];
    [sectionItems addObject:appergroup];

    // 3. Navbar
    YTSettingsSectionItem *navbargroup = [YTSettingsSectionItemClass itemWithTitle:LOC(@"NAVBAR") accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        NSArray <YTSettingsSectionItem *> *rows = @[SETTINGS_HEADER, BASIC_SWITCH(LOC(@"HIDE_YT_LOGO"), LOC(@"HIDE_YT_LOGO_DESC"), HideYTLogo), BASIC_SWITCH(LOC(@"PREMIUM_LOGO"), LOC(@"PREMIUM_LOGO_DESC"), YTPremiumLogo), BASIC_SWITCH(LOC(@"HIDE_NOTIFICATION_BUTTON"), LOC(@"HIDE_NOTIFICATION_BUTTON_DESC"), HideNoti), BASIC_SWITCH(LOC(@"HIDE_SEARCH_BUTTON"), LOC(@"HIDE_SEARCH_BUTTON_DESC"), HideSearch), BASIC_SWITCH(LOC(@"HIDE_VOICE_SEARCH_BUTTON"), LOC(@"HIDE_VOICE_SEARCH_BUTTON_DESC"), HideVoiceSearch), BASIC_SWITCH(LOC(@"HIDE_CAST_BUTTON_NAVBAR"), LOC(@"HIDE_CAST_BUTTON_NAVBAR_DESC"), HideCastButtonNav)];
        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"NAVBAR") pickerSectionTitle:nil rows:rows selectedItemIndex:0 parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];
    [sectionItems addObject:navbargroup];

    // 4. Feed
    YTSettingsSectionItem *feedgroup = [YTSettingsSectionItemClass itemWithTitle:LOC(@"FEED") accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        NSArray <YTSettingsSectionItem *> *rows = @[SETTINGS_HEADER, BASIC_SWITCH(LOC(@"HIDE_SUBBAR"), LOC(@"HIDE_SUBBAR_DESC"), HideSubbar), BASIC_SWITCH(LOC(@"HIDE_MUSIC_PLAYLISTS"), LOC(@"HIDE_MUSIC_PLAYLISTS_DESC"), HideGenMusicShelf), BASIC_SWITCH(LOC(@"HIDE_FEED_POST"), LOC(@"HIDE_FEED_POST_DESC"), HideFeedPost), BASIC_SWITCH(LOC(@"HIDE_SHORTS_SHELF"), LOC(@"HIDE_SHORTS_SHELF_DESC"), HideShortsShelf), BASIC_SWITCH(LOC(@"HIDE_SEARCH_HISTORY"), LOC(@"HIDE_SEARCH_HISTORY_DESC"), HideSearchHis), BASIC_SWITCH(LOC(@"HIDE_SUB_BUTTON"), LOC(@"HIDE_SUB_BUTTON_DESC"), HideSubButton), BASIC_SWITCH(LOC(@"HIDE_SHOP_BUTTON"), LOC(@"HIDE_SHOP_BUTTON_DESC"), HideShoppingButton), BASIC_SWITCH(LOC(@"HIDE_MEMBER_BUTTON"), LOC(@"HIDE_MEMBER_BUTTON_DESC"), HideMemberButton)];
        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"FEED") pickerSectionTitle:nil rows:rows selectedItemIndex:0 parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];
    [sectionItems addObject:feedgroup];

    // 5. Player (Tích hợp nút Tải)
    YTSettingsSectionItem *playergroup = [YTSettingsSectionItemClass itemWithTitle:LOC(@"PLAYER") accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        NSArray <YTSettingsSectionItem *> *rows = @[SETTINGS_HEADER, BASIC_SWITCH(LOC(@"DOWNLOAD_PLAYER_BUTTON"), LOC(@"DOWNLOAD_PLAYER_BUTTON_DESC"), DownloadPlayerButton), BASIC_SWITCH(LOC(@"HIDE_AUTOPLAY"), LOC(@"HIDE_AUTOPLAY_DESC"), HideAutoPlayToggle), BASIC_SWITCH(LOC(@"HIDE_CAPTIONS_BUTTON"), LOC(@"HIDE_CAPTIONS_BUTTON_DESC"), HideCaptionsButton), BASIC_SWITCH(LOC(@"HIDE_CAST_BUTTON_PLAYER"), LOC(@"HIDE_CAST_BUTTON_PLAYER_DESC"), HideCastButtonPlayer), BASIC_SWITCH(LOC(@"HIDE_PREV_BUTTON"), LOC(@"HIDE_PREV_BUTTON_DESC"), HidePrevButton), BASIC_SWITCH(LOC(@"HIDE_NEXT_BUTTON"), LOC(@"HIDE_NEXT_BUTTON_DESC"), HideNextButton), BASIC_SWITCH(LOC(@"REPLACE_PREVNEXT_BUTTONS"), LOC(@"REPLACE_PREVNEXT_BUTTONS_DESC"), ReplacePrevNextButtons), BASIC_SWITCH(LOC(@"REMOVE_DARK_OVERLAY"), LOC(@"REMOVE_DARK_OVERLAY_DESC"), RemoveDarkOverlay), BASIC_SWITCH(LOC(@"HIDE_END_SCREEN"), LOC(@"HIDE_END_SCREEN_DESC"), HideEndScreenCards), BASIC_SWITCH(LOC(@"REMOVE_AMBIANT"), LOC(@"REMOVE_AMBIANT_DESC"), RemoveAmbiant), BASIC_SWITCH(LOC(@"HIDE_SUGGESTED_VIDEO"), LOC(@"HIDE_SUGGESTED_VIDEO_DESC"), HideSuggestedVideo), BASIC_SWITCH(LOC(@"HIDE_PAID_OVERLAY"), LOC(@"HIDE_PAID_OVERLAY_DESC"), HidePaidPromoOverlay), BASIC_SWITCH(LOC(@"HIDE_WATERMARK"), LOC(@"HIDE_WATERMARK_DESC"), HideWaterMark), BASIC_SWITCH(LOC(@"GESTURES"), LOC(@"GESTURES_DESC"), GestureControls), BASIC_SWITCH(LOC(@"GESTURE_HUD"), LOC(@"GESTURE_HUD_DESC"), GestureHUD), BASIC_SWITCH(LOC(@"DISABLES_DOUBLE_TAP"), LOC(@"DISABLES_DOUBLE_TAP_DESC"), DisablesDoubleTap), BASIC_SWITCH(LOC(@"DISABLES_LONG_HOLD"), LOC(@"DISABLES_LONG_HOLD_DESC"), DisablesLongHold), BASIC_SWITCH(LOC(@"AUTO_EXIT_FULLSCREEN"), LOC(@"AUTO_EXIT_FULLSCREEN_DESC"), AutoExitFullScreen), BASIC_SWITCH(LOC(@"AUTO_DISABLES_CAPTION"), LOC(@"AUTO_DISABLES_CAPTION_DESC"), DisablesCaptions), BASIC_SWITCH(LOC(@"ALWAYS_SHOW_REMAINING"), LOC(@"ALWAYS_SHOW_REMAINING_DESC"), AlwaysShowRemaining), BASIC_SWITCH(LOC(@"HIDE_FULLSCREEN_ACTIONS"), LOC(@"HIDE_FULLSCREEN_ACTIONS_DESC"), HideFullAction), BASIC_SWITCH(LOC(@"HIDE_FULL_VID_TITLE"), LOC(@"HIDE_FULL_VID_TITLE_DESC"), HideFullvidTitle), BASIC_SWITCH(LOC(@"STOP_AUTOPLAY_VIDEO"), LOC(@"STOP_AUTOPLAY_VIDEO_DESC"), StopAutoplayVideo), BASIC_SWITCH(LOC(@"HIDE_CONTENT_WARNING"), LOC(@"HIDE_CONTENT_WARNING_DESC"), HideContentWarning), BASIC_SWITCH(LOC(@"AUTO_FULLSCREEN"), LOC(@"AUTO_FULLSCREEN_DESC"), AutoFullScreen), BASIC_SWITCH(LOC(@"PORTRAIT_FULLSCREEN"), LOC(@"PORTRAIT_FULLSCREEN_DESC"), PortFull), BASIC_SWITCH(LOC(@"OLD_QUALITY_PICKER"), LOC(@"OLD_QUALITY_PICKER_DESC"), OldQualityPicker), BASIC_SWITCH(LOC(@"EXTRA_SPEED"), LOC(@"EXTRA_SPEED_DESC"), ExtraSpeed), BASIC_SWITCH(LOC(@"DISABLE_HINTS"), LOC(@"DISABLE_HINTS_DESC"), DisableHints), BASIC_SWITCH(LOC(@"FORCE_MINIPLAYER"), LOC(@"FORCE_MINIPLAYER_DESC"), ForceMiniPlayer), BASIC_SWITCH(LOC(@"FORCE_SEEKBAR"), LOC(@"FORCE_SEEKBAR_DESC"), AlwaysShowSeekbar), BASIC_SWITCH(LOC(@"HIDE_LIKE_BUTTON"), LOC(@"HIDE_LIKE_BUTTON_DESC"), HideLikeButton), BASIC_SWITCH(LOC(@"HIDE_DISLIKE_BUTTON"), LOC(@"HIDE_DISLIKE_BUTTON_DESC"), HideDisLikeButton), BASIC_SWITCH(LOC(@"HIDE_SHARE_BUTTON"), LOC(@"HIDE_SHARE_BUTTON_DESC"), HideShareButton), BASIC_SWITCH(LOC(@"HIDE_DOWNLOAD_BUTTON"), LOC(@"HIDE_DOWNLOAD_BUTTON_DESC"), HideDownloadButton), BASIC_SWITCH(LOC(@"HIDE_CLIP_BUTTON"), LOC(@"HIDE_CLIP_BUTTON_DESC"), HideClipButton), BASIC_SWITCH(LOC(@"HIDE_REMIX_BUTTON"), LOC(@"HIDE_REMIX_BUTTON_DESC"), HideRemixButton), BASIC_SWITCH(LOC(@"HIDE_SAVE_BUTTON"), LOC(@"HIDE_SAVE_BUTTON_DESC"), HideSaveButton)];
        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"PLAYER") pickerSectionTitle:nil rows:rows selectedItemIndex:0 parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];
    [sectionItems addObject:playergroup];

    // 6. Shorts
    YTSettingsSectionItem *shortsgroup = [YTSettingsSectionItemClass itemWithTitle:LOC(@"SHORTS") accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        NSArray <YTSettingsSectionItem *> *rows = @[SETTINGS_HEADER, BASIC_SWITCH(LOC(@"HIDE_SHORTS_LIKE_BUTTON"), LOC(@"HIDE_SHORTS_LIKE_BUTTON_DESC"), HideShortsLikeButton), BASIC_SWITCH(LOC(@"HIDE_SHORTS_DISLIKE_BUTTON"), LOC(@"HIDE_SHORTS_DISLIKE_BUTTON_DESC"), HideShortsDisLikeButton), BASIC_SWITCH(LOC(@"HIDE_SHORTS_COMMENT_BUTTON"), LOC(@"HIDE_SHORTS_COMMENT_BUTTON_DESC"), HideShortsCommentButton), BASIC_SWITCH(LOC(@"HIDE_SHORTS_SHARE_BUTTON"), LOC(@"HIDE_SHORTS_SHARE_BUTTON_DESC"), HideShortsShareButton), BASIC_SWITCH(LOC(@"HIDE_SHORTS_REMIX_BUTTON"), LOC(@"HIDE_SHORTS_REMIX_BUTTON_DESC"), HideShortsRemixButton), BASIC_SWITCH(LOC(@"HIDE_METADATA_BUTTON"), LOC(@"HIDE_METADATA_BUTTON_DESC"), HideShortsMetaButton), BASIC_SWITCH(LOC(@"HIDE_SHORTS_PRODUCT"), LOC(@"HIDE_SHORTS_PRODUCT_DESC"), HideShortsProducts), BASIC_SWITCH(LOC(@"HIDE_SHORTS_RECBAR"), LOC(@"HIDE_SHORTS_RECBAR_DESC"), HideShortsRecbar), BASIC_SWITCH(LOC(@"HIDE_SHORTS_COMMIT"), LOC(@"HIDE_SHORTS_COMMIT_DESC"), HideShortsCommit), BASIC_SWITCH(LOC(@"HIDE_SHORTS_SUBSCRIPT_BUTTON"), LOC(@"HIDE_SHORTS_SUBSCRIPT_BUTTON_DESC"), HideShortsSubscriptButton), BASIC_SWITCH(LOC(@"HIDE_SHORTS_LIVE_BUTTON"), LOC(@"HIDE_SHORTS_LIVE_BUTTON_DESC"), HideShortsLiveButton), BASIC_SWITCH(LOC(@"HIDE_SHORTS_LENS_BUTTON"), LOC(@"HIDE_SHORTS_LENS_BUTTON_DESC"), HideShortsLensButton), BASIC_SWITCH(LOC(@"HIDE_SHORTS_TRENDS_BUTTON"), LOC(@"HIDE_SHORTS_TRENDS_BUTTON_DESC"), HideShortsTrendsButton), BASIC_SWITCH(LOC(@"HIDE_SHORTS_TO_VIDEO"), LOC(@"HIDE_SHORTS_TO_VIDEO_DESC"), HideShortsToVideo), BASIC_SWITCH(LOC(@"ENABLES_SHORTS_QUALITY"), LOC(@"ENABLES_SHORTS_QUALITY_DESC"), EnablesShortsQuality), BASIC_SWITCH(LOC(@"SHOW_SHORTS_SEEKBAR"), LOC(@"SHOW_SHORTS_SEEKBAR_DESC"), ShowShortsSeekbar)];
        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"SHORTS") pickerSectionTitle:nil rows:rows selectedItemIndex:0 parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];
    [sectionItems addObject:shortsgroup];

    // 7. TabBar
    YTSettingsSectionItem *tabgroup = [YTSettingsSectionItemClass itemWithTitle:LOC(@"TABBAR") accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        NSArray <YTSettingsSectionItem *> *rows = @[SETTINGS_HEADER, BASIC_SWITCH(LOC(@"HIDE_TAB_INDI"), LOC(@"HIDE_TAB_INDI_DESC"), HideTabIndi), BASIC_SWITCH(LOC(@"HIDE_TAB_LABELS"), LOC(@"HIDE_TAB_LABELS_DESC"), HideTabLabels), BASIC_SWITCH(LOC(@"HIDE_HOME_TAB"), LOC(@"HIDE_HOME_TAB_DESC"), HideHomeTab), BASIC_SWITCH(LOC(@"HIDE_SHORTS_TAB"), LOC(@"HIDE_SHORTS_TAB_DESC"), HideShortsTab), BASIC_SWITCH(LOC(@"HIDE_CREATE_BUTTON"), LOC(@"HIDE_CREATE_BUTTON_DESC"), HideCreateButton), BASIC_SWITCH(LOC(@"HIDE_SUBSCRIPT_TAB"), LOC(@"HIDE_SUBSCRIPT_TAB_DESC"), HideSubscriptTab)];
        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"TABBAR") pickerSectionTitle:nil rows:rows selectedItemIndex:0 parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];
    [sectionItems addObject:tabgroup];

    // 8. Misc
    YTSettingsSectionItem *othergroup = [YTSettingsSectionItemClass itemWithTitle:LOC(@"MISCELLANEOUS") accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        NSArray <YTSettingsSectionItem *> *rows = @[SETTINGS_HEADER, BASIC_SWITCH(LOC(@"BACKGROUND_PLAYBACK"), LOC(@"BACKGROUND_PLAYBACK_DESC"), BackgroundPlayback), BASIC_SWITCH(LOC(@"DISABLES_SHORTS_PIP"), LOC(@"DISABLES_SHORTS_PIP_DESC"), DisablesShortsPiP), BASIC_SWITCH(LOC(@"BLOCK_UPGRADE_DIALOGS"), LOC(@"BLOCK_UPGRADE_DIALOGS_DESC"), BlockUpgradeDialogs), BASIC_SWITCH(LOC(@"FIXES_SLOW_MINIPLAYER"), LOC(@"FIXES_SLOW_MINIPLAYER_DESC"), FixesSlowMiniPlayer), BASIC_SWITCH(LOC(@"HIDE_STARTUP_ANIMATIONS"), LOC(@"HIDE_STARTUP_ANIMATIONS_DESC"), HideStartupAni)];
        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"MISCELLANEOUS") pickerSectionTitle:nil rows:rows selectedItemIndex:0 parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];
    [sectionItems addObject:othergroup];

    // 9. Preferences
    YTSettingsSectionItem *perfgroup = [YTSettingsSectionItemClass itemWithTitle:LOC(@"PERFER_HEADER") accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        NSArray <YTSettingsSectionItem *> *rows = @[
            [YTSettingsSectionItemClass itemWithTitle:LOC(@"IMPORT") titleDescription:nil accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) { [[YomostPrefsManager sharedManager] importYomostSettingsFromVC:settingsViewController]; return YES; }],
            [YTSettingsSectionItemClass itemWithTitle:LOC(@"EXPORT") titleDescription:nil accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) { [[YomostPrefsManager sharedManager] exportYomostSettingsFromVC:settingsViewController]; return YES; }],
            [YTSettingsSectionItemClass itemWithTitle:LOC(@"RESTORE") titleDescription:nil accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) { [[YomostPrefsManager sharedManager] restoreYomostDefaults]; return YES; }],
            BASIC_SWITCH(LOC(@"AUTO_CLEARCACHE"), LOC(@"AUTO_CLEARCACHE_DESC"), AutoClearCache)
        ];
        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"PERFER_HEADER") pickerSectionTitle:nil rows:rows selectedItemIndex:0 parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];
    [sectionItems addObject:perfgroup];

    // 10. Version (Dưới cùng)
    YTSettingsSectionItem *tweakVersion = [YTSettingsSectionItemClass itemWithTitle:@"Yomost v1.3.1" titleDescription:nil accessibilityIdentifier:nil detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) { return NO; }];
    [sectionItems addObject:tweakVersion];

    // Áp dụng
    [settingsViewController setSectionItems:sectionItems forCategory:TweakSection title:TweakName titleDescription:nil headerHidden:NO];
}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == TweakSection) { [self updateYomostSectionWithEntry:entry]; return; }
    %orig;
}
%end
