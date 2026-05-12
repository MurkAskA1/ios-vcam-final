// VirtualCamPro V225.0: The Sovereign Engine (Stable Build)
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *globalVcamView = nil;
static UIImage *globalLastImage = nil;
static CVPixelBufferRef globalLastPixelBuffer = NULL;

// --- Direct Preference Loading ---
static void load_vcam_prefs() {
    NSArray *paths = @[@"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist", 
                       @"/var/jb/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
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

// --- Global Frame Capture Loop ---
static void start_frame_capture() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
            if (enabled && globalVcamView) {
                [globalVcamView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
                    if (img) {
                        globalLastImage = img;
                        
                        // Convert to PixelBuffer for deep injection if needed
                        CGImageRef cgImage = img.CGImage;
                        size_t w = CGImageGetWidth(cgImage);
                        size_t h = CGImageGetHeight(cgImage);
                        
                        CVPixelBufferRef px = NULL;
                        NSDictionary *options = @{(id)kCVPixelBufferCGImageCompatibilityKey: @YES, (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES};
                        CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &px);
                        
                        if (status == kCVReturnSuccess && px) {
                            CVPixelBufferLockBaseAddress(px, 0);
                            CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(px), w, h, 8, CVPixelBufferGetBytesPerRow(px), CGColorSpaceCreateDeviceRGB(), (CGBitmapInfo)kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
                            CGContextDrawImage(context, CGRectMake(0, 0, w, h), cgImage);
                            CGContextRelease(context);
                            CVPixelBufferUnlockBaseAddress(px, 0);
                            
                            CVPixelBufferRef old = globalLastPixelBuffer;
                            globalLastPixelBuffer = px;
                            if (old) CVPixelBufferRelease(old);
                        }
                    }
                }];
            }
        }];
    });
}

// --- Visual Hijack (The "Chrome Engine" but Clean) ---
static void inject_vcam_into_view(UIView *parent) {
    if (!parent || !enabled) return;
    
    if (globalVcamView && globalVcamView.superview == parent) {
        [parent bringSubviewToFront:globalVcamView];
        return;
    }

    if (globalVcamView) [globalVcamView removeFromSuperview];

    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    config.allowsInlineMediaPlayback = YES;
    
    globalVcamView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    globalVcamView.backgroundColor = [UIColor blackColor];
    globalVcamView.opaque = YES;
    globalVcamView.userInteractionEnabled = NO;
    globalVcamView.scrollView.scrollEnabled = NO;

    NSString *html = [NSString stringWithFormat:
        @"<html><head><style>"
        "body{margin:0;padding:0;background:black;overflow:hidden;}"
        "img{width:100%%;height:100%%;object-fit:cover;position:fixed;top:0;left:0;}"
        "</style></head><body><img src='%@' onerror='location.reload();'></body></html>", streamURL];
    
    [globalVcamView loadHTMLString:html baseURL:nil];
    [parent insertSubview:globalVcamView atIndex:0];
    
    start_frame_capture();
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *target = nil;
        if ([self.delegate isKindOfClass:[UIView class]]) target = (UIView *)self.delegate;
        else if ([self.superlayer.delegate isKindOfClass:[UIView class]]) target = (UIView *)self.superlayer.delegate;

        if (target) {
            inject_vcam_into_view(target);
            globalVcamView.frame = target.bounds;
        }
    }
}
%end

// --- Anti-KYC Spoofing ---
%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
- (BOOL)isVirtualDevice { return NO; }
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && globalLastImage) return UIImageJPEGRepresentation(globalLastImage, 0.95);
    return %orig;
}
%end

%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && globalLastImage) %orig(globalLastImage);
    else %orig;
}
%end

%ctor {
    load_vcam_prefs();
    NSLog(@"[VirtualCamPro] Sovereign Engine V225.0 Active");
}