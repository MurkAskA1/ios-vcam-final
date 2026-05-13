// VirtualCamPro V241.0: The Final Absolute Sovereign
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *globalVcamView = nil;
static UIImage *globalLastSnapshot = nil;

static void load_prefs() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
    if (prefs) {
        enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        NSString *u = prefs[@"rtspURL"];
        if (u && u.length > 5) streamURL = u;
    }
}

// Global App Transport Security Bypass
%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"NSAppTransportSecurity"]) {
        return @{ @"NSAllowsArbitraryLoads": @YES, @"NSAllowsLocalNetworking": @YES };
    }
    return %orig;
}
%end

static void inject_vcam(UIView *parent) {
    if (!parent || !enabled) return;
    
    // Prevent duplicate injection
    if (globalVcamView && globalVcamView.superview == parent) {
        [parent sendSubviewToBack:globalVcamView];
        return;
    }
    
    if (globalVcamView) [globalVcamView removeFromSuperview];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;

    // Nuclear UI Wiper: Hide all player controls, live badges, and white backgrounds
    NSString *js = @"let s = document.createElement('style');" 
                    "s.innerHTML = 'body, html { background: black !important; margin: 0; padding: 0; overflow: hidden; width: 100%; height: 100%; } " 
                    "video, img { width: 100vw !important; height: 100vh !important; object-fit: cover !important; position: absolute; top:0; left:0; pointer-events: none !important; } " 
                    "* { -webkit-tap-highlight-color: transparent !important; outline: none !important; } " 
                    ".vjs-control-bar, .vjs-big-play-button, .live-badge, .player-controls { display: none !important; }';" 
                    "document.head.appendChild(s);" 
                    "setInterval(() => { " 
                    "  let v = document.querySelector('video'); " 
                    "  if(v) { v.controls = false; v.removeAttribute('controls'); if(v.paused) v.play().catch(e=>{}); } " 
                    "}, 500);";

    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [config.userContentController addUserScript:script];

    globalVcamView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    globalVcamView.backgroundColor = [UIColor blackColor];
    globalVcamView.scrollView.backgroundColor = [UIColor blackColor];
    globalVcamView.opaque = YES;
    globalVcamView.userInteractionEnabled = NO;
    globalVcamView.scrollView.scrollEnabled = NO;

    // Load the stream directly as it's the most reliable for MediaMTX
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:streamURL] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
    [globalVcamView loadRequest:req];

    [parent insertSubview:globalVcamView atIndex:0];
    
    // Start snapshot loop for gallery/photo hijack
    [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        if (globalVcamView) {
            [globalVcamView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
                if (img) globalLastSnapshot = img;
            }];
        }
    }];
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        self.opacity = 0.0; // Hide real camera output
        UIView *target = (UIView *)self.delegate;
        if ([target isKindOfClass:[UIView class]]) {
            inject_vcam(target);
            globalVcamView.frame = target.bounds;
        }
    }
}
%end

// Anti-KYC Device Masking
%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (BOOL)isVirtualDevice { return NO; }
%end

// Hijack saved photos
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && globalLastSnapshot) return UIImageJPEGRepresentation(globalLastSnapshot, 0.9);
    return %orig;
}
%end

// Hijack camera thumbnail well
%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && globalLastSnapshot) %orig(globalLastSnapshot);
    else %orig(image);
}
%end

%ctor {
    load_prefs();
}
