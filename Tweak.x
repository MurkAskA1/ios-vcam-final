// VCAM V121.0: The Stealth Master - Crash Fix & Absolute Clean UI
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
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    // If the hit view is our webview or window, return nil so touch goes to the app below
    if (hitView == self || [hitView isDescendantOfView:self.rootViewController.view]) return nil;
    return hitView;
}
@end

@interface VCamRootVC : UIViewController @end
@implementation VCamRootVC
- (BOOL)prefersStatusBarHidden { return YES; }
@end

static void setup_web_engine(void) {
    if (vcamWindow) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (vcamWindow) return;
        
        vcamWindow = [[VCamPassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        vcamWindow.windowLevel = UIWindowLevelAlert + 5000;
        vcamWindow.userInteractionEnabled = YES;
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
        
        // IMPROVED CSS: Nuclear option to hide ALL player UI elements
        NSString *css = @"* { -webkit-tap-highlight-color: transparent !important; } "
                        "video { width: 100vw !important; height: 100vh !important; object-fit: cover !important; pointer-events: none !important; } "
                        "button, .controls, .video-controls, .overlay, .play-button, .skip-button, .timer { display: none !important; opacity: 0 !important; visibility: hidden !important; }";
        
        WKUserScript *script = [[WKUserScript alloc] initWithSource:[NSString stringWithFormat:@"var style = document.createElement('style'); style.innerHTML = '%@'; document.head.appendChild(style);", css] injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
        [vcamWebView.configuration.userContentController addUserScript:script];
        
        [vcamWindow.rootViewController.view addSubview:vcamWebView];
        [vcamWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];
        
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
            WKSnapshotConfiguration *sc = [[WKSnapshotConfiguration alloc] init];
            [vcamWebView takeSnapshotWithConfiguration:sc completionHandler:^(UIImage *img, NSError *err) {
                if (img) snapshotForPhoto = img;
            }];
        }];
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        setup_web_engine();
        if (vcamWindow) vcamWindow.hidden = NO;
        
        // Safe session check to prevent crashes in apps like Telegram
        AVCaptureSession *s = nil;
        @try {
            s = [self session];
        } @catch (NSException *e) {}

        if (s && vcamWebView) {
            BOOL f = NO;
            for (AVCaptureInput *i in [s inputs]) {
                if ([i isKindOfClass:objc_getClass("AVCaptureDeviceInput")]) {
                    if (((AVCaptureDeviceInput *)i).device.position == 2) { f = YES; break; }
                }
            }
            vcamWebView.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
        }
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
- (void)stopRunning {
    %orig;
    if (vcamWindow) vcamWindow.hidden = YES;
}
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = [p[@"rtspURL"] stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
    }
}
