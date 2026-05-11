// VCAM V136.0: The Backstage Engine - Direct View Injection & No UI Image Trick
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *vcamWebView = nil;
static UIImage *lastGlobalSnap = nil;

static void setup_backstage_engine(UIView *parent) {
    if (!parent || (vcamWebView && vcamWebView.superview == parent)) return;
    if (vcamWebView) [vcamWebView removeFromSuperview];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    
    vcamWebView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamWebView.backgroundColor = [UIColor blackColor];
    vcamWebView.userInteractionEnabled = NO;
    vcamWebView.scrollView.scrollEnabled = NO;
    
    // Using <img> tag trick to avoid ANY video player UI (no pause buttons, etc.)
    NSString *html = [NSString stringWithFormat:@"<html><body style='margin:0;padding:0;background:black;overflow:hidden;'><img src='%@' style='width:100vw;height:100vh;object-fit:cover;'></body></html>", streamURL];
    [vcamWebView loadHTMLString:html baseURL:nil];
    
    // Insert as the VERY FIRST subview to stay BEHIND all camera buttons
    [parent insertSubview:vcamWebView atIndex:0];
    
    [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *t) {
        [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
            if (img) lastGlobalSnap = img;
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
            setup_backstage_engine(p);
            vcamWebView.frame = p.bounds;
            [p sendSubviewToBack:vcamWebView]; // Extra safety for buttons
            
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

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && lastGlobalSnap) return UIImageJPEGRepresentation(lastGlobalSnap, 0.95);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation { if (enabled && lastGlobalSnap) return lastGlobalSnap.CGImage; return %orig; }
- (struct CGImage *)previewCGImageRepresentation { if (enabled && lastGlobalSnap) return lastGlobalSnap.CGImage; return %orig; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = [p[@"rtspURL"] stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
    }
}
