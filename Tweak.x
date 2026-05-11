// VCAM V120.0: The Invisible Ghost - Touch Passthrough & Clean Web UI
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
// Allow touches to pass through to the camera app underneath
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view) return nil;
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
        vcamWindow = [[VCamPassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        vcamWindow.windowLevel = UIWindowLevelAlert + 5000;
        vcamWindow.userInteractionEnabled = YES; // Window itself accepts touches to pass them
        vcamWindow.backgroundColor = [UIColor clearColor];
        vcamWindow.rootViewController = [[VCamRootVC alloc] init];
        vcamWindow.hidden = NO;
        
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.allowsInlineMediaPlayback = YES;
        config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
        
        vcamWebView = [[WKWebView alloc] initWithFrame:vcamWindow.bounds configuration:config];
        vcamWebView.backgroundColor = [UIColor clearColor];
        vcamWebView.opaque = NO;
        vcamWebView.userInteractionEnabled = NO; // Webview won't steal touches from Shutter button
        vcamWebView.scrollView.scrollEnabled = NO;
        
        // Inject CSS to hide all video controls and force fullscreen
        NSString *css = @"video { width: 100vw !important; height: 100vh !important; object-fit: cover !important; } .controls, button, .overlay { display: none !important; }";
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
        vcamWindow.hidden = NO;
        AVCaptureSession *s = [self session]; BOOL f = NO;
        if (s) {
            for (AVCaptureInput *i in [s inputs]) {
                if ([i isKindOfClass:[AVCaptureDeviceInput class]]) {
                    if (((AVCaptureDeviceInput *)i).device.position == 2) { f = YES; break; }
                }
            }
        }
        vcamWebView.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
        [self setOpacity:0.01]; // Hide real lens
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
