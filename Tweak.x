// Tweak.x - VirtualCamPro V256.0: Heartbeat Edition
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
static UILabel *gStatusLabel = nil;

static void GlobalLog(NSString *msg) {
    os_log(OS_LOG_DEFAULT, "[VCam] %{public}@", msg);
    FILE *f = fopen("/var/mobile/Documents/vcam.log", "a");
    if (f) {
        fprintf(f, "[%s] %s\n", [[NSDate date].description UTF8String], [msg UTF8String]);
        fclose(f);
    }
}

static void UpdateStatus(UIView *view, NSString *text, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gStatusLabel) {
            gStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, view.bounds.size.width, 60)];
            gStatusLabel.textAlignment = NSTextAlignmentCenter;
            gStatusLabel.font = [UIFont boldSystemFontOfSize:14];
            gStatusLabel.textColor = [UIColor whiteColor];
            gStatusLabel.numberOfLines = 0;
            gStatusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
            [view addSubview:gStatusLabel];
            [view bringSubviewToFront:gStatusLabel];
        }
        gStatusLabel.text = [NSString stringWithFormat:@"V256 | %@", text];
        gStatusLabel.textColor = color;
    });
}

// Hooking the actual view instead of just the layer for better visibility
%hook UIView
- (void)didMoveToWindow {
    %orig;
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    if ([bid isEqualToString:@"com.apple.camera"]) {
        if ([NSStringFromClass([self class]) containsString:@"Preview"]) {
            self.backgroundColor = [UIColor blackColor];
            UpdateStatus(self, @"PREVIEW VIEW DETECTED", [UIColor yellowColor]);
        }
    }
}
%end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        self.opacity = 0.0;
        UIView *p = (UIView *)self.delegate;
        if ([p isKindOfClass:[UIView class]]) {
            UIImageView *v = [p viewWithTag:9999];
            if (!v) {
                v = [[UIImageView alloc] initWithFrame:p.bounds];
                v.tag = 9999;
                v.contentMode = UIViewContentModeScaleAspectFill;
                [p insertSubview:v atIndex:0];
            }
            if (gLastFrame) v.image = gLastFrame;
            
            NSString *stat = (gReader.frameCount > 0) ? 
                [NSString stringWithFormat:@"LIVE | FPS: %lu", (unsigned long)gReader.frameCount] : 
                @"CONNECTING...";
            UpdateStatus(p, stat, (gReader.frameCount > 0 ? [UIColor greenColor] : [UIColor orangeColor]));
        }
    }
}
%end

%ctor {
    GlobalLog([NSString stringWithFormat:@"--- V256 START in %@ ---", [NSBundle mainBundle].bundleIdentifier]);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gReader.frameCallback = ^(UIImage *f) { 
            static BOOL first = YES;
            if (first) { GlobalLog(@"FRAME OK"); first = NO; }
            gLastFrame = f; 
        };
        gReader.errorCallback = ^(NSError *e) {
            GlobalLog([NSString stringWithFormat:@"NET ERROR: %@", e.localizedDescription]);
        };
        [gReader startStreaming];
        GlobalLog(@"Fetcher Resumed");
    });
}
