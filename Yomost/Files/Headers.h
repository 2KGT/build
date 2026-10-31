// Preferences and headers for Yomost Tweak
// ==========================================
// 1. SYSTEM & YOUTUBE FRAMEWORK HEADERS
// ==========================================
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h> 
#import <YouTubeHeader/_ASDisplayView.h>
#import <YouTubeHeader/YTIIcon.h>
#import <YouTubeHeader/YTRightNavigationButtons.h>
#import <YouTubeHeader/YTIElementRenderer.h>
#import <YouTubeHeader/YTPlayerBarController.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/YTWatchController.h>
#import <YouTubeHeader/YTIMenuConditionalServiceItemRenderer.h>
#import <YouTubeHeader/YTIPivotBarRenderer.h>
#import <YouTubeHeader/YTPivotBarItemView.h>
#import <YouTubeHeader/YTActionSheetAction.h>
#import <YouTubeHeader/YTIMenuItemSupportedRenderers.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayView.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTVideoQualitySwitchOriginalController.h>
#import <YouTubeHeader/YTVideoQualitySwitchRedesignedController.h>
#import <YouTubeHeader/YTInnerTubeCollectionViewController.h>
#import <YouTubeHeader/YTIShowFullscreenInterstitialCommand.h>
#import <YouTubeHeader/YTISectionListRenderer.h>
#import <YouTubeHeader/YTIShelfRenderer.h>
#import <YouTubeHeader/YTIWatchNextResponse.h>
#import <YouTubeHeader/YTPlayerOverlay.h>
#import <YouTubeHeader/YTPlayerOverlayProvider.h>
#import <YouTubeHeader/YTReelModel.h>
#import <YouTubeHeader/YTAlertView.h>
#import <YouTubeHeader/YTVarispeedSwitchController.h>
#import <YouTubeHeader/YTVarispeedSwitchControllerImpl.h>
#import <YouTubeHeader/YTVarispeedSwitchControllerOption.h>
#import <YouTubeHeader/YTMultiSizeViewController.h>
#import <YouTubeHeader/YTInlinePlayerBarContainerView.h>
#import <YouTubeHeader/YTSingleVideoTime.h>
#import <YouTubeHeader/YTSingleVideoController.h>
#import <YouTubeHeader/YTPlayerView.h>
#import <YouTubeHeader/YTLabel.h>
#import <YouTubeHeader/YTCommonColorPalette.h>
#import <YouTubeHeader/YTQTMButton.h> 
#import <YouTubeHeader/YTIPivotBarItemRenderer.h>
#import <YouTubeHeader/YTIPivotBarSupportedRenderers.h>
#import <YouTubeHeader/YTSettingsCell.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// For Settings.x & Preferences
#import <PSHeader/Misc.h>
#import <YouTubeHeader/YTSettingsGroupData.h>
#import <YouTubeHeader/YTSettingsPickerViewController.h>
#import <YouTubeHeader/YTSettingsSectionItem.h>
#import <YouTubeHeader/YTSearchableSettingsViewController.h>
#import <YouTubeHeader/YTSettingsSectionItemManager.h>
#import <YouTubeHeader/YTSettingsViewController.h>
#import <YouTubeHeader/YTToastResponderEvent.h>
#import <YouTubeHeader/YTUIUtils.h>

// ==========================================
// 2. MACROS & USERDEFAULTS MANAGEMENT
// ==========================================
#define IS_ENABLED(k) [[NSUserDefaults standardUserDefaults] boolForKey:k]
#define INTFORVAL(v) [[NSUserDefaults standardUserDefaults] integerForKey:v]

#define LOC(x) [NSBundle.mainBundle localizedStringForKey:x value:nil table:nil]
#define ytlBool(key) [[NSUserDefaults standardUserDefaults] boolForKey:key]
#define ytlSetBool(val, key) [[NSUserDefaults standardUserDefaults] setBool:val forKey:key]
#define ytlInt(key) (int)[[NSUserDefaults standardUserDefaults] integerForKey:key]
#define ytlSetInt(val, key) [[NSUserDefaults standardUserDefaults] setInteger:val forKey:key]

// Kiểm tra tránh re-define macro hệ thống hệ điều hành
#ifndef OS_STRINGIFY
#define OS_STRINGIFY(s) #s
#endif

