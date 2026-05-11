// VCAM V135.0: Direct Link Master - Pure Stream Engine Restoration
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
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
@end

@interface VCamRootVC : UIViewController @end
@implementation VCamRootVC
- (BOOL)prefersStatusBarHidden { return YES; }
@end

static void setup_direct_engine(void) {
    if (vcamWindow) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        vcamWindow = [[VCamPassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        vcamWindow.windowLevel = UIWindowLevelAlert + 5000;
        vcamWindow.userInteractionEnabled = NO;
        vcamWindow.backgroundColor = [UIColor blackColor];
        vcamWindow.rootViewController = [[VCamRootVC alloc] init];
        vcamWindow.hidden = NO;
        
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.allowsInlineMediaPlayback = YES;
        config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
        
        vcamWebView = [[WKWebView alloc] initWithFrame:vcamWindow.bounds configuration:config];
        vcamWebView.backgroundColor = [UIColor blackColor];
        vcamWebView.opaque = YES;
        vcamWebView.userInteractionEnabled = NO;
        vcamWebView.scrollView.scrollEnabled = NO;
        
        // Direct Load: Use the exact URL from settings without any HTML wrapping
        [vcamWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];
        
        // Aggressive UI Hiding via JavaScript loop
        NSString *js = @"setInterval(function() { "
                        "var v = document.querySelector('video'); if(v) { v.play(); v.controls = false; v.style.width='100vw'; v.style.height='100vh'; v.style.objectFit='cover'; } "
                        "var items = document.querySelectorAll('button, .controls, .overlay'); for(var i=0; i<items.length; i++) { items[i].style.display='none'; } "
                        "}, 100);";
        WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
        [vcamWebView.configuration.userContentController addUserScript:script];
        
        [vcamWindow.rootViewController.view addSubview:vcamWebView];
        
        [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *t) {
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
        setup_direct_engine();
        vcamWindow.hidden = NO;
        AVCaptureSession *s = nil; @try { s = [self session]; } @catch(id e) {}
        BOOL f = NO;
        if (s) {
            for (id i in [s inputs]) {
                if ([i isKindOfClass:objc_getClass("AVCaptureDeviceInput")]) {
                    if (((AVCaptureDeviceInput *)i).device.position == 2) { f = YES; break; }
                }
            }
        }
        vcamWebView.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
        [self setOpacity:0.0];
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && snapshotForPhoto) return UIImageJPEGRepresentation(snapshotForPhoto, 0.95);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation {
    if (enabled && snapshotForPhoto) return snapshotForPhoto.CGImage;
    return %orig;
}
- (struct CGImage *)previewCGImageRepresentation {
    if (enabled && snapshotForPhoto) return snapshotForPhoto.CGImage;
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
        if (p[@"rtspURL"]) streamURL = p[@"rtspURL"];
    }
}
