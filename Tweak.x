// VirtualCamPro V229.0: The Stealth Void (Black Background & ATS Fix)
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *globalVcamView = nil;
static UIImage *globalLastImage = nil;

// --- Direct Preference Loading ---
static void load_vcam_prefs() {
    NSArray *paths = @[@"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist", 
                       @"/var/jb/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d) {
            enabled = [d[@"enabled"] ?: @YES boolValue];
            NSString *u = d[@"rtspURL"];
            if (u && u.length > 5) streamURL = u;
            break;
        }
    }
}

// --- Global ATS Fix: Critical for HTTP Streams ---
%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"NSAppTransportSecurity"]) {
        return @{ 
            @"NSAllowsArbitraryLoads": @YES, 
            @"NSAllowsArbitraryLoadsInWebContent": @YES, 
            @"NSAllowsLocalNetworking": @YES 
        };
    }
    return %orig;
}
%end

// --- Continuous Snapshot for Photo Hijack ---
static void start_frame_capture() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
            if (enabled && globalVcamView) {
                [globalVcamView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
                    if (img) globalLastImage = img;
                }];
            }
        }];
    });
}

// --- Visual Hijack (The "Black Void" Engine) ---
static void inject_vcam_into_view(UIView *parent) {
    if (!parent || !enabled) return;
    
    if (globalVcamView && globalVcamView.superview == parent) {
        [parent bringSubviewToFront:globalVcamView];
        return;
    }

    if (globalVcamView) [globalVcamView removeFromSuperview];

    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    globalVcamView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    
    // Force absolute black everywhere to kill the white screen
    globalVcamView.backgroundColor = [UIColor blackColor];
    globalVcamView.scrollView.backgroundColor = [UIColor blackColor];
    if (@available(iOS 15.0, *)) {
        globalVcamView.underPageBackgroundColor = [UIColor blackColor];
    }
    
    globalVcamView.opaque = YES;
    globalVcamView.userInteractionEnabled = NO;
    globalVcamView.scrollView.scrollEnabled = NO;

    // HTML with explicit black background style to prevent white flashes
    NSString *html = [NSString stringWithFormat:
        @"<html><head><meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no'>"
        "<style>"
        "body{margin:0;padding:0;background-color:black !important;overflow:hidden;width:100%%;height:100%%;} "
        "img{width:100%%;height:100%%;object-fit:cover;position:absolute;top:0;left:0;}"
        "</style></head><body style='background-color:black;'>"
        "<img src='%@' onerror=\"this.src=this.src;\">"
        "</body></html>", streamURL];
    
    [globalVcamView loadHTMLString:html baseURL:nil];
    
    // Sits at the absolute bottom layer
    [parent insertSubview:globalVcamView atIndex:0];
    
    start_frame_capture();
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *target = nil;
        if ([self.delegate isKindOfClass:[UIView class]]) target = (UIView *)self.delegate;
        else if ([self.superlayer.delegate isKindOfClass:[UIView class]]) target = (UIView *)self.superlayer.delegate;

        if (target) {
            inject_vcam_into_view(target);
            globalVcamView.frame = target.bounds;
        }
    }
}
%end

// --- Disable Real Preview Data ---
%hook AVCaptureConnection
- (BOOL)isEnabled {
    if (enabled && [self.output isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")]) {
        return NO; // Make real camera transparent
    }
    return %orig;
}
%end

// --- Anti-KYC Identity Spoofing ---
%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
- (BOOL)isVirtualDevice { return NO; }
%end

// --- Global Capture Hijack ---
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && globalLastImage) return UIImageJPEGRepresentation(globalLastImage, 0.95);
    return %orig;
}
%end

%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && globalLastImage) %orig(globalLastImage);
    else %orig;
}
%end

%ctor {
    load_vcam_prefs();
    NSLog(@"[VirtualCamPro] The Stealth Void V229.0 Active");
}