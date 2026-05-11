// VCAM V128.0: The Chrome Mirror - WKWebView Passthrough Engine
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIWindow *vcamWindow = nil;
static WKWebView *vcamWebView = nil;
static UIImage *snapshotForPhoto = nil;

@interface VCamPassthroughWindow : UIWindow @end
@implementation VCamPassthroughWindow
// Absolute touch passthrough: ignore all touches so they reach the app below
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
@end

@interface VCamRootVC : UIViewController @end
@implementation VCamRootVC
- (BOOL)prefersStatusBarHidden { return YES; }
@end

static void setup_web_mirror(void) {
    if (vcamWindow) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        vcamWindow = [[VCamPassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        vcamWindow.windowLevel = UIWindowLevelAlert + 5000;
        vcamWindow.userInteractionEnabled = NO;
        vcamWindow.backgroundColor = [UIColor clearColor];
        vcamWindow.rootViewController = [[VCamRootVC alloc] init];
        vcamWindow.hidden = NO;
        
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.allowsInlineMediaPlayback = YES;
        config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
        
        vcamWebView = [[WKWebView alloc] initWithFrame:vcamWindow.bounds configuration:config];
        vcamWebView.backgroundColor = [UIColor clearColor];
        vcamWebView.opaque = NO;
        vcamWebView.userInteractionEnabled = NO;
        vcamWebView.scrollView.scrollEnabled = NO;
        
        // Aggressive CSS to force fullscreen and hide all browser/player UI
        NSString *css = @"* { background: transparent !important; } "
                        "video { position: fixed !important; top: 0 !important; left: 0 !important; "
                        "width: 100vw !important; height: 100vh !important; object-fit: cover !important; } "
                        "button, .controls, .overlay, .play-button { display: none !important; }";
        WKUserScript *script = [[WKUserScript alloc] initWithSource:[NSString stringWithFormat:@"var s = document.createElement('style'); s.innerHTML = '%@'; document.head.appendChild(s);", css] injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
        [vcamWebView.configuration.userContentController addUserScript:script];
        
        [vcamWindow.rootViewController.view addSubview:vcamWebView];
        [vcamWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];
        
        // Continuous snapshotting for photo hijack
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
            [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
                if (img) snapshotForPhoto = img;
            }];
        }];
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        setup_web_mirror();
        vcamWindow.hidden = NO;
        
        // Front camera mirroring detection
        AVCaptureSession *s = nil;
        @try { s = [self session]; } @catch(id e) {}
        BOOL isFront = NO;
        if (s) {
            for (id input in [s inputs]) {
                if ([input isKindOfClass:objc_getClass("AVCaptureDeviceInput")]) {
                    if (((AVCaptureDeviceInput *)input).device.position == 2) { isFront = YES; break; }
                }
            }
        }
        vcamWebView.transform = isFront ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
        [self setOpacity:0.01];
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (enabled && snapshotForPhoto) objc_setAssociatedObject(s, "vcamS", snapshotForPhoto, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    UIImage *snap = objc_getAssociatedObject([self resolvedSettings], "vcamS");
    if (snap) return UIImageJPEGRepresentation(snap, 0.95);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation {
    UIImage *snap = objc_getAssociatedObject([self resolvedSettings], "vcamS");
    if (snap) return snap.CGImage;
    return %orig;
}
%end

%hook AVCaptureSession
- (void)stopRunning { %orig; if (vcamWindow) vcamWindow.hidden = YES; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = [p[@"rtspURL"] stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
    }
}
