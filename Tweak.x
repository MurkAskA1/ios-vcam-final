// VCAM V137.0: The Pro Master - Direct Engine & Button Preservation
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static WKWebView *vcamWebView = nil;
static UIImage *snapshotForPhoto = nil;

static void setup_pro_engine(UIView *parent) {
    if (!parent || (vcamWebView && vcamWebView.superview == parent)) return;
    if (vcamWebView) [vcamWebView removeFromSuperview];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    vcamWebView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamWebView.backgroundColor = [UIColor blackColor];
    vcamWebView.opaque = YES;
    vcamWebView.userInteractionEnabled = NO;
    vcamWebView.scrollView.scrollEnabled = NO;
    
    // BRUTAL JAVASCRIPT: Kill all UI, Auto-Play, and Force Fullscreen every 100ms
    NSString *js = @"setInterval(function() { "
                    "var v = document.querySelector('video'); if(v) { v.play(); v.controls = false; v.style.width='100vw'; v.style.height='100vh'; v.style.objectFit='cover'; v.style.position='fixed'; v.style.top='0'; v.style.left='0'; } "
                    "var ui = document.querySelectorAll('button, .controls, .overlay, .ytp-chrome-bottom'); "
                    "for(var i=0; i<ui.length; i++) { ui[i].style.display='none'; ui[i].style.opacity='0'; } "
                    "}, 100);";
    
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [vcamWebView.configuration.userContentController addUserScript:script];
    
    // Logic: Insert at index 0 (Background) and hide the real camera layer
    [parent insertSubview:vcamWebView atIndex:0];
    [vcamWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];
    
    [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
            if (img) snapshotForPhoto = img;
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
            setup_pro_engine(p);
            vcamWebView.frame = p.bounds;
            [p sendSubviewToBack:vcamWebView]; // Ensure it stays behind buttons
            
            AVCaptureSession *s = self.session; BOOL f = NO;
            if (s) {
                for (id i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == 2) { f = YES; break; } }
            }
            vcamWebView.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
            [self setOpacity:0.0]; // Hide real lens feed
        }
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && snapshotForPhoto) return UIImageJPEGRepresentation(snapshotForPhoto, 0.95);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation { if (enabled && snapshotForPhoto) return snapshotForPhoto.CGImage; return %orig; }
- (struct CGImage *)previewCGImageRepresentation { if (enabled && snapshotForPhoto) return snapshotForPhoto.CGImage; return %orig; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = p[@"rtspURL"];
    }
}
