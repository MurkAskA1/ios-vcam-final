// Tweak.x - VirtualCamPro V271.0: The Hybrid Sovereign
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;

// 1. Force ATS Bypass for all processes
%hook NSBundle
- (NSDictionary *)infoDictionary {
    NSMutableDictionary *dict = [%orig mutableCopy];
    dict[@"NSAppTransportSecurity"] = @{ @"NSAllowsArbitraryLoads": @YES };
    return dict;
}
%end

// 2. Hybrid Visual Engine: WKWebView for guaranteed stream connection
@interface VCamWebView : WKWebView
@end
@implementation VCamWebView
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

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    
    self.opacity = 0.0;
    UIView *container = (UIView *)self.delegate;
    if ([container isKindOfClass:[UIView class]]) {
        VCamWebView *web = [container viewWithTag:8888];
        if (!web) {
            WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
            config.allowsInlineMediaPlayback = YES;
            config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
            
            web = [[VCamWebView alloc] initWithFrame:container.bounds configuration:config];
            web.tag = 8888;
            [container insertSubview:web atIndex:0];
            
            // Nuclear CSS: Raw stream only, no MediaMTX UI
            NSString *css = @"* { background: black !important; } "
                            "video, img { position: fixed !important; top: 0; left: 0; width: 100% !important; height: 100% !important; object-fit: cover !important; z-index: 9999 !important; } "
                            ".ui, .controls, button, span { display: none !important; }";
            
            NSString *js = [NSString stringWithFormat:@"var s = document.createElement('style'); s.innerHTML = '%@'; document.head.appendChild(s);", css];
            WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
            [config.userContentController addUserScript:script];
            
            [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];
        }
        web.frame = container.bounds;
        
        // On-screen Diagnostic Label
        UILabel *status = [container viewWithTag:7777];
        if (!status) {
            status = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, container.bounds.size.width, 60)];
            status.tag = 7777;
            status.textAlignment = NSTextAlignmentCenter;
            status.font = [UIFont boldSystemFontOfSize:12];
            status.textColor = [UIColor whiteColor];
            status.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
            status.numberOfLines = 0;
            [container addSubview:status];
        }
        status.text = [NSString stringWithFormat:@"V271 HYBRID ACTIVE\nURL: %@\nBUFFER: %@", streamURL, (gLastFrame ? @"READY" : @"EMPTY")];
        [container bringSubviewToFront:status];
    }
}
%end

// 3. Absolute Photo Hijack (For Gallery & KYC)
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && gLastFrame) return UIImageJPEGRepresentation(gLastFrame, 0.95);
    return %orig;
}
- (CGImageRef)CGImageRepresentation {
    if (enabled && gLastFrame) return gLastFrame.CGImage;
    return %orig;
}
%end

%ctor {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    if ([bid containsString:@"camera"] || [bid containsString:@"telegra"] || [bid containsString:@"safari"] || [bid containsString:@"chrome"] || [bid containsString:@"WebKit"]) {
        // Background reader for KYC data hijacking
        gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gReader.frameCallback = ^(UIImage *f) { gLastFrame = f; };
        [gReader startStreaming];
    }
}
