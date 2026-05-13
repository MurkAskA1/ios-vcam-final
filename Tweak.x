// VirtualCamPro V238.0: The Visible Phantom Fix
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *globalVcamView = nil;
static UIImage *globalLastImage = nil;

// Global ATS bypass for any app
%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"NSAppTransportSecurity"]) {
        return @{ 
            @"NSAllowsArbitraryLoads": @YES, 
            @"NSAllowsArbitraryLoadsInWebContent": @YES, 
            @"NSAllowsLocalNetworking": @YES 
        };
    }
    return %orig;
}
%end

static void load_vcam_prefs() {
    NSArray *paths = @[@"/var/jb/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist",
                       @"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d) {
            enabled = [d[@"enabled"] ?: @YES boolValue];
            NSString *u = d[@"rtspURL"];
            if (u && u.length > 5) streamURL = u;
            break;
        }
    }
}

static void start_frame_capture() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t) {
            if (enabled && globalVcamView) {
                [globalVcamView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
                    if (img) globalLastImage = img;
                }];
            }
        }];
    });
}

static void inject_vcam_sovereign(UIView *parent) {
    if (!parent || !enabled) return;
    
    if (globalVcamView && globalVcamView.superview == parent) {
        [parent sendSubviewToBack:globalVcamView];
        return;
    }

    if (globalVcamView) [globalVcamView removeFromSuperview];

    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    globalVcamView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    globalVcamView.backgroundColor = [UIColor blackColor];
    globalVcamView.scrollView.backgroundColor = [UIColor blackColor];
    globalVcamView.opaque = YES;
    globalVcamView.userInteractionEnabled = NO;
    globalVcamView.scrollView.scrollEnabled = NO;

    NSString *html = [NSString stringWithFormat:@"<html><body style=\"margin:0;padding:0;background:black;overflow:hidden;\"><img src=\"%@\" style=\"width:100vw;height:100vh;object-fit:cover;\" /></body></html>", streamURL];
    [globalVcamView loadHTMLString:html baseURL:[NSURL URLWithString:streamURL]];
    
    [parent insertSubview:globalVcamView atIndex:0];
    
    start_frame_capture();
}

// Ensure it attaches to the preview layer robustly
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        // HIDE THE REAL CAMERA FEED so it doesn't overlap our stream
        self.opacity = 0.0;
        
        UIView *target = nil;
        CALayer *layer = self;
        // Traverse up the layer tree to find the hosting UIView
        while (layer) {
            if ([layer.delegate isKindOfClass:[UIView class]]) {
                target = (UIView *)layer.delegate;
                break;
            }
            layer = layer.superlayer;
        }

        if (target) {
            inject_vcam_sovereign(target);
            globalVcamView.frame = target.bounds;
        }
    }
}
%end

// Anti-KYC Device Identity Hook
%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
- (BOOL)isVirtualDevice { return NO; }
%end

// Hijack the saved photo
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && globalLastImage) return UIImageJPEGRepresentation(globalLastImage, 0.95);
    return %orig;
}
- (CGImageRef)CGImageRepresentation {
    if (enabled && globalLastImage) return [globalLastImage CGImage];
    return %orig;
}
%end

// Hijack the gallery thumbnail well
%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && globalLastImage) %orig(globalLastImage);
    else %orig;
}
%end

%ctor {
    load_vcam_prefs();
}
