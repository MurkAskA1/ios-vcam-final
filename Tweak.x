// VCAM V130.0: The KYC Stealth Pro - Absolute UI Clean & Deep Hijack
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *vcamWebView = nil;
static UIImage *lastGlobalSnap = nil;

@interface VCamSnapshoter : NSObject @end
@implementation VCamSnapshoter
+ (void)syncSnap {
    if (!vcamWebView) return;
    [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
        if (img) lastGlobalSnap = img;
    }];
}
@end

static void setup_stealth_engine(UIView *parent) {
    if (!parent || (vcamWebView && vcamWebView.superview == parent)) return;
    if (vcamWebView) [vcamWebView removeFromSuperview];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    vcamWebView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamWebView.backgroundColor = [UIColor blackColor];
    vcamWebView.userInteractionEnabled = NO;
    vcamWebView.scrollView.scrollEnabled = NO;
    
    // Nuclear CSS/JS to hide ALL player UI forever
    NSString *js = @"var style = document.createElement('style'); "
                    "style.innerHTML = '* { -webkit-tap-highlight-color: transparent !important; } "
                    "video { width: 100vw !important; height: 100vh !important; object-fit: cover !important; pointer-events: none !important; } "
                    "button, .controls, .video-controls, .overlay, .play-button, .skip-button, .timer { display: none !important; opacity: 0 !important; visibility: hidden !important; }'; "
                    "document.head.appendChild(style); "
                    "setInterval(function() { var v = document.querySelector('video'); if(v) { v.play(); v.controls = false; } }, 100);";
    
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [vcamWebView.configuration.userContentController addUserScript:script];
    
    [parent insertSubview:vcamWebView atIndex:0];
    [vcamWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];
    
    [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *t) { [VCamSnapshoter syncSnap]; }];
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *p = (UIView *)self.delegate;
        if (!p || ![p isKindOfClass:[UIView class]]) {
             p = (UIView *)self.superlayer.delegate;
        }
        if (p && [p isKindOfClass:[UIView class]]) {
            setup_stealth_engine(p);
            vcamWebView.frame = p.bounds;
            AVCaptureSession *s = self.session; BOOL f = NO;
            if (s) {
                for (id i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == 2) { f = YES; break; } }
            }
            vcamWebView.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
            [self setOpacity:0.0];
        }
    }
}
%end

// REDESIGNED PHOTO HIJACK: Directly override the image data representation
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && lastGlobalSnap) {
        return UIImageJPEGRepresentation(lastGlobalSnap, 0.95);
    }
    return %orig;
}

- (struct CGImage *)CGImageRepresentation {
    if (enabled && lastGlobalSnap) {
        return lastGlobalSnap.CGImage;
    }
    return %orig;
}

- (struct __CVBuffer *)pixelBuffer {
    return %orig; // Fallback to avoid crashes, mostly used for video
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(id)s delegate:(id)d { %orig; }
%end

%hook AVCaptureSession
- (void)startRunning { %orig; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = [p[@"rtspURL"] stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
    }
}
