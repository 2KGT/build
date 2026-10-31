// Player.x
#import "Headers.h"

extern void YomostDownloadSetCurrentPlayer(id player);

float playbackRate = 1.0;
static NSString *lastFormattedEndTime = nil; // Biến đệm tránh lặp vô hạn layout

// ==========================================
// THÊM THỜI GIAN KẾT THÚC ƯỚC TÍNH (ĐÃ TỐI ƯU & MỞ KHÓA)
// ==========================================
static void YomostAddEndTime(YTPlayerViewController *self, id video, id time) {
    if (!IS_ENABLED(ShowExtraTimeRemaining) || !self || !video || !time) return;

    @try {
        if (![video respondsToSelector:@selector(totalMediaTime)] || ![time respondsToSelector:@selector(time)]) return;
        
        CGFloat rate = playbackRate != 0 ? playbackRate : 1.0;
        NSTimeInterval remainingTime = (lround([video totalMediaTime]) - lround([time time])) / rate;

        // Tính thời gian kết thúc dựa trên thời gian thực + thời gian còn lại của video
        NSDate *estimatedEndTime = [NSDate dateWithTimeIntervalSinceNow:remainingTime];

        static NSDateFormatter *dateFormatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            dateFormatter = [[NSDateFormatter alloc] init];
            [dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
            [dateFormatter setDateFormat:@"HH:mm"];
        });

        NSString *formattedEndTime = [dateFormatter stringFromDate:estimatedEndTime];
        
        // Kiểm tra an toàn view tránh lỗi ép sai kiểu class
        if (![self respondsToSelector:@selector(view)]) return;
        UIView *playerView = self.view;
        if (!playerView || ![playerView respondsToSelector:@selector(overlayView)]) return;
        
        id overlayView = [playerView performSelector:@selector(overlayView)];
        if (!overlayView || ![overlayView isKindOfClass:NSClassFromString(@"YTMainAppVideoPlayerOverlayView")]) return;

        id playerBar = [overlayView respondsToSelector:@selector(playerBar)] ? [overlayView playerBar] : nil;
        if (!playerBar) return;
        
        if ([playerBar respondsToSelector:@selector(setEndTimeString:)]) {
            [playerBar setEndTimeString:formattedEndTime];
        }

        if ([playerBar respondsToSelector:@selector(durationLabel)]) {
            id durationLabel = [playerBar durationLabel];
            if (durationLabel && [durationLabel respondsToSelector:@selector(text)] && [durationLabel respondsToSelector:@selector(setText:)]) {
                NSString *currentText = [durationLabel text];
                
                // Chỉ cập nhật khi chuỗi thời gian thực sự thay đổi (Chống nghẽn Infinite Layout Loop)
                if (currentText && ![formattedEndTime isEqualToString:lastFormattedEndTime]) {
                    lastFormattedEndTime = formattedEndTime;
                    
                    // Cắt bỏ phần đuôi cũ nếu đã từng thêm vào trước đó
                    NSRange range = [currentText rangeOfString:@" • "];
                    NSString *baseText = (range.location != NSNotFound) ? [currentText substringToIndex:range.location] : currentText;
                    
                    [durationLabel setText:[baseText stringByAppendingFormat:@" • %@", formattedEndTime]];
                    if ([durationLabel respondsToSelector:@selector(sizeToFit)]) {
                        [durationLabel sizeToFit];
                    }
                }
            }
        }
    } @catch (NSException *e) {}
}

// ==========================================
// HOOKS GIAO DIỆN ĐIỀU KHIỂN & PHỤ ĐỀ
// ==========================================
%hook YTMainAppControlsOverlayView
- (void)setAutoplaySwitchButtonRenderer:(id)arg1 { if (!IS_ENABLED(HideAutoPlayToggle)) %orig; }
- (void)setClosedCaptionsOrSubtitlesButtonAvailable:(BOOL)arg1 { if (!IS_ENABLED(HideCaptionsButton)) %orig; }
- (void)setPreviousButtonHidden:(BOOL)arg { %orig(IS_ENABLED(HidePrevButton) ? YES : arg); }
- (void)setNextButtonHidden:(BOOL)arg { %orig(IS_ENABLED(HideNextButton) ? YES : arg); }
- (BOOL)titleViewHidden { return IS_ENABLED(HideFullvidTitle) ? YES : %orig; }
%end