// Keys Định Nghĩa
#define DownloadManager @"YomostDownloadManager"
#define DownloadSaveToPhotos @"YomostDownloadSaveToPhotos"
#define DownloadPreferDRCAudio @"YomostDownloadPreferDRCAudio"
#define AutoClearCache @"YomostAutoClearCache"
#define OLEDTheme @"YomostEnablesOLEDTheme"
#define OLEDKeyboard @"YomostEnablesOLEDKeyboard"
#define HideYTLogo @"YomostHideYTLogo"
#define YTPremiumLogo @"YomostYTPremiumLogo"
#define HideNoti @"YomostHideNotificationButton"
#define HideSearch @"YomostHideSearchButton"
#define HideVoiceSearch @"YomostHideVoiceSearchButton"
#define HideCastButtonNav @"YomostHideCastButtonNavigationBar"
#define HideSubbar @"YomostHideSubbar"
#define HideGenMusicShelf @"YomostHideGenMusicShelf"
#define HideFeedPost @"YomostHideFeedPost"
#define HideShortsShelf @"YomostHideShortsShelf"
#define HideSearchHis @"YomostHideSearchHistoryAndSuggestions"
#define HideSubButton @"YomostHideSubscribeButton"
#define ShoppingButton @"YomostHideShoppingButton"
#define HideMemberButton @"YomostHideMemberButton"
#define HideAutoPlayToggle @"YomostHideAutoPlayToggle"
#define HideCaptionsButton @"YomostHideCaptionsButton"
#define HideCastButtonPlayer @"YomostHideCastButtonPlayer"
#define HidePrevButton @"YomostHidePrevButton"
#define HideNextButton @"YomostHideNextButton"
#define ReplacePrevNextButtons @"YomostReplacePrevNextButtons"
#define RemoveDarkOverlay @"YomostRemoveDarkOverlay"
#define RemoveAmbiant @"YomostRemoveAmbiantColors"
#define HideEndScreenCards @"YomostHideEndScreenCards"
#define HideSuggestedVideo @"YomostHideSuggestedVideoOnFinish"
#define HidePaidPromoOverlay @"YomostHidePaidPromoOverlay"
#define HideWaterMark @"YomostHideWaterMark"
#define GestureControls @"YomostEnableGesturesControls"
#define GestureActivationArea @"YomostGestureActivationArea"
#define LeftSideGesture @"YomostLeftSideGesture"
#define RightSideGesture @"YomostRightSideGesture"
#define GestureHUD @"YomostGestureHUD"
#define DisablesDoubleTap @"YomostDisablesDoubleTap"
#define DisablesLongHold @"YomostDisablesLongHold"
#define AutoExitFullScreen @"YomostAutoExitFullScreen"
#define DisablesCaptions @"YomostAutoDisablesCaptions"
#define DisablesShowRemaining @"YomostDisablesShowRemainingTime"
#define AlwaysShowRemaining @"YomostAlwaysShowRemainingTime"
#define ShowExtraTimeRemaining @"YomostShowExtraTimeRemaining"
#define HideFullAction @"YomostHideFullScreenAction"
#define HideFullvidTitle @"YomostHideFullscreenVideoTitle"
#define StopAutoplayVideo @"YomostStopAutoplayVideo"
#define HideContentWarning @"YomostHideContentWarning"
#define AutoFullScreen @"YomostAutoFullScreen"
#define PortFull @"YomostPortraitFullscreen"
#define OldQualityPicker @"YomostUseOldQualityPicker"
#define ExtraSpeed @"YomostAddExtraSpeed"
#define DisableHints @"YomostDisableHints"
#define ForceMiniPlayer @"YomostForceMiniPlayer"
#define AlwaysShowSeekbar @"YomostAlwaysShowSeekbar"
#define HideLikeButton @"YomostHideLikeButton"
#define HideDisLikeButton @"YomostHideDisLikeButton"
#define HideShareButton @"YomostHideShareButton"
#define HideDownloadButton @"YomostHideDownloadButton"
#define HideClipButton @"YomostHideClipButton"
#define HideRemixButton @"YomostHideRemixButton"
#define HideSaveButton @"YomostHideSaveButton"
#define EnableShortsDownload       @"YomostEnableShortsDownload"
#define HideShortsLikeButton @"YomostHideShortsLikeButton"
#define HideShortsDisLikeButton @"YomostHideShortsDisLikeButton"
#define HideShortsCommentButton @"YomostHideShortsCommentButton"
#define HideShortsShareButton @"YomostHideShortsShareButton"
#define HideShortsRemixButton @"YomostHideShortsRemixButton"
#define HideShortsMetaButton @"YomostHideShortsMetaButton"
#define HideShortsProducts @"YomostHideShortsProducts"
#define HideShortsRecbar @"YomostHideShortsRecbar"
#define HideShortsCommit @"YomostHideShortsCommit"
#define HideShortsSubscriptButton @"YomostHideShortsSubscriptButton"
#define HideShortsLiveButton @"YomostHideShortsLiveButton"
#define HideShortsLensButton @"YomostHideShortsLensButton"
#define HideShortsTrendsButton @"YomostHideShortsTrendsButton"
#define HideShortsToVideo @"YomostHideShortsToVideo"
#define EnablesShortsQuality @"YomostEnablesShortsQuality"
#define ShowShortsSeekbar @"YomostShowShortsSeekbar"
#define DefaultTab @"YomostDefaultStartupTab"
#define HideTabIndi @"YomostHideTabIndicators"
#define HideTabLabels @"YomostHideTabLabels"
#define HideHomeTab @"YomostHideHomeTab"
#define HideShortsTab @"YomostHideShortsTab"
#define HideCreateButton @"YomostHideCreateButton"
#define HideSubscriptTab @"YomostHideSubscriptionsTab"
#define HideLibraryTab @"YomostHideLibraryTab"
#define BackgroundPlayback @"YomostEnablesBackgroundPlayback"
#define DisablesShortsPiP @"YomostTrytoDisablesShortsPiP"
#define BlockUpgradeDialogs @"YomostBlockUpgradeDialogs"
#define HideAreYouThereDialog @"YomostHideAreYouThereDialog"
#define FixesSlowMiniPlayer @"YomostFixesSlowMiniPlayer"
#define DisablesNewMiniPlayer @"YomostDisablesNewMiniPlayer"
#define DisablesSnackBar @"YomostDisablesSnackBar"
#define HideStartupAni @"YomostHideStartupAnimations"
#define HidePlayInNextQueue @"YomostHidePlayInNextQueue"
#define HideLikeDislikeVotes @"YomostHideLikeDislikeVotes"

