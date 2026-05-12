// VCAM V181.0: The Surgical Strike - Live Hijack without Gallery Overwrite
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *vcamWebView = nil;
static UIImage *liveSnapshot = nil;

static void setup_vcam_v181(UIView *parent) {
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

    NSString *js = @"var s = document.createElement('style'); s.innerHTML = '* { -webkit-tap-highlight-color: transparent !important; } body, html, img, video { margin: 0; padding: 0; width: 100vw; height: 100vh; object-fit: cover; background: black !important; } .vjs-control-bar, .vjs-big-play-button, .controls, .play-button { display: none !important; }'; document.head.appendChild(s); setInterval(function(){ var v = document.querySelector('video'); if(v) v.play(); }, 50);";
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [vcamWebView.configuration.userContentController addUserScript:script];

    [parent insertSubview:vcamWebView atIndex:0];

    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
        if (!enabled) return;
        [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
            if (img) liveSnapshot = img;
        }];
    }];
}

// 1. SURGICAL PREVIEW HIJACK
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *p = (UIView *)self.delegate;
        if (!p || ![p isKindOfClass:[UIView class]]) p = (UIView *)self.superlayer.delegate;
        if (p && [p isKindOfClass:[UIView class]]) {
            setup_vcam_v181(p);
            vcamWebView.frame = p.bounds;
            [p sendSubviewToBack:vcamWebView];
            [self setOpacity:0.0];
        }
    }
}
%end

// 2. SURGICAL PHOTO CAPTURE HIJACK
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && liveSnapshot) return UIImageJPEGRepresentation(liveSnapshot, 0.95);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation {
    if (enabled && liveSnapshot) return liveSnapshot.CGImage;
    return %orig;
}
- (struct CGImage *)previewCGImageRepresentation {
    if (enabled && liveSnapshot) return liveSnapshot.CGImage;
    return %orig;
}
%end

// 3. TARGETED CAMERA UI HIJACK (Only in Camera App)
%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && liveSnapshot) %orig(liveSnapshot);
    else %orig;
}
%end

// 4. DEVICE SPOOFING FOR BANKS
%hook AVCaptureDevice
- (NSString *)localizedName { return enabled ? @"Back Camera" : %orig; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = p[@"rtspURL"];
    }
}
