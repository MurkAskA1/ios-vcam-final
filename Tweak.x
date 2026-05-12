// VirtualCamPro V213.0: The Global Stealth Engine
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *vcamWebView = nil;
static UIImage *lastSnapshot = nil;

// --- Hardware Spoofing (Global) ---

%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
%end

// --- Global Hijack Logic (AVFoundation Level) ---

%hook AVCaptureConnection
- (BOOL)isEnabled {
    if (enabled && [self.output isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")]) {
        return NO; // Block real camera preview globally
    }
    return %orig;
}
%end

static void setup_global_vcam(UIView *parent) {
    if (!parent || !enabled) return;
    
    // Ensure we don't stack multiple views
    if (vcamWebView && vcamWebView.superview == parent) {
        [parent bringSubviewToFront:vcamWebView];
        return;
    }

    if (vcamWebView) [vcamWebView removeFromSuperview];

    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    vcamWebView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamWebView.backgroundColor = [UIColor blackColor];
    vcamWebView.opaque = YES;
    vcamWebView.userInteractionEnabled = NO;
    vcamWebView.scrollView.scrollEnabled = NO;

    // Robust MJPEG Loader for WebKit
    NSString *html = [NSString stringWithFormat:
        @"<html><head><style>"
        "body{margin:0;padding:0;background:black;overflow:hidden;}"
        "img{width:100%%;height:100%%;object-fit:cover;position:fixed;top:0;left:0;}"
        "</style></head><body>"
        "<img src='%@' onerror='this.src=this.src;'>"
        "</body></html>", streamURL];
    
    [vcamWebView loadHTMLString:html baseURL:nil];
    
    // Find the right place in the hierarchy to stay behind native UI buttons
    if ([parent respondsToSelector:@selector(insertSubview:atIndex:)]) {
        [parent insertSubview:vcamWebView atIndex:0];
    } else {
        [parent addSubview:vcamWebView];
    }

    // Global snapshot for photo/recording hijack
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
            if (vcamWebView) {
                [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
                    if (img) lastSnapshot = img;
                }];
            }
        }];
    });
}

// Hook Preview Layer for ALL apps
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *target = nil;
        if ([self.delegate isKindOfClass:[UIView class]]) target = (UIView *)self.delegate;
        else if ([self.superlayer.delegate isKindOfClass:[UIView class]]) target = (UIView *)self.superlayer.delegate;

        if (target) {
            setup_global_vcam(target);
            vcamWebView.frame = target.bounds;
        }
    }
}
%end

// --- Global Capture Hijack (Photo & Video Data) ---

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && lastSnapshot) return UIImageJPEGRepresentation(lastSnapshot, 0.9);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation {
    if (enabled && lastSnapshot) return lastSnapshot.CGImage;
    return %orig;
}
%end

// --- Gallery & UI Hijack (Consistent Experience) ---

%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && lastSnapshot) %orig(lastSnapshot);
    else %orig;
}
%end

%hook PHImageManager
- (PHImageRequestID)requestImageForAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(PHImageContentMode)contentMode options:(PHImageRequestOptions *)options resultHandler:(void (^)(UIImage *result, NSDictionary *info))resultHandler {
    // Protect privacy: only hijack photos taken while tweak was active (last 60s)
    if (enabled && lastSnapshot && [[NSDate date] timeIntervalSinceDate:asset.creationDate] < 60) {
        if (resultHandler) {
            resultHandler(lastSnapshot, nil);
            return (PHImageRequestID)1;
        }
    }
    return %orig;
}
%end

%ctor {
    NSUserDefaults *defs = [[NSUserDefaults alloc] initWithSuiteName:@"com.murkaska.virtualcampro"];
    enabled = [defs objectForKey:@"enabled"] ? [defs boolForKey:@"enabled"] : YES;
    NSString *str = [defs stringForKey:@"rtspURL"];
    if (str && str.length > 5) streamURL = str;
    
    NSLog(@"[VirtualCamPro] Global Stealth Engine V213.0 Active");
}