#define YT_BUNDLE_ID @"com.google.ios.youtube"
#define YT_NAME @"YouTube"

// ==========================================
// 3. ENUMS & EXTENSION CATEGORIES
// ==========================================
typedef NS_ENUM(NSUInteger, GestureSection) {
    GestureSectionTop,
    GestureSectionBottom,
    GestureSectionInvalid
};

@interface YTITopbarLogoRenderer : NSObject
@property(readonly, nonatomic) YTIIcon *iconImage;
@end

@interface YTRightNavigationButtons (Yomost)
@property (nonatomic, strong) YTQTMButton *notificationButton;
@property (nonatomic, strong) YTQTMButton *searchButton;
@property (nonatomic, strong) YTQTMButton *voiceSearchButton; // Khai báo thêm cho nút giọng nói
@end

@interface YTMainAppVideoPlayerOverlayView (Yomost)
@property (nonatomic, strong) YTQTMButton *playbackRouteButton;
@end

@interface YTNavigationBarTitleView : UIView
@property (nonatomic, strong) UIImageView *logoImageView; // Khai báo cho tính năng đổi logo
@end

// Lớp điều khiển các nút chức năng tương tác ở cạnh/dưới trình phát
@interface YTTransportControlsButtonView : UIView
@property (nonatomic, strong) YTQTMButton *thanksButton;
@property (nonatomic, strong) YTQTMButton *reportButton;
@property (nonatomic, strong) YTQTMButton *hypeButton;
@property (nonatomic, strong) YTQTMButton *stopAdsButton;
@end

@interface YTChipCloudCell : UICollectionViewCell
@end

@interface YTSearchViewController : UIViewController
@end

@interface YTPlayabilityResolutionUserActionUIController : NSObject
- (void)confirmAlertDidPressConfirm;
@end

@interface YTPlayabilityResolutionUserActionUIControllerImpl : NSObject
- (void)confirmAlertDidPressConfirm;
@end

@interface YTSettingsSectionItemManager (Yomost)
- (void)updateYomostSectionWithEntry:(id)entry;
@end

@interface YTPivotBarViewController : UIViewController
- (void)selectItemWithPivotIdentifier:(id)pivotIndentifier;
@end

@interface YTPivotBarItemView (Yomost)
@property (nonatomic, strong) UIButton *navigationButton;
@property (nonatomic, strong, readonly) UIView *titleLabel;
@end

@interface YTIPivotBarItemRenderer (Yomost)
- (NSString *)pivotIdentifier;
@end

@interface YTIPivotBarSupportedRenderers (Yomost)
- (YTIPivotBarItemRenderer *)pivotBarItemRenderer;
- (YTIPivotBarItemRenderer *)pivotBarIconOnlyItemRenderer;
@end

@interface YTIPivotBarRenderer (Yomost)
- (NSMutableArray *)itemsArray;
@end

@interface YTHeaderContentComboViewController : UIViewController
- (void)refreshPivotBar;
@end

@interface ABCOption : NSObject
@end