%hook YTAutonavEndscreenController
- (void)showEndscreen { if (!IS_ENABLED(HideSuggestedVideo)) %orig; }
- (void)showEndscreenControlsInPlayerBar:(BOOL)arg { %orig(IS_ENABLED(HideSuggestedVideo) ? NO : arg); }
%end

%hook YTSettings
- (BOOL)isAutoplayEnabled { return IS_ENABLED(HideAutoPlayToggle) ? NO : %orig; }
%end

%hook YTSettingsImpl
- (BOOL)isAutoplayEnabled { return IS_ENABLED(HideAutoPlayToggle) ? NO : %orig; }
%end

// ==========================================
// HOOKS LỚP PHỦ VIDEO (OVERLAY)
// ==========================================
%hook YTMainAppVideoPlayerOverlayView
- (void)setBackgroundVisible:(BOOL)arg1 isGradientBackground:(BOOL)arg2 { %orig(IS_ENABLED(RemoveDarkOverlay) ? NO : arg1, arg2); }
- (BOOL)isWatermarkEnabled { return IS_ENABLED(HideWaterMark) ? NO : %orig; }
- (void)setWatermarkEnabled:(BOOL)arg { %orig(IS_ENABLED(HideWaterMark) ? NO : arg); }
- (void)layoutSubviews {
    %orig;
    @try {
        if (IS_ENABLED(HideCastButtonPlayer) && [self respondsToSelector:@selector(playbackRouteButton)]) {
            [[self valueForKey:@"playbackRouteButton"] setHidden:YES];
        }
    } @catch (NSException *e) {}
}
- (BOOL)isFullscreenActionsVisible { return IS_ENABLED(HideFullAction) ? NO : %orig; }
%end

%hook YTCreatorEndscreenView
- (void)setHidden:(BOOL)arg1 { %orig(IS_ENABLED(HideEndScreenCards) ? YES : arg1); }
- (void)setHoverCardHidden:(BOOL)arg { %orig(IS_ENABLED(HideEndScreenCards) ? YES : arg); }
- (void)setHoverCardRenderer:(id)arg { if (!IS_ENABLED(HideEndScreenCards)) %orig; }
%end

%hook YTMainAppVideoPlayerOverlayViewController
- (BOOL)allowDoubleTapToSeekGestureRecognizer { return IS_ENABLED(DisablesDoubleTap) ? NO : %orig; }
- (BOOL)allowLongPressGestureRecognizerInView:(id)arg { return IS_ENABLED(DisablesLongHold) ? NO : %orig; }
%end

// Chặn quảng cáo hiển thị được tài trợ
%group PaidPromoOverlay
%hook YTMainAppVideoPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data {}
- (void)playerOverlayProvider:(id)provider didInsertPlayerOverlay:(id)overlay {
    if (overlay && [overlay respondsToSelector:@selector(overlayIdentifier)]) {
        if ([[overlay overlayIdentifier] isEqualToString:@"player_overlay_paid_content"]) return;
    }
    %orig;
}
%end

%hook YTInlineMutedPlaybackPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data {}
%end
%end

%hook YTAnnotationsViewController
- (void)loadFeaturedChannelWatermark { if (!IS_ENABLED(HideWaterMark)) %orig; }
%end

%hook YTWatchFlowController
- (BOOL)shouldExitFullScreenOnFinish { return IS_ENABLED(AutoExitFullScreen) ? YES : %orig; }
%end

