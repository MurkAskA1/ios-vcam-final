// VCAM V180.0: The KYC Final Boss - Absolute System Hijack
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static NSString *sharedPath = @"/tmp/vcam_snap.jpg";
static WKWebView *vcamWebView = nil;
static UIImage *globalSnapshot = nil;

static UIImage *get_safe_snapshot() {
    if (globalSnapshot) return globalSnapshot;
    UIImage *fileImg = [UIImage imageWithContentsOfFile:sharedPath];
    return fileImg;
}

static void setup_vcam_v180(UIView *parent) {
    if (!parent || (vcamWebView && vcamWebView.superview == parent)) return;
    if (vcamWebView) [vcamWebView removeFromSuperview];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    vcamWebView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamWebView.backgroundColor = [UIColor blackColor];
    vcamWebView.userInteractionEnabled = NO;
    vcamWebView.scrollView.scrollEnabled = NO;
    vcamWebView.opaque = NO;

    [vcamWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];

    NSString *js = @"var s = document.createElement('style'); s.innerHTML = '* { -webkit-tap-highlight-color: transparent !important; } body, html, img, video { margin: 0; padding: 0; width: 100vw; height: 100vh; object-fit: cover; background: black !important; } .vjs-control-bar, .vjs-big-play-button, .controls, .play-button, .pause-indicator { display: none !important; }'; document.head.appendChild(s); setInterval(function(){ var v = document.querySelector('video'); if(v) v.play(); }, 50);";
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [vcamWebView.configuration.userContentController addUserScript:script];

    [parent insertSubview:vcamWebView atIndex:0];

    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
        if (!enabled) return;
        [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
            if (img) {
                globalSnapshot = img;
                NSData *data = UIImageJPEGRepresentation(img, 0.8);
                [data writeToFile:sharedPath atomically:YES];
            }
        }];
    }];
}

// 1. GLOBAL IMAGE CREATION HIJACK (Fixed White Screen)
%hook UIImage
+ (UIImage *)imageWithCGImage:(struct CGImage *)cgImage {
    if (enabled) {
        UIImage *snap = get_safe_snapshot();
        if (snap) return snap;
    }
    return %orig;
}
+ (UIImage *)imageWithData:(NSData *)data {
    if (enabled && data.length > 3000) {
        UIImage *snap = get_safe_snapshot();
        if (snap) return snap;
    }
    return %orig;
}
%end

// 2. DATA REPRESENTATION HIJACK
FOUNDATION_EXTERN NSData *UIImageJPEGRepresentation(UIImage *image, CGFloat compressionQuality);
%hookf(NSData *, UIImageJPEGRepresentation, UIImage *image, CGFloat compressionQuality) {
    if (enabled) {
        UIImage *snap = get_safe_snapshot();
        if (snap && image != snap) return %orig(snap, compressionQuality);
    }
    return %orig(image, compressionQuality);
}

// 3. PHOTOS DATABASE HIJACK (Telegram Picker & Gallery)
%hook PHImageManager
- (int)requestImageForAsset:(id)asset targetSize:(struct CGSize)targetSize contentMode:(int)contentMode options:(id)options resultHandler:(void (^)(UIImage *result, NSDictionary *info))resultHandler {
    if (enabled && resultHandler) {
        UIImage *snap = get_safe_snapshot();
        if (snap) {
            resultHandler(snap, nil);
            return 1337;
        }
    }
    return %orig;
}
%end

// 4. PREVIEW AND LAYER HIJACK
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *p = (UIView *)self.delegate;
        if (!p || ![p isKindOfClass:[UIView class]]) p = (UIView *)self.superlayer.delegate;
        if (p && [p isKindOfClass:[UIView class]]) {
            setup_vcam_v180(p);
            vcamWebView.frame = p.bounds;
            [p sendSubviewToBack:vcamWebView];
            [self setOpacity:0.0];
        }
    }
}
%end

// 5. CAMERA CIRCLE (CAMImageWell)
%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    UIImage *snap = get_safe_snapshot();
    if (enabled && snap) %orig(snap);
    else %orig;
}
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = p[@"rtspURL"];
    }
}
