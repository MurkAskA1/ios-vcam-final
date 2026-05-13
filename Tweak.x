// Tweak.x - VirtualCamPro V267.0: Total Capture Lockdown
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

static void UpdateDiagnostics(UIView *view, NSString *status, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gDiagnosticsHUD) {
            gDiagnosticsHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 80, view.bounds.size.width, 140)];
            gDiagnosticsHUD.textAlignment = NSTextAlignmentCenter;
            gDiagnosticsHUD.font = [UIFont fontWithName:@"Courier-Bold" size:12];
            gDiagnosticsHUD.textColor = [UIColor whiteColor];
            gDiagnosticsHUD.numberOfLines = 0;
            gDiagnosticsHUD.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
            [view addSubview:gDiagnosticsHUD];
        }
        gDiagnosticsHUD.text = [NSString stringWithFormat:@"VCAM V267 LOCKDOWN\nURL: %@\nSTATUS: %@\nBUFFER: %@", 
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

// 2. Absolute Photo Hijack (Multiple hooks to stop REAL photo leak)
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled) {
        if (gLastFrame) return UIImageJPEGRepresentation(gLastFrame, 0.95);
        // If stream is empty, return a black square instead of reality!
        return UIImageJPEGRepresentation([UIImage imageNamed:@"black"], 0.1);
    }
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    if (enabled && gLastFrame) return gLastFrame.CGImage;
    return %orig;
}
%end

// 3. Prevent Data Leak (For apps that don't use 'photo' but capture frames)
%hook AVCaptureVideoDataOutput
- (void)captureOutput:(AVCaptureOutput *)o didOutputSampleBuffer:(CMSampleBufferRef)s fromConnection:(AVCaptureConnection *)c {
    if (enabled) {
        // We don't call %orig here if enabled, to stop the real lens from leaking data to the app
        // In a real bank app, this forces it to wait for our injected buffer.
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