// Tùy biến hiển thị thời gian còn lại
%hook YTInlinePlayerBarContainerView
- (void)setShouldDisplayTimeRemaining:(BOOL)arg1 { 
    if (IS_ENABLED(DisablesShowRemaining)) {
        %orig(NO);
        return;
    }
    %orig(IS_ENABLED(AlwaysShowRemaining) ? YES : arg1);
}
- (void)setPlayerBarAlpha:(CGFloat)alpha { %orig(IS_ENABLED(AlwaysShowSeekbar) ? 1.0 : alpha); }
%end

%hook YTPlayerBarController
- (void)setActiveSingleVideo:(id)arg1 {
    %orig;
    if (IS_ENABLED(AlwaysShowRemaining) && !IS_ENABLED(DisablesShowRemaining)) {
        if ([self respondsToSelector:@selector(playerBar)]) {
            id playerBar = [self playerBar];
            if (playerBar && [playerBar respondsToSelector:@selector(setShouldDisplayTimeRemaining:)]) {
                [playerBar setShouldDisplayTimeRemaining:YES];
            }
        }
    }
}
%end

%hook YTFullscreenActionsView
- (CGSize)sizeThatFits:(CGSize)size { return IS_ENABLED(HideFullAction) ? CGSizeMake(1, 35) : %orig; }
%end

// Sửa lỗi trả về nil trong hàm init của YTCinematicContainerView gây crash sập nguồn
%hook YTCinematicContainerView
- (void)layoutSubviews {
    %orig;
    if (IS_ENABLED(RemoveAmbiant)) {
        self.hidden = YES;
        self.frame = CGRectZero;
    }
}
- (void)loadWithModel:(id)arg { if (!IS_ENABLED(RemoveAmbiant)) %orig; }
%end

%hook YTPlaybackConfig
- (void)setStartPlayback:(BOOL)arg1 { %orig(IS_ENABLED(StopAutoplayVideo) ? NO : arg1); }
%end

// Tự động bỏ qua cảnh báo nội dung nhạy cảm
%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert { IS_ENABLED(HideContentWarning) ? [self confirmAlertDidPressConfirm] : %orig; }
%end

%hook YTPlayabilityResolutionUserActionUIControllerImpl
- (void)showConfirmAlert { IS_ENABLED(HideContentWarning) ? [self confirmAlertDidPressConfirm] : %orig; }
%end

%hook YTWatchViewController
- (unsigned long long)allowedFullScreenOrientations { return IS_ENABLED(PortFull) ? UIInterfaceOrientationMaskAllButUpsideDown : %orig; }
%end

// Thay nút Next/Prev bằng nút Tua tiến/Tua lùi nhanh
%hook YTColdConfig
- (BOOL)replaceNextPaddleWithFastForwardButtonForSingletonVods { return IS_ENABLED(ReplacePrevNextButtons) ? YES : %orig; }
- (BOOL)replacePreviousPaddleWithRewindButtonForSingletonVods { return IS_ENABLED(ReplacePrevNextButtons) ? YES : %orig; }
%end

%group ForceMiniPlayer
%hook YTIMiniplayerRenderer
%new - (BOOL)hasMinimizedEndpoint { return NO; }
%new - (BOOL)hasPlaybackMode { return NO; }
%end
%end

// ==========================================
// TỐC ĐỘ PHÁT ULTRA SPEED lên tới 10X
// ==========================================
%group Speed
#define itemCount 13

