// Tweak.x - VirtualCamPro V268.0: Nuclear Capture Protection
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;
static UILabel *gDiagnosticsHUD = nil;

// Create a solid black image programmatically to ensure fallback works
static UIImage *CreateBlackImage() {
    CGRect rect = CGRectMake(0, 0, 1, 1);
    UIGraphicsBeginImageContext(rect.size);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, [[UIColor blackColor] CGColor]);
    CGContextFillRect(context, rect);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static void UpdateDiagnostics(UIView *view, NSString *status, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gDiagnosticsHUD) {
            gDiagnosticsHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, view.bounds.size.width, 140)];
            gDiagnosticsHUD.textAlignment = NSTextAlignmentCenter;
            gDiagnosticsHUD.font = [UIFont fontWithName:@"Courier-Bold" size:12];
            gDiagnosticsHUD.textColor = [UIColor whiteColor];
            gDiagnosticsHUD.numberOfLines = 0;
            gDiagnosticsHUD.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
            [view addSubview:gDiagnosticsHUD];
        }
        gDiagnosticsHUD.text = [NSString stringWithFormat:@"VCAM V268 NUCLEAR\nURL: %@\nSTATUS: %@\nBUFFER: %@", 
            streamURL, status, (gLastFrame ? @"READY" : @"EMPTY")];
        gDiagnosticsHUD.textColor = color;
        [view bringSubviewToFront:gDiagnosticsHUD];
    });
}

// 1. Visual Hijack (Preview)
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.opacity = 0.0;
    UIView *p = (UIView *)self.delegate;
    if ([p isKindOfClass:[UIView class]]) {
        UIImageView *v = [p viewWithTag:9999];
        if (!v) {
            v = [[UIImageView alloc] initWithFrame:p.bounds];
            v.tag = 9999;
            v.contentMode = UIViewContentModeScaleAspectFill;
            v.backgroundColor = [UIColor blackColor];
            [p insertSubview:v atIndex:0];
        }
        if (gLastFrame) v.image = gLastFrame;
        
        NSString *netStat = (gReader.frameCount > 0) ? [NSString stringWithFormat:@"ACTIVE | FPS: %lu", (unsigned long)gReader.frameCount] : @"CONNECTING...";
        UpdateDiagnostics(p, netStat, (gReader.frameCount > 0 ? [UIColor greenColor] : [UIColor orangeColor]));
    }
}
%end

// 2. Absolute Photo Hijack (Blocking all output paths)
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (!enabled) return %orig;
    UIImage *target = gLastFrame ? gLastFrame : CreateBlackImage();
    return UIImageJPEGRepresentation(target, 0.95);
}

- (CGImageRef)CGImageRepresentation {
    if (!enabled) return %orig;
    UIImage *target = gLastFrame ? gLastFrame : CreateBlackImage();
    return target.CGImage;
}

// Newer iOS methods
- (CVPixelBufferRef)pixelBuffer {
    if (!enabled) return %orig;
    // Returning NULL forces the app to use fileDataRepresentation or CGImageRepresentation
    return NULL;
}
%end

// 3. Prevent Real Data Leak for all session types
%hook AVCaptureVideoDataOutput
- (void)captureOutput:(AVCaptureOutput *)o didOutputSampleBuffer:(CMSampleBufferRef)s fromConnection:(AVCaptureConnection *)c {
    if (enabled) {
        // DO NOT call %orig. This completely cuts the data line from the real lens to the app.
        // If we have a frame, we could inject it here, but for now we block leakage.
        return;
    }
    %orig;
}
%end

%ctor {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    if ([bid containsString:@"camera"] || [bid containsString:@"telegra"] || [bid containsString:@"safari"]) {
        gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gReader.frameCallback = ^(UIImage *f) { gLastFrame = f; };
        [gReader startStreaming];
    }
}
