// VCAM V182.0: The Cache Killer - Deep Hardware-to-File Hijack
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *vcamWebView = nil;
static UIImage *sharedSnapshot = nil;

static void setup_vcam_v182(UIView *parent) {
    if (!parent || (vcamWebView && vcamWebView.superview == parent)) return;
    if (vcamWebView) [vcamWebView removeFromSuperview];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    vcamWebView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamWebView.backgroundColor = [UIColor blackColor];
    vcamWebView.userInteractionEnabled = NO;
    vcamWebView.opaque = NO;

    [vcamWebView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];

    NSString *js = @"var s = document.createElement('style'); s.innerHTML = '* { -webkit-tap-highlight-color: transparent !important; } body, html, img, video { margin: 0; padding: 0; width: 100vw; height: 100vh; object-fit: cover; background: black !important; } .vjs-control-bar, .vjs-big-play-button, .controls, .play-button { display: none !important; }'; document.head.appendChild(s); setInterval(function(){ var v = document.querySelector('video'); if(v) v.play(); }, 50);";
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [vcamWebView.configuration.userContentController addUserScript:script];

    [parent insertSubview:vcamWebView atIndex:0];

    [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t) {
        if (!enabled) return;
        [vcamWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
            if (img) sharedSnapshot = img;
        }];
    }];
}

// 1. DISABLE HARDWARE THUMBNAILS (Force software generation from our fake image)
%hook AVCapturePhotoSettings
- (NSArray *)availableEmbeddedThumbnailPhotoCodecTypes { return @[]; }
%end

// 2. RESOURCE DATA HIJACK (The "Filmstrip" leak fix)
%hook PHAssetChangeRequest
- (void)addResourceWithType:(PHAssetResourceType)type data:(NSData *)data options:(id)options {
    if (enabled && sharedSnapshot && (type == PHAssetResourceTypePhoto || type == PHAssetResourceTypeAlternatePhoto)) {
        NSData *fakeData = UIImageJPEGRepresentation(sharedSnapshot, 0.95);
        %orig(type, fakeData, options);
    } else {
        %orig;
    }
}
%end

// 3. PHOTO RESULT HIJACK
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && sharedSnapshot) return UIImageJPEGRepresentation(sharedSnapshot, 0.95);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation {
    if (enabled && sharedSnapshot) return sharedSnapshot.CGImage;
    return %orig;
}
- (struct CGImage *)previewCGImageRepresentation {
    if (enabled && sharedSnapshot) return sharedSnapshot.CGImage;
    return %orig;
}
%end

// 4. PREVIEW AND UI HIJACK
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *p = (UIView *)self.delegate;
        if (!p || ![p isKindOfClass:[UIView class]]) p = (UIView *)self.superlayer.delegate;
        if (p && [p isKindOfClass:[UIView class]]) {
            setup_vcam_v182(p);
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