@interface ABCSwitch : UIView
@property(nonatomic, assign) BOOL on;
@property(nonatomic, strong) UIColor *onTintColor;
@end

@interface YTTouchFeedbackController : NSObject
@property(nonatomic, strong) UIColor *feedbackColor;
@end

@interface YTLUserDefaults : NSObject
+ (void)resetUserDefaults;
@end

@interface YTReelInnerShortsContentView : UIView
@end

@interface YTPlayerViewController (Yomost) <UIGestureRecognizerDelegate>
@property (nonatomic, retain) UIPanGestureRecognizer *YomostPanGesture;
@property (nonatomic, retain) UILabel *YomostGestureHUD;
@property (nonatomic, strong) NSTimer *sleepTimer; // Khai báo hỗ trợ Sleep Timer mới
@property (nonatomic, assign) CGFloat customPlaybackSpeed; // Khai báo hỗ trợ HoldToSpeed cử chỉ gõ giữ
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer;
- (void)YomostAutoFullscreen;
- (void)YomostTurnOffCaptions;
- (void)setActiveCaptionTrack:(id)arg1 source:(long long)arg2;
- (void)setPlaybackRate:(float)rate;
- (void)showCompactToastWithText:(NSString *)text; // Khai báo hỗ trợ Toast thông báo cử chỉ rút gọn
@end

@interface YTVideoQualitySwitchOriginalController (Yomost)
@property (retain, nonatomic) YTVideoQualitySwitchRedesignedController *redesignedController;
@end

@interface UIView (Private)
@property (nonatomic, assign, readonly) BOOL _mapkit_isDarkModeEnabled;
- (UIViewController *)_viewControllerForAncestor;
@end

@interface UIKeyboard : UIView
+ (instancetype)activeKeyboard;
@end

@interface UIPredictionViewController : UIViewController
@end

@interface UIKeyboardDockView : UIView
@end

@interface UIKBVisualEffectView : UIVisualEffectView
@property (nonatomic, copy, readwrite) NSArray *backgroundEffects;
@end

@interface YTAppDelegate : UIResponder
- (void)YomostAutoClearCache;
- (void)manualClearCacheWithCompletion:(void (^)(NSString *newSize))completion;
@end

// ==========================================
// 4. PREFERENCES MANAGEMENT CORE INTERFACE
// ==========================================
@interface YomostPrefsManager : NSObject <UIDocumentPickerDelegate>
+ (instancetype)sharedManager;
- (void)exportYomostSettingsFromVC:(UIViewController *)vc;
- (void)importYomostSettingsFromVC:(UIViewController *)vc;
- (void)restoreYomostDefaults;

// Khai báo bổ sung các phương thức xử lý Document Picker (Tránh lỗi no visible @interface)
- (void)configurePopoverForPicker:(UIDocumentPickerViewController *)picker inViewController:(UIViewController *)vc;
- (void)presentImportPickerInViewController:(UIViewController *)vc;
- (void)presentExportPickerForURL:(NSURL *)fileURL inViewController:(UIViewController *)vc;
@end

// ==========================================
// 5. PLAYER BAR & SCRUBBER HEADERS
// ==========================================
@interface YTFineScrubberFilmstripView : UIView
@end

@interface YTFineScrubberFilmstripCollectionView : UICollectionView
@end

@interface YTWatchFullscreenViewController : YTMultiSizeViewController
@end

@interface YTPlayerBarController (Yomost)
- (void)didScrub:(UIPanGestureRecognizer *)gestureRecognizer;
- (void)startScrubbing;
- (void)didScrubToPoint:(CGPoint)point;
- (void)endScrubbingForSeekSource:(int)seekSource;
@end

@interface YTMainAppVideoPlayerOverlayViewController (Yomost)
@property (nonatomic, strong, readwrite) YTPlayerBarController *playerBarController;
@end

@interface YTInlinePlayerBarContainerView (Yomost)
@property UIPanGestureRecognizer *scrubGestureRecognizer;
@property (nonatomic, strong, readwrite) YTFineScrubberFilmstripView *fineScrubberFilmstrip;
@property (nonatomic, strong, readwrite) NSString *endTimeString;
- (CGFloat)scrubXForScrubRange:(CGFloat)scrubRange;
@end

@interface YTSingleVideoController (Yomost)
@property (nonatomic, assign, readonly) CGFloat totalMediaTime;
@end

@interface YTShortsPlayerControlsViewController : UIViewController
- (id)currentVideoId;
@end

@interface YTActionSheetController : UIViewController
- (void)addAction:(id)action;
@end

@interface YTAlertAction : NSObject
+ (instancetype)actionWithTitle:(NSString *)title style:(NSInteger)style handler:(void (^)(id action))handler;
@end