%hook YTMenuController
- (NSMutableArray <id> *)actionsForRenderers:(NSMutableArray <id> *)renderers fromView:(UIView *)fromView entry:(id)entry shouldLogItems:(BOOL)shouldLogItems firstResponder:(id)firstResponder {
    if (!renderers || renderers.count == 0) return %orig;
    
    NSUInteger index = [renderers indexOfObjectPassingTest:^BOOL(id renderer, NSUInteger idx, BOOL *stop) {
        @try {
            id elementRenderer = [renderer respondsToSelector:@selector(valueForKey:)] ? [renderer valueForKey:@"elementRenderer"] : nil;
            id extension = elementRenderer ? [elementRenderer valueForKey:@"compatibilityOptions"] : nil;
            NSString *menuItemIdentifier = extension ? [extension valueForKey:@"menuItemIdentifier"] : nil;
            BOOL isVideoSpeed = [menuItemIdentifier isEqualToString:@"menu_item_playback_speed"];
            if (isVideoSpeed) *stop = YES;
            return isVideoSpeed;
        } @catch (NSException *e) { return NO; }
    }];
    
    NSMutableArray <id> *actions = %orig;
    if (index != NSNotFound && index < actions.count) {
        @try {
            id action = actions[index];
            [action setValue:^{ [firstResponder didPressVarispeed:fromView]; } forKey:@"handler"];
            UIView *elementView = [action valueForKey:@"button"];
            [[elementView valueForKey:@"_elementView"] setUserInteractionEnabled:NO];
        } @catch (NSException *e) {}
    }
    return actions;
}
%end

%hook YTVarispeedSwitchController
- (id)init {
    self = %orig;
    if (self) {
        float speeds[] = {0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 5.0, 7.5, 10.0};
        id options[itemCount];
        Class OptionClass = %c(YTVarispeedSwitchControllerOption);
        for (int i = 0; i < itemCount; ++i) {
            options[i] = [[OptionClass alloc] initWithTitle:[NSString stringWithFormat:@"%.2fx", speeds[i]] rate:speeds[i]];
        }
        [self setValue:[NSArray arrayWithObjects:options count:itemCount] forKey:@"_options"];
    }
    return self;
}
%end

%hook YTVarispeedSwitchControllerImpl
- (id)init {
    self = %orig;
    if (self) {
        float speeds[] = {0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 5.0, 7.5, 10.0};
        id options[itemCount];
        Class OptionClass = %c(YTVarispeedSwitchControllerOption);
        for (int i = 0; i < itemCount; ++i) {
            options[i] = [[OptionClass alloc] initWithTitle:[NSString stringWithFormat:@"%.2fx", speeds[i]] rate:speeds[i]];
        }
        [self setValue:[NSArray arrayWithObjects:options count:itemCount] forKey:@"_options"];
    }
    return self;
}
%end

%hook YIPlayerHotConfig
%new(f@:) - (float)maximumPlaybackRate { return 10.0; }
%end

%hook YTIGranularVariableSpeedConfig
%new(d@:) - (int)maximumPlaybackRate { return 10.0 * 100; }
%end
%end

// Chặn thông báo/hướng dẫn tương tác (Hints) từ YouTube
%hook YTSettings
- (BOOL)areHintsDisabled { return IS_ENABLED(DisableHints) ? YES : %orig; }
- (void)setHintsDisabled:(BOOL)arg1 { %orig(IS_ENABLED(DisableHints) ? YES : arg1); }
%end

%hook YTSettingsImpl
- (BOOL)areHintsDisabled { return IS_ENABLED(DisableHints) ? YES : %orig; }
- (void)setHintsDisabled:(BOOL)arg1 { %orig(IS_ENABLED(DisableHints) ? YES : arg1); }
%end

%hook YTUserDefaults
- (BOOL)areHintsDisabled { return IS_ENABLED(DisableHints) ? YES : %orig; }
- (void)setHintsDisabled:(BOOL)arg1 { %orig(IS_ENABLED(DisableHints) ? YES : arg1); }
%end

// TRÌNH ĐIỀU KHIỂN VIDEO CHÍNH
%hook YTPlayerViewController
%property (nonatomic, retain) UIPanGestureRecognizer *YomostPanGesture;
%property (nonatomic, retain) UILabel *YomostGestureHUD;

