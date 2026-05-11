// VCAM V175.0: The Total Eraser - No Thumbnail Leaks
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *vcamWebView = nil;
static UIImage *sharedSnapshot = nil;

static void setup_vcam_v175(UIView *parent) {
    if (!parent || (vcamWebView && vcamWebView.superview == parent)) return;
    if (vcamWebView) [vcamWebView removeFromSuperview];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    vcamWebView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamWebView.backgroundColor = [UIColor blackColor];
    vcamWebView.userInteractionEnabled = NO;
    vcamWebView.scrollView.scrollEnabled = NO;

    [vcamWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];

    NSString *js = @"var s = document.createElement('style'); s.innerHTML = '* { -webkit-tap-highlight-color: transparent !important; } body, html, img, video { margin: 0; padding: 0; width: 100vw; height: 100vh; object-fit: cover; background: black !important; overflow: hidden !important; } .vjs-control-bar, .vjs-big-play-button, .vjs-loading-spinner, .controls, .play-button, .pause-indicator { display: none !important; opacity: 0 !important; }'; document.head.appendChild(s); setInterval(function(){ var v = document.querySelector('video'); if(v) { v.play(); v.controls = false; } }, 50);";
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [vcamWebView.configuration.userContentController addUserScript:script];

    [parent insertSubview:vcamWebView atIndex:0];

    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
        if (!enabled) return;
        [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
            if (img) sharedSnapshot = img;
        }];
    }];
}

// 1. GLOBAL UIIMAGE CREATION HIJACK (Aggressive threshold: 30px)
%hook UIImage
+ (UIImage *)imageWithCGImage:(struct CGImage *)cgImage {
    if (enabled && sharedSnapshot && cgImage) {
        if (CGImageGetWidth(cgImage) > 30) return sharedSnapshot;
    }
    return %orig;
}
+ (UIImage *)imageWithData:(NSData *)data {
    if (enabled && sharedSnapshot && data.length > 5000) return sharedSnapshot;
    return %orig;
}
%end

// 2. DATA REPRESENTATION HIJACK (No original bytes in file)
FOUNDATION_EXTERN NSData *UIImageJPEGRepresentation(UIImage *image, CGFloat compressionQuality);
%hookf(NSData *, UIImageJPEGRepresentation, UIImage *image, CGFloat compressionQuality) {
    if (enabled && sharedSnapshot && image != sharedSnapshot && image.size.width > 30) {
        return %orig(sharedSnapshot, compressionQuality);
    }
    return %orig(image, compressionQuality);
}

// 3. DATABASE IMAGE MANAGER HIJACK (For gallery icons)
%hook PHImageManager
- (int)requestImageForAsset:(id)asset targetSize:(struct CGSize)targetSize contentMode:(int)contentMode options:(id)options resultHandler:(void (^)(UIImage *result, NSDictionary *info))resultHandler {
    if (enabled && sharedSnapshot && resultHandler) {
        return %orig(asset, targetSize, contentMode, options, ^(UIImage *result, NSDictionary *info) {
            resultHandler(sharedSnapshot, info);
        });
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
            setup_vcam_v175(p);
            vcamWebView.frame = p.bounds;
            [p sendSubviewToBack:vcamWebView];
            [self setOpacity:0.0];
        }
    }
}
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = p[@"rtspURL"];
    }
}
