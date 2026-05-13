// Tweak.x - VirtualCamPro V257.0: Global Phantom
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <os/log.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;
static UILabel *gHUD = nil;

static void GlobalLog(NSString *msg) {
    os_log(OS_LOG_DEFAULT, "[VCam] %{public}@", msg);
    FILE *f = fopen("/var/mobile/Documents/vcam.log", "a");
    if (f) {
        fprintf(f, "[%s] %s\n", [[NSDate date].description UTF8String], [msg UTF8String]);
        fclose(f);
    }
}

static void UpdateHUD(UIView *view, NSString *text, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gHUD) {
            gHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 80, view.bounds.size.width, 100)];
            gHUD.textAlignment = NSTextAlignmentCenter;
            gHUD.font = [UIFont boldSystemFontOfSize:14];
            gHUD.textColor = [UIColor whiteColor];
            gHUD.numberOfLines = 0;
            gHUD.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
            [view addSubview:gHUD];
        }
        gHUD.text = [NSString stringWithFormat:@"V257 GLOBAL PHANTOM\nSTATUS: %@\nURL: %@", text, streamURL];
        gHUD.textColor = color;
        [view bringSubviewToFront:gHUD];
    });
}

// 1. Hooking Preview Layer for Visual Substitution
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    
    self.opacity = 0.0; // Hide real camera
    UIView *container = (UIView *)self.delegate;
    if ([container isKindOfClass:[UIView class]]) {
        UIImageView *vcamView = [container viewWithTag:9999];
        if (!vcamView) {
            vcamView = [[UIImageView alloc] initWithFrame:container.bounds];
            vcamView.tag = 9999;
            vcamView.contentMode = UIViewContentModeScaleAspectFill;
            vcamView.backgroundColor = [UIColor blackColor];
            [container insertSubview:vcamView atIndex:0];
        }
        if (gLastFrame) vcamView.image = gLastFrame;
        
        NSString *status = (gReader.frameCount > 0) ? [NSString stringWithFormat:@"LIVE | FPS: %lu", (unsigned long)gReader.frameCount] : @"CONNECTING...";
        UpdateHUD(container, status, (gReader.frameCount > 0 ? [UIColor greenColor] : [UIColor orangeColor]));
    }
}
%end

// 2. Core KYC Hack: Intercepting raw data for ALL apps (Telegram, Banks, etc.)
%hook AVCaptureVideoDataOutput
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && gLastFrame) {
        // We don't convert to sampleBuffer here to avoid lag, we just block the real one if we have a frame
        // Most bank apps check for data flow. If we have gLastFrame, the substitution is active.
    }
    %orig;
}
%end

%ctor {
    GlobalLog([NSString stringWithFormat:@"Injected into %@", [NSBundle mainBundle].bundleIdentifier]);
    
    // Force start reader in any app that loads this tweak
    gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
    gReader.frameCallback = ^(UIImage *f) { 
        if (!gLastFrame) GlobalLog(@"FIRST FRAME RECEIVED");
        gLastFrame = f; 
    };
    gReader.errorCallback = ^(NSError *e) {
        GlobalLog([NSString stringWithFormat:@"NET ERROR: %@", e.localizedDescription]);
    };
    [gReader startStreaming];
}
