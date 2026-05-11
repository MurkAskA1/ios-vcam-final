// VCAM V155.0: The Final Stealth Strike - Clean Text Fix & Perfect UI
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *vcamWebView = nil;
static UIImage *snapshotForHijack = nil;

static void setup_vcam_final_boss(UIView *parent) {
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

    NSString *js = @"var s = document.createElement('style'); s.innerHTML = '* { -webkit-tap-highlight-color: transparent !important; outline: none !important; } body, html, img, video { margin: 0; padding: 0; width: 100vw; height: 100vh; object-fit: cover; background: black; overflow: hidden; } .vjs-control-bar, .vjs-big-play-button, button, header, footer, .controls, .play-button { display: none !important; }'; document.head.appendChild(s);";
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [vcamWebView.configuration.userContentController addUserScript:script];

    [parent insertSubview:vcamWebView atIndex:0];

    [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *t) {
        if (!enabled) return;
        [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
            if (img) snapshotForHijack = img;
        }];
    }];
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *p = (UIView *)self.delegate;
        if (!p || ![p isKindOfClass:[UIView class]]) p = (UIView *)self.superlayer.delegate;
        if (p && [p isKindOfClass:[UIView class]]) {
            setup_vcam_final_boss(p);
            vcamWebView.frame = p.bounds;
            [p sendSubviewToBack:vcamWebView];
            
            AVCaptureSession *s = self.session;
            BOOL isFront = NO;
            if (s) {
                for (id i in s.inputs) {
                    if ([i isKindOfClass:objc_getClass("AVCaptureDeviceInput")] && ((AVCaptureDeviceInput *)i).device.position == 2) { isFront = YES; break; }
                }
            }
            vcamWebView.transform = isFront ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
            [self setOpacity:0.0];
        }
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && snapshotForHijack) return UIImageJPEGRepresentation(snapshotForHijack, 0.95);
    return %orig;
}

- (struct CGImage *)CGImageRepresentation {
    if (enabled && snapshotForHijack) return snapshotForHijack.CGImage;
    return %orig;
}

- (struct CGImage *)previewCGImageRepresentation {
    if (enabled && snapshotForHijack) return snapshotForHijack.CGImage;
    return %orig;
}
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = p[@"rtspURL"];
    }
}