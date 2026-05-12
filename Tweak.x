// VCAM V196.0: Final Stability
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <Photos/Photos.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *vcamWebView = nil;
static UIImage *lastCleanSnapshot = nil;

static void setup_vcam_v196(UIView *parent) {
    if (!parent) return;
    if (vcamWebView && vcamWebView.superview == parent) return;
    if (vcamWebView) [vcamWebView removeFromSuperview];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    vcamWebView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamWebView.backgroundColor = [UIColor blackColor];
    vcamWebView.userInteractionEnabled = NO;
    vcamWebView.scrollView.scrollEnabled = NO;
    vcamWebView.opaque = YES;

    [vcamWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];

    NSString *js = @"var s = document.createElement('style'); "
                    "s.innerHTML = '* { background: black !important; color: transparent !important; } "
                    "video { position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; object-fit: cover !important; z-index: 9999 !important; } "
                    ".vjs-control-bar, .controls, button { display: none !important; }'; "
                    "document.head.appendChild(s); "
                    "setInterval(function(){ var v = document.querySelector('video'); if(v) { v.play(); v.controls = false; } }, 100);";

    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [vcamWebView.configuration.userContentController addUserScript:script];

    [parent insertSubview:vcamWebView atIndex:0];

    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
        if (!enabled) return;
        [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
            if (img) lastCleanSnapshot = img;
        }];
    }];
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *p = (UIView *)self.delegate;
        if (p && [p isKindOfClass:[UIView class]]) {
            setup_vcam_v196(p);
            vcamWebView.frame = p.bounds;
            [p sendSubviewToBack:vcamWebView];
            [self setOpacity:0.0];
        }
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && lastCleanSnapshot) {
        return UIImageJPEGRepresentation(lastCleanSnapshot, 0.9);
    }
    return %orig;
}
- (struct CGImage *)CGImageRepresentation {
    if (enabled && lastCleanSnapshot) {
        return lastCleanSnapshot.CGImage;
    }
    return %orig;
}
%end

%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && lastCleanSnapshot) {
        %orig(lastCleanSnapshot);
    } else {
        %orig;
    }
}
%end

%hook AVCaptureDevice
- (NSString *)localizedName { return enabled ? @"Back Camera" : %orig; }
- (NSString *)modelID { return enabled ? @"iPhone Camera" : %orig; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = p[@"rtspURL"];
    }
}
