// VCAM V146.0: The Chrome Direct - No HTML, No Wrappers, Just Stream
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *vcamWebView = nil;
static UIImage *snapshotForPhoto = nil;

static void setup_vcam_direct(UIView *parent) {
    if (!parent || (vcamWebView && vcamWebView.superview == parent)) return;
    if (vcamWebView) [vcamWebView removeFromSuperview];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    
    vcamWebView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamWebView.backgroundColor = [UIColor blackColor];
    vcamWebView.userInteractionEnabled = NO;
    vcamWebView.scrollView.scrollEnabled = NO;
    
    // Direct Load like Chrome (No <img> tag to avoid the question mark)
    NSURL *url = [NSURL URLWithString:streamURL];
    [vcamWebView loadRequest:[NSURLRequest requestWithURL:url]];

    [parent insertSubview:vcamWebView atIndex:0]; // Stay BEHIND buttons

    [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *t) {
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
            setup_vcam_direct(p);
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

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = p[@"rtspURL"];
    }
}