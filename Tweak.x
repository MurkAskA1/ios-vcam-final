// Tweak.x - VirtualCamPro V263.0: Deep Diagnostic Master
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <Photos/Photos.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UILabel *gHUD = nil;

@interface VCamEngine : WKWebView <WKNavigationDelegate>
@end

@implementation VCamEngine
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    self = [super initWithFrame:frame configuration:configuration];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.scrollView.backgroundColor = [UIColor blackColor];
        self.userInteractionEnabled = NO;
        self.navigationDelegate = self;
    }
    return self;
}

static void HUD(NSString *status, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gHUD) {
            gHUD.text = [NSString stringWithFormat:@"VCAM V263 | %@\nPROC: %@\nURL: %@\nSTAT: %@", 
                [[NSDate date] descriptionWithLocale:[NSLocale currentLocale]],
                [NSBundle mainBundle].bundleIdentifier, streamURL, status];
            gHUD.textColor = color;
        }
    });
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    HUD(@"CONNECTING...", [UIColor orangeColor]);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    HUD(@"STREAM ACTIVE", [UIColor greenColor]);
    [webView evaluateJavaScript:@"document.body.style.background = 'black';" completionHandler:nil];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    HUD([NSString stringWithFormat:@"NET ERROR: %@", error.localizedDescription], [UIColor redColor]);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    HUD([NSString stringWithFormat:@"LOAD ERROR: %@", error.localizedDescription], [UIColor redColor]);
}
@end

%hook NSBundle
- (NSDictionary *)infoDictionary {
    NSMutableDictionary *dict = [%orig mutableCopy];
    dict[@"NSAppTransportSecurity"] = @{ @"NSAllowsArbitraryLoads": @YES };
    return dict;
}
%end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.opacity = 0.0;
    
    UIView *container = (UIView *)self.delegate;
    if ([container isKindOfClass:[UIView class]]) {
        if (!gHUD) {
            gHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, container.bounds.size.width, 110)];
            gHUD.textAlignment = NSTextAlignmentCenter;
            gHUD.font = [UIFont fontWithName:@"Courier-Bold" size:11];
            gHUD.numberOfLines = 0;
            gHUD.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
            [container addSubview:gHUD];
        }
        [container bringSubviewToFront:gHUD];

        VCamEngine *engine = [container viewWithTag:8888];
        if (!engine) {
            WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
            config.allowsInlineMediaPlayback = YES;
            config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
            
            engine = [[VCamEngine alloc] initWithFrame:container.bounds configuration:config];
            engine.tag = 8888;
            [container insertSubview:engine atIndex:0];
            
            // Nuclear CSS Injection
            NSString *css = @"* { background: black !important; } "
                            "video, img { position: fixed !important; top: 0; left: 0; width: 100% !important; height: 100% !important; object-fit: cover !important; z-index: 999; } "
                            ".ui, .controls, button, span, .spinner { display: none !important; }";
            
            NSString *js = [NSString stringWithFormat:@"var s = document.createElement('style'); s.innerHTML = '%@'; document.head.appendChild(s);", css];
            WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
            [config.userContentController addUserScript:script];
            
            [engine loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];
        }
        engine.frame = container.bounds;
    }
}
%end

%ctor {
    NSLog(@"[VCam] V263 Diagnostics Loaded");
}
