// VirtualCamPro V239.0: The True Engine Fix
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
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
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
    
    // Inject JS to force black background, remove MediaMTX player UI, and auto-play WebRTC videos or MJPEG images
    WKUserContentController *userContent = [[WKUserContentController alloc] init];
    NSString *js = @"let style = document.createElement('style');" 
                   "style.innerHTML = 'body { background: black !important; margin: 0 !important; overflow: hidden !important; } " 
                   "video, img { width: 100vw !important; height: 100vh !important; object-fit: cover !important; position: absolute !important; top: 0 !important; left: 0 !important; pointer-events: none !important; } " 
                   "*:not(video):not(img):not(body):not(html):not(style) { display: none !important; }';" 
                   "document.head.appendChild(style);" 
                   "let v = document.querySelector('video');" 
                   "if (v) {" 
                   "  v.removeAttribute('controls'); v.controls = false; v.muted = true;" 
                   "  v.setAttribute('playsinline', 'playsinline');" 
                   "  v.play().catch(e=>{});" 
                   "  setInterval(() => { v.removeAttribute('controls'); v.controls = false; if(v.paused) v.play(); }, 500);" 
                   "}";
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [userContent addUserScript:script];
    config.userContentController = userContent;

    globalVcamView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    globalVcamView.backgroundColor = [UIColor blackColor];
    globalVcamView.scrollView.backgroundColor = [UIColor blackColor];
    globalVcamView.opaque = YES;
    globalVcamView.userInteractionEnabled = NO;
    globalVcamView.scrollView.scrollEnabled = NO;

    // Directly load the URL. MediaMTX WebRTC page or raw MJPEG will be formatted perfectly by the injected JS.
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:streamURL] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
    [globalVcamView loadRequest:req];
    
    [parent insertSubview:globalVcamView atIndex:0];
    
    start_frame_capture();
}

// Ensure it attaches to the preview layer robustly
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        self.opacity = 0.0; // Hide the real camera output
        
        UIView *target = nil;
        CALayer *layer = self;
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
