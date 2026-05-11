// VCAM V134.0: The Chrome-Hybrid Engine - Absolute Stealth & Total Hijack
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIWindow *vcamWindow = nil;
static WKWebView *vcamWebView = nil;
static UIImage *lastSnapV = nil;

@interface VCamPassthroughWindow : UIWindow @end
@implementation VCamPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; } // All touches go to camera app below
@end

@interface VCamRootVC : UIViewController @end
@implementation VCamRootVC
- (BOOL)prefersStatusBarHidden { return YES; }
@end

static void setup_chrome_hybrid(void) {
    if (vcamWindow) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        vcamWindow = [[VCamPassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        vcamWindow.windowLevel = UIWindowLevelAlert + 5000;
        vcamWindow.userInteractionEnabled = NO;
        vcamWindow.backgroundColor = [UIColor blackColor];
        vcamWindow.rootViewController = [[VCamRootVC alloc] init];
        vcamWindow.hidden = NO;
        
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        vcamWebView = [[WKWebView alloc] initWithFrame:vcamWindow.bounds configuration:config];
        vcamWebView.backgroundColor = [UIColor blackColor];
        vcamWebView.opaque = YES;
        vcamWebView.userInteractionEnabled = NO;
        vcamWebView.scrollView.scrollEnabled = NO;
        
        // The "Chrome Trick": Using <img> instead of <video> to avoid all player UI elements (pause buttons)
        NSString *html = [NSString stringWithFormat:@"<html><body style='margin:0;padding:0;background:black;'><img src='%@' style='width:100vw;height:100vh;object-fit:cover;'></body></html>", streamURL];
        [vcamWebView loadHTMLString:html baseURL:nil];
        
        [vcamWindow.rootViewController.view addSubview:vcamWebView];
        
        [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *t) {
            [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
                if (img) lastSnapV = img;
            }];
        }];
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        setup_chrome_hybrid();
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

// TOTAL HIJACK: Overriding every possible output for main photo and thumbnails
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && lastSnapV) return UIImageJPEGRepresentation(lastSnapV, 0.95);
    return %orig;
}

- (struct CGImage *)CGImageRepresentation {
    if (enabled && lastSnapV) return lastSnapV.CGImage;
    return %orig;
}

- (struct CGImage *)previewCGImageRepresentation {
    if (enabled && lastSnapV) return lastSnapV.CGImage;
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
