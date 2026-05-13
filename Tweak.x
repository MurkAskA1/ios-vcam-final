// Tweak.x - VirtualCamPro V262.0: Forensic HUD
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UILabel *gHUD = nil;

// 1. System-wide ATS Bypass to allow local HTTP
%hook NSBundle
- (NSDictionary *)infoDictionary {
    NSMutableDictionary *dict = [%orig mutableCopy];
    dict[@"NSAppTransportSecurity"] = @{ @"NSAllowsArbitraryLoads": @YES };
    return dict;
}
%end

static void UpdateHUD(UIView *host, NSString *status, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gHUD) {
            gHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, host.bounds.size.width, 100)];
            gHUD.textAlignment = NSTextAlignmentCenter;
            gHUD.font = [UIFont fontWithName:@"Courier-Bold" size:12];
            gHUD.textColor = [UIColor whiteColor];
            gHUD.numberOfLines = 0;
            gHUD.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
            [host addSubview:gHUD];
        }
        gHUD.text = [NSString stringWithFormat:@"V262 DIAGNOSTIC HUD\nPROCESS: %@\nURL: %@\nSTATUS: %@", 
            [NSBundle mainBundle].bundleIdentifier, streamURL, status];
        gHUD.textColor = color;
        [host bringSubviewToFront:gHUD];
    });
}

@interface VCamWeb : WKWebView
@end
@implementation VCamWeb
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    self = [super initWithFrame:frame configuration:configuration];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.scrollView.backgroundColor = [UIColor blackColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}
@end

// 2. Visual Substitution Hook
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    
    self.opacity = 0.0; // Hide real lens
    UIView *container = (UIView *)self.delegate;
    if ([container isKindOfClass:[UIView class]]) {
        VCamWeb *web = [container viewWithTag:8888];
        if (!web) {
            WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
            config.allowsInlineMediaPlayback = YES;
            config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
            
            web = [[VCamWeb alloc] initWithFrame:container.bounds configuration:config];
            web.tag = 8888;
            [container insertSubview:web atIndex:0];
            
            // Nuclear CSS: Force raw video and hide all MediaMTX UI
            NSString *css = @"* { background: black !important; } "
                            "video, img { position: fixed !important; top: 0; left: 0; width: 100% !important; height: 100% !important; object-fit: cover !important; } "
                            ".ui, .controls, button, span, .spinner { display: none !important; }";
            
            NSString *js = [NSString stringWithFormat:@"var s = document.createElement('style'); s.innerHTML = '%@'; document.head.appendChild(s);", css];
            WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
            [config.userContentController addUserScript:script];
            
            [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];
            UpdateHUD(container, @"WEB ENGINE STARTED", [UIColor yellowColor]);
        }
        web.frame = container.bounds;
        if (web.isLoading) {
             UpdateHUD(container, @"LOADING STREAM...", [UIColor orangeColor]);
        } else {
             UpdateHUD(container, @"ENGINE ACTIVE", [UIColor greenColor]);
        }
    }
}
%end

// 3. Absolute Photo Hijack (Placeholder while engine active)
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation { return %orig; }
%end

%ctor {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    // Force injection into core apps
    if ([bid containsString:@"camera"] || [bid containsString:@"telegra"] || [bid containsString:@"safari"]) {
        NSLog(@"[VCam] Sovereign Hybrid loaded in %@", bid);
    }
}
