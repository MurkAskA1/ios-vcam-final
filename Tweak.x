// VirtualCamPro V212.0: The Stealth Vision (Black Screen Fix)
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *vcamWebView = nil;
static UIImage *lastSnapshot = nil;
static UILabel *debugLabel = nil;

// --- Anti-Detection ---

%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
%end

%hook AVCaptureConnection
- (BOOL)isEnabled {
    if (enabled && [self.output isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")]) return NO;
    return %orig;
}
%end

// --- Global ATS Fix ---
%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"NSAppTransportSecurity"]) {
        return @{ @"NSAllowsArbitraryLoads": @YES, @"NSAllowsArbitraryLoadsInWebContent": @YES };
    }
    return %orig;
}
%end

static void setup_vcam_v2(UIView *parent) {
    if (!parent || !enabled) return;
    
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

    // High-Compatibility HTML Wrapper
    NSString *html = [NSString stringWithFormat:
        @"<html><head><meta name='viewport' content='width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no'>"
        "<style>body{margin:0;padding:0;background:black;overflow:hidden;} img{width:100vw;height:100vh;object-fit:contain;}</style>"
        "</head><body><img src='%@' onerror=\"this.src=this.src;\"></body></html>", streamURL];
    
    [vcamWebView loadHTMLString:html baseURL:[NSURL URLWithString:streamURL]];
    [parent insertSubview:vcamWebView atIndex:0]; // Stay behind buttons

    if (!debugLabel) {
        debugLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, 300, 20)];
        debugLabel.textColor = [UIColor greenColor];
        debugLabel.font = [UIFont systemFontOfSize:8];
    }
    debugLabel.text = [NSString stringWithFormat:@"VCAM V212.0: %@", streamURL];
    [parent addSubview:debugLabel];

    // Snapshot Loop for Photo Hijack
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

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *target = nil;
        if ([self.delegate isKindOfClass:[UIView class]]) target = (UIView *)self.delegate;
        else if ([self.superlayer.delegate isKindOfClass:[UIView class]]) target = (UIView *)self.superlayer.delegate;

        if (target) {
            setup_vcam_v2(target);
            vcamWebView.frame = target.bounds;
        }
    }
}
%end

// --- Photo Hijack ---

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

// --- UI & Gallery Hijack ---

%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && lastSnapshot) %orig(lastSnapshot);
    else %orig;
}
%end

%hook PHImageManager
- (PHImageRequestID)requestImageForAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(PHImageContentMode)contentMode options:(PHImageRequestOptions *)options resultHandler:(void (^)(UIImage *result, NSDictionary *info))resultHandler {
    if (enabled && lastSnapshot && [[NSDate date] timeIntervalSinceDate:asset.creationDate] < 15) {
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
    
    NSLog(@"[VirtualCamPro] Stealth Engine V212.0 Active");
}