- (void)loadWithPlayerTransition:(id)arg1 playbackConfig:(id)arg2 {
    %orig;
    YomostDownloadSetCurrentPlayer(self);
    if (IS_ENABLED(AutoFullScreen)) [self performSelector:@selector(YomostAutoFullscreen) withObject:nil afterDelay:0.75];
    if (IS_ENABLED(DisablesCaptions)) [self performSelector:@selector(YomostTurnOffCaptions) withObject:nil afterDelay:1.0];
}

- (void)prepareToLoadWithPlayerTransition:(id)arg1 expectedLayout:(id)arg2 {
    %orig;
    YomostDownloadSetCurrentPlayer(self);
    if (IS_ENABLED(AutoFullScreen)) [self performSelector:@selector(YomostAutoFullscreen) withObject:nil afterDelay:0.75];
    if (IS_ENABLED(DisablesCaptions)) [self performSelector:@selector(YomostTurnOffCaptions) withObject:nil afterDelay:1.0];
}

%new
- (void)YomostTurnOffCaptions {
    @try {
        if (self.view.superview && [self.view.superview isKindOfClass:NSClassFromString(@"YTWatchView")]) {
            if ([self respondsToSelector:@selector(setActiveCaptionTrack:source:)]) {
                [self setActiveCaptionTrack:nil source:0];
            }
        }
    } @catch (NSException *e) {}
}

%new
- (void)YomostAutoFullscreen {
    @try {
        id watchController = [self valueForKey:@"_UIDelegate"];
        if (watchController && [watchController respondsToSelector:@selector(showFullScreen)]) {
            [watchController showFullScreen];
        }
    } @catch (NSException *e) {}
}

- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    YomostAddEndTime(self, video, time);
}

- (void)potentiallyMutatedSingleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    YomostAddEndTime(self, video, time);
}

- (void)setPlaybackRate:(float)rate {
    playbackRate = rate;
    %orig;
}
%end

// Giao diện chọn chất lượng video nâng cao cũ
%group OldVideoQuality
%hook YTIMediaQualitySettingsHotConfig
%new(B@:) - (BOOL)enableQuickMenuVideoQualitySettings { return NO; }
%end

%hook YTVideoQualitySwitchOriginalController
%property (retain, nonatomic) id redesignedController;
- (void)setUserSelectableFormats:(NSArray *)formats {
    @try {
        if (self.redesignedController == nil) {
            self.redesignedController = [[%c(YTVideoQualitySwitchRedesignedController) alloc] initWithServiceRegistryScope:nil parentResponder:nil];
        }
        [self.redesignedController setValue:[self valueForKey:@"_video"] forKey:@"_video"];
        NSArray *newFormats = [self.redesignedController respondsToSelector:@selector(addRestrictedFormats:)] ? [self.redesignedController addRestrictedFormats:formats] : formats;
        %orig(newFormats);
    } @catch (NSException *e) {
        %orig;
    }
}
- (void)dealloc {
    self.redesignedController = nil;
    %orig;
}
%end

%hook YTMenuController
- (NSMutableArray <id> *)actionsForRenderers:(NSMutableArray <id> *)renderers fromView:(UIView *)fromView entry:(id)entry shouldLogItems:(BOOL)shouldLogItems firstResponder:(id)firstResponder {
    if (!renderers || renderers.count == 0) return %orig;
    
    NSUInteger index = [renderers indexOfObjectPassingTest:^BOOL(id renderer, NSUInteger idx, BOOL *stop) {
        @try {
            id elementRenderer = [renderer respondsToSelector:@selector(valueForKey:)] ? [renderer valueForKey:@"elementRenderer"] : nil;
            id extension = elementRenderer ? [elementRenderer valueForKey:@"compatibilityOptions"] : nil;
            NSString *menuItemIdentifier = extension ? [extension valueForKey:@"menuItemIdentifier"] : nil;
            BOOL isVideoQuality = [menuItemIdentifier isEqualToString:@"menu_item_video_quality"];
            if (isVideoQuality) *stop = YES;
            return isVideoQuality;
        } @catch (NSException *e) { return NO; }
    }];
    
    NSMutableArray <id> *actions = %orig;
    if (index != NSNotFound && index < actions.count) {
        @try {
            id action = actions[index];
            [action setValue:^{ [firstResponder didPressVideoQuality:fromView]; } forKey:@"handler"];
            UIView *elementView = [action valueForKey:@"button"];
            [[elementView valueForKey:@"_elementView"] setUserInteractionEnabled:NO];
        } @catch (NSException *e) {}
    }
    return actions;
}
%end
%end

// ==========================================
// CỬ CHỈ ĐIỀU KHIỂN (VUỐT ĐỘ SÁNG / ÂM LƯỢNG / TỐC ĐỘ)
// ==========================================
%group Gestures
%hook YTWatchLayerViewController
- (void)watchController:(id)watchController didSetPlayerViewController:(YTPlayerViewController *)playerViewController {
    %orig;
    if (playerViewController && [playerViewController respondsToSelector:@selector(playerView)]) {
        @try {
            UIView *pView = [playerViewController playerView];
            if (pView && !playerViewController.YomostPanGesture) {
                playerViewController.YomostPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:playerViewController action:@selector(YomostHandlePanGesture:)];
                playerViewController.YomostPanGesture.delegate = playerViewController;
                [pView addGestureRecognizer:playerViewController.YomostPanGesture];
            }
        } @catch (NSException *e) {}
    }
}
%end

%hook YTPlayerViewController

%new
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.YomostPanGesture) {
        UIPanGestureRecognizer *panGesture = (UIPanGestureRecognizer *)gestureRecognizer;
        CGPoint startLocation = [panGesture locationInView:self.view];
        CGFloat viewWidth = self.view.bounds.size.width;

        float areaPercent = 0.15;
        int areaSetting = INTFORVAL(GestureActivationArea);
        if (areaSetting == 0) areaPercent = 0.10;
        else if (areaSetting == 2) areaPercent = 0.20;
        else if (areaSetting == 3) areaPercent = 0.25;
        else if (areaSetting == 4) areaPercent = 0.30;
        else if (areaSetting == 5) areaPercent = 0.35;
        else if (areaSetting == 6) areaPercent = 0.40;
        else if (areaSetting == 7) areaPercent = 0.45;
        else if (areaSetting == 8) areaPercent = 0.50;

        int leftAction = [[NSUserDefaults standardUserDefaults] objectForKey:LeftSideGesture] ? INTFORVAL(LeftSideGesture) : 1;
        int rightAction = [[NSUserDefaults standardUserDefaults] objectForKey:RightSideGesture] ? INTFORVAL(RightSideGesture) : 2;

        if (startLocation.x > viewWidth * areaPercent && startLocation.x < viewWidth * (1.0 - areaPercent)) return NO;
        if (startLocation.x <= viewWidth * areaPercent && leftAction == 0) return NO;
        if (startLocation.x >= viewWidth * (1.0 - areaPercent) && rightAction == 0) return NO;

        CGPoint velocity = [panGesture velocityInView:self.view];
        if (fabs(velocity.x) > fabs(velocity.y)) return NO;

        return YES;
    }
    return YES;
}

