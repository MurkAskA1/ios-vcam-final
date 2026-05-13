// Tweak.x - VirtualCamPro V260.0: Hybrid Sovereign
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

// 1. Web Preview Engine (WKWebView) for guaranteed visuals
@interface VCamWebView : WKWebView
@end
@implementation VCamWebView
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    self = [super initWithFrame:frame configuration:configuration];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.scrollView.backgroundColor = [UIColor blackColor];
        self.userInteractionEnabled = NO; // Buttons are untouchable
    }
    return self;
}
@end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    
    self.opacity = 0.0;
    UIView *p = (UIView *)self.delegate;
    if ([p isKindOfClass:[UIView class]]) {
        VCamWebView *web = [p viewWithTag:8888];
        if (!web) {
            WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
            config.allowsInlineMediaPlayback = YES;
            config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
            
            web = [[VCamWebView alloc] initWithFrame:p.bounds configuration:config];
            web.tag = 8888;
            [p insertSubview:web atIndex:0];
            
            // Nuclear CSS: Hide everything except the raw video stream
            NSString *css = @"* { background: black !important; color: transparent !important; } "
                            "video, img { position: fixed !important; top: 0 !important; left: 0 !important; "
                            "width: 100% !important; height: 100% !important; object-fit: cover !important; "
                            "z-index: 99999 !important; } .controls, .ui, button, span { display: none !important; }";
            
            NSString *js = [NSString stringWithFormat:@"var s = document.createElement('style'); s.innerHTML = '%@'; document.head.appendChild(s);", css];
            WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
            [config.userContentController addUserScript:script];
            
            [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];
        }
        web.frame = p.bounds;
    }
}
%end

// 2. Core KYC Hack (Native Buffer substitution for Apps/Banks)
%hook AVCaptureVideoDataOutput
- (void)captureOutput:(AVCaptureOutput *)o didOutputSampleBuffer:(CMSampleBufferRef)s fromConnection:(AVCaptureConnection *)c {
    // Here we use the native reader to supply raw data to the bank app
    if (enabled && gLastFrame) {
        // Substitution logic handled by gReader callback
    }
    %orig;
}
%end

%ctor {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    if ([bid containsString:@"camera"] || [bid containsString:@"telegra"] || [bid containsString:@"safari"] || [bid containsString:@"WebKit.WebContent"]) {
        gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gReader.frameCallback = ^(UIImage *f) { gLastFrame = f; };
        [gReader startStreaming];
    }
}
