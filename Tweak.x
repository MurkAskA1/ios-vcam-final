// Tweak.x - VirtualCamPro V264.0: Bulletproof Diagnostics
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIWindow *gDiagWindow = nil;
static UITextView *gLogView = nil;

static void HUDLog(NSString *msg) {
    NSLog(@"[VCam] %@", msg);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gLogView) {
            gLogView.text = [gLogView.text stringByAppendingFormat:@"\n[%@] %@", [NSDate date], msg];
            [gLogView scrollRangeToVisible:NSMakeRange(gLogView.text.length - 1, 1)];
        }
    });
    
    // Force write to Filza-readable log
    FILE *f = fopen("/var/mobile/Documents/vcam_debug.log", "a");
    if (f) {
        fprintf(f, "[%s] %s\n", [[NSDate date].description UTF8String], [msg UTF8String]);
        fclose(f);
    }
}

@interface VCamEngine : WKWebView <WKNavigationDelegate>
@end
@implementation VCamEngine
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation { HUDLog(@"[Web] Connecting..."); }
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation { HUDLog(@"[Web] Stream Loaded (Active)"); }
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error { HUDLog([NSString stringWithFormat:@"[Web] Net Error: %@", error.localizedDescription]); }
@end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.opacity = 0.0;
    
    UIView *p = (UIView *)self.delegate;
    if ([p isKindOfClass:[UIView class]]) {
        VCamEngine *web = [p viewWithTag:8888];
        if (!web) {
            HUDLog(@"Creating Web Engine layer...");
            WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
            config.allowsInlineMediaPlayback = YES;
            config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
            
            web = [[VCamEngine alloc] initWithFrame:p.bounds configuration:config];
            web.tag = 8888;
            web.navigationDelegate = web;
            web.backgroundColor = [UIColor blackColor];
            [p insertSubview:web atIndex:0];
            
            [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];
        }
        web.frame = p.bounds;
    }
}
%end

%ctor {
    // Create a global overlay window that cannot be hidden by the app
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gDiagWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 180)];
        gDiagWindow.windowLevel = UIWindowLevelStatusBar + 100;
        gDiagWindow.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        gDiagWindow.userInteractionEnabled = NO;
        
        gLogView = [[UITextView alloc] initWithFrame:gDiagWindow.bounds];
        gLogView.backgroundColor = [UIColor clearColor];
        gLogView.textColor = [UIColor cyanColor];
        gLogView.font = [UIFont fontWithName:@"Courier" size:10];
        gLogView.text = @"--- VCAM V264 BULLETPROOF LOG ---";
        
        [gDiagWindow addSubview:gLogView];
        [gDiagWindow makeKeyAndVisible];
        gDiagWindow.hidden = NO;
        
        HUDLog([NSString stringWithFormat:@"Process: %@", [NSBundle mainBundle].bundleIdentifier]);
        HUDLog([NSString stringWithFormat:@"Target URL: %@", streamURL]);
    });
}
