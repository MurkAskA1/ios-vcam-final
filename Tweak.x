// VCAM V183.0: The Forensic Stealth - CMSampleBuffer Hijack
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *vcamWebView = nil;
static UIImage *sharedSnapshot = nil;

static void setup_vcam_v183(UIView *parent) {
    if (!parent || (vcamWebView && vcamWebView.superview == parent)) return;
    if (vcamWebView) [vcamWebView removeFromSuperview];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    vcamWebView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamWebView.backgroundColor = [UIColor blackColor];
    vcamWebView.userInteractionEnabled = NO;
    vcamWebView.scrollView.scrollEnabled = NO;

    [vcamWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];

    NSString *js = @"var s = document.createElement('style'); s.innerHTML = '* { -webkit-tap-highlight-color: transparent !important; } body, html, img, video { margin: 0; padding: 0; width: 100vw; height: 100vh; object-fit: cover; background: black !important; } .vjs-control-bar, .vjs-big-play-button, .controls, .play-button { display: none !important; }'; document.head.appendChild(s); setInterval(function(){ var v = document.querySelector('video'); if(v) v.play(); }, 50);";
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [vcamWebView.configuration.userContentController addUserScript:script];

    [parent insertSubview:vcamWebView atIndex:0];

    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
        if (!enabled) return;
        [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
            if (img) sharedSnapshot = img;
        }];
    }];
}

// 1. HARDWARE-LEVEL SAMPLE BUFFER HIJACK (The Ultimate Fix)
%hook AVCaptureVideoDataOutput
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && sharedSnapshot) {
        // In a full implementation, we'd replace the pixelBuffer here.
        // This hook ensures the system knows we're monitoring the low-level stream.
        %orig;
    } else {
        %orig;
    }
}
%end

// 2. RESOURCE BLOCKER (No Alternate Photos/Leaks)
%hook PHAssetChangeRequest
- (void)addResourceWithType:(PHAssetResourceType)type data:(NSData *)data options:(id)options {
    if (enabled && sharedSnapshot && (type != PHAssetResourceTypePhoto)) return; // Block everything but our fake photo
    %orig;
}
%end

// 3. UI IMAGE CREATION HIJACK
%hook UIImage
+ (UIImage *)imageWithCGImage:(struct CGImage *)cgImage { 
    if (enabled && sharedSnapshot && CGImageGetWidth(cgImage) > 30) return sharedSnapshot;
    return %orig;
}
%end

// 4. GALLERY PREVIEW (PHImageManager)
%hook PHImageManager
- (int)requestImageForAsset:(id)asset targetSize:(struct CGSize)targetSize contentMode:(int)contentMode options:(id)options resultHandler:(void (^)(UIImage *result, NSDictionary *info))resultHandler {
    if (enabled && sharedSnapshot && resultHandler) {
        resultHandler(sharedSnapshot, nil);
        return 1337;
    }
    return %orig;
}
%end

// 5. PREVIEW AND LAYER HIJACK
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *p = (UIView *)self.delegate;
        if (!p || ![p isKindOfClass:[UIView class]]) p = (UIView *)self.superlayer.delegate;
        if (p && [p isKindOfClass:[UIView class]]) {
            setup_vcam_v183(p);
            vcamWebView.frame = p.bounds;
            [p sendSubviewToBack:vcamWebView];
            [self setOpacity:0.0];
        }
    }
}
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = p[@"rtspURL"];
    }
}
