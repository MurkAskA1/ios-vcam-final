// VirtualCamPro V243.0: The Final Masterpiece (Display & KYC Recovery)
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *globalVcamView = nil;
static UIImage *globalLastSnapshot = nil;

static void load_prefs() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
    if (prefs) {
        enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        NSString *u = prefs[@"rtspURL"];
        if (u && [u length] > 5) streamURL = u;
    }
}

// ATS Bypass to allow raw HTTP streams
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
    
    if (globalVcamView && globalVcamView.superview == parent) {
        [parent sendSubviewToBack:globalVcamView];
        return;
    }
    
    if (globalVcamView) [globalVcamView removeFromSuperview];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;

    globalVcamView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    globalVcamView.backgroundColor = [UIColor blackColor];
    globalVcamView.scrollView.backgroundColor = [UIColor blackColor];
    globalVcamView.opaque = YES;
    globalVcamView.userInteractionEnabled = NO;
    globalVcamView.scrollView.scrollEnabled = NO;

    // Using the most robust method for MJPEG: Simple HTML <img> tag.
    // This ELIMINATES all play buttons, seek bars, and MediaMTX player UI.
    NSString *html = [NSString stringWithFormat:@"
        <html><head><style>
        body { background-color: black; margin: 0; overflow: hidden; }
        img { width: 100vw; height: 100vh; object-fit: cover; position: absolute; top: 0; left: 0; }
        </style></head><body>
        <img src='%@' onerror='this.src=this.src;'>
        </body></html>", streamURL];

    [globalVcamView loadHTMLString:html baseURL:[NSURL URLWithString:streamURL]];

    [parent insertSubview:globalVcamView atIndex:0];
    
    // Snapshot loop for gallery hijack
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
        self.opacity = 0.0; // Hide the real camera output
        UIView *target = (UIView *)self.delegate;
        if ([target isKindOfClass:[UIView class]]) {
            inject_vcam(target);
            globalVcamView.frame = target.bounds;
        }
    }
}
%end

// Anti-KYC Masking
%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (BOOL)isVirtualDevice { return NO; }
%end

// Hijack final photo capture
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && globalLastSnapshot) return UIImageJPEGRepresentation(globalLastSnapshot, 0.95);
    return %orig;
}
%end

// Hijack camera preview bubble
%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && globalLastSnapshot) %orig(globalLastSnapshot);
    else %orig(image);
}
%end

// Hijack Gallery Thumbnails (Liveness/Recent Photos Fix)
%hook PHImageManager
- (PHImageRequestID)requestImageForAsset:(PHAsset *)asset targetSize:(CGSize)size contentMode:(PHImageContentMode)mode options:(PHImageRequestOptions *)options resultHandler:(void (^)(UIImage *result, NSDictionary *info))handler {
    if (enabled && globalLastSnapshot && asset.mediaType == PHAssetMediaTypeImage) {
        NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:asset.creationDate];
        if (diff < 60.0) { // Only hijack assets from the last minute
            handler(globalLastSnapshot, nil);
            return 1;
        }
    }
    return %orig;
}
%end

%ctor {
    load_prefs();
}