%new
- (void)YomostHandlePanGesture:(UIPanGestureRecognizer *)panGestureRecognizer {
    static float initialVolume;
    static float initialBrightness;
    static float initialSpeed;
    static int controlType = 0;
    static CGFloat deadzoneStartingTranslation;
    static CGFloat sensitivityFactor = 1.0;

    static MPVolumeView *volumeView;
    static UISlider *volumeViewSlider;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        volumeView = [[MPVolumeView alloc] initWithFrame:CGRectZero];
        for (UIView *view in volumeView.subviews) {
            if ([view isKindOfClass:[UISlider class]]) {
                volumeViewSlider = (UISlider *)view;
                break;
            }
        }
    });

    if (IS_ENABLED(GestureHUD) && !self.YomostGestureHUD) {
        self.YomostGestureHUD = [[UILabel alloc] initWithFrame:CGRectZero];
        self.YomostGestureHUD.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
        self.YomostGestureHUD.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
        self.YomostGestureHUD.tintColor = [UIColor colorWithWhite:1.0 alpha:0.75];
        self.YomostGestureHUD.textAlignment = NSTextAlignmentCenter;
        self.YomostGestureHUD.layer.masksToBounds = YES;
        self.YomostGestureHUD.alpha = 0.0;
        [self.view addSubview:self.YomostGestureHUD];
    }

    if (panGestureRecognizer.state == UIGestureRecognizerStateBegan) {
        CGPoint startLocation = [panGestureRecognizer locationInView:self.view];
        CGFloat viewWidth = self.view.bounds.size.width;

        float areaPercent = 0.15;
        int areaSetting = INTFORVAL(GestureActivationArea);
        if (areaSetting == 0) areaPercent = 0.10;
        else if (areaSetting == 2) areaPercent = 0.20;
        else if (areaSetting == 3) areaPercent = 0.25;
        else if (areaSetting == 4) areaPercent = 0.30;
        else if (areaSetting == 5) areaPercent = 0.35;
        else if (areaSetting == 6) areaPercent = 0.40;
        else if (areaSetting == 7) areaPercent = 0.45;
        else if (areaSetting == 8) areaPercent = 0.50;

        int leftAction = [[NSUserDefaults standardUserDefaults] objectForKey:LeftSideGesture] ? INTFORVAL(LeftSideGesture) : 1;
        int rightAction = [[NSUserDefaults standardUserDefaults] objectForKey:RightSideGesture] ? INTFORVAL(RightSideGesture) : 2;

        if (startLocation.x <= viewWidth * areaPercent) {
            controlType = leftAction; 
        } else if (startLocation.x >= viewWidth * (1.0 - areaPercent)) {
            controlType = rightAction;
        } else {
            controlType = 0;
        }
        
        deadzoneStartingTranslation = [panGestureRecognizer translationInView:self.view].y;
        
        if (controlType == 1) {
            initialBrightness = [UIScreen mainScreen].brightness;
        } else if (controlType == 2) {
            initialVolume = [[AVAudioSession sharedInstance] outputVolume];
        } else if (controlType == 3) {
            initialSpeed = playbackRate;
        }

        if (IS_ENABLED(GestureHUD)) {
            int sizeSetting = [[NSUserDefaults standardUserDefaults] objectForKey:@"GestureHUDSize"] ? (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"GestureHUDSize"] : 1;
            CGFloat fontSize = 14.0 + (sizeSetting * 2.0);
            CGFloat hudWidth = 74.0 + (sizeSetting * 10.0);
            CGFloat hudHeight = 30.0 + (sizeSetting * 4.0);
            
            self.YomostGestureHUD.frame = CGRectMake(0, 0, hudWidth, hudHeight);
            self.YomostGestureHUD.layer.cornerRadius = hudHeight / 2.0;
            self.YomostGestureHUD.font = [UIFont boldSystemFontOfSize:fontSize];

            int posSetting = [[NSUserDefaults standardUserDefaults] objectForKey:@"GestureHUDPosition"] ? (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"GestureHUDPosition"] : 0;
            CGFloat viewHeight = self.view.bounds.size.height;
            CGFloat centerY = viewHeight / 6.0;
            if (posSetting == 1) centerY = viewHeight / 2.0;
            else if (posSetting == 2) centerY = viewHeight * 5.0 / 6.0;

            [self.view bringSubviewToFront:self.YomostGestureHUD];
            self.YomostGestureHUD.center = CGPointMake(viewWidth / 2, centerY);
        }
    }

    if (panGestureRecognizer.state == UIGestureRecognizerStateChanged) {
        if (controlType == 0) return;
        
        CGPoint translation = [panGestureRecognizer translationInView:self.view];
        CGFloat adjustedTranslation = translation.y - deadzoneStartingTranslation;
        float delta = (-adjustedTranslation / self.view.bounds.size.height) * sensitivityFactor;
        
        NSString *symbolName = nil;
        NSString *percentString = nil;

        if (controlType == 1) {
            float newBrightness = fmaxf(fminf(initialBrightness + delta, 1.0), 0.0);
            [[UIScreen mainScreen] setBrightness:newBrightness];
            symbolName = @"sun.max.fill";
            percentString = [NSString stringWithFormat:@" %d%%", (int)(newBrightness * 100)];
        } else if (controlType == 2) {
            float newVolume = fmaxf(fminf(initialVolume + delta, 1.0), 0.0);
            volumeViewSlider.value = newVolume;
            symbolName = @"speaker.wave.2.fill";
            percentString = [NSString stringWithFormat:@" %d%%", (int)(newVolume * 100)];
        } else if (controlType == 3) {
            float speedSensitivity = 8.0; 
            float speedDelta = (-adjustedTranslation / self.view.bounds.size.height) * speedSensitivity;
            float rawSpeed = initialSpeed + speedDelta;
            float clampedSpeed = fmaxf(fminf(rawSpeed, 10.0), 0.25);
            float steppedSpeed = roundf(clampedSpeed * 4.0) / 4.0;

            static float lastUpdatedSpeed = 0;
            if (steppedSpeed != lastUpdatedSpeed) {
                [self setPlaybackRate:steppedSpeed];
                lastUpdatedSpeed = steppedSpeed;
            }
            symbolName = @"speedometer";
            percentString = [NSString stringWithFormat:@" %.2fx", steppedSpeed];
        }

        if (IS_ENABLED(GestureHUD) && symbolName) {
            @try {
                NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
                UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:self.YomostGestureHUD.font.pointSize - 1];
                UIImage *icon = [UIImage systemImageNamed:symbolName withConfiguration:config];
                attachment.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                CGFloat iconY = (self.YomostGestureHUD.font.capHeight - attachment.image.size.height) / 2.0;
                attachment.bounds = CGRectMake(0, iconY, attachment.image.size.width, attachment.image.size.height);
                NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
                NSAttributedString *textString = [[NSAttributedString alloc] initWithString:percentString attributes:@{NSFontAttributeName: self.YomostGestureHUD.font, NSForegroundColorAttributeName: self.YomostGestureHUD.textColor}];
                [attributedString appendAttributedString:textString];
                self.YomostGestureHUD.attributedText = attributedString;
                self.YomostGestureHUD.alpha = 1.0;
            } @catch (NSException *e) {}
        }
    } else if (panGestureRecognizer.state == UIGestureRecognizerStateEnded || panGestureRecognizer.state == UIGestureRecognizerStateCancelled || panGestureRecognizer.state == UIGestureRecognizerStateFailed) {
        if (IS_ENABLED(GestureHUD)) {
            [UIView animateWithDuration:0.3 delay:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
                self.YomostGestureHUD.alpha = 0.0;
            } completion:nil];
        }
    }
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.YomostPanGesture && [otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        return YES;
    }
    return NO;
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return (gestureRecognizer == self.YomostPanGesture) ? NO : YES;
}
%end
%end

// ==========================================
// KHỞI TẠO ĐIỀU KIỆN TWEAK (CONSTRUCTOR)
// ==========================================
%ctor {
    %init;
    @try {
        if (IS_ENABLED(OldQualityPicker)) {
            %init(OldVideoQuality);
        }
        if (IS_ENABLED(ExtraSpeed) || IS_ENABLED(GestureControls)) {
            %init(Speed);
        }
        if (IS_ENABLED(HidePaidPromoOverlay)) {
            %init(PaidPromoOverlay);
        }
        if (IS_ENABLED(GestureControls)) {
            %init(Gestures);
        }
        if (IS_ENABLED(ForceMiniPlayer)) {
            %init(ForceMiniPlayer);
        }
    } @catch (NSException *e) {}
}
