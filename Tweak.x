// Tweak.x - VirtualCamPro V255.0: Diagnostic HUD
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
static UITextView *gHUD = nil;

static void VCamHUDLog(NSString *msg) {
    os_log(OS_LOG_DEFAULT, "[VCam] %{public}@", msg);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gHUD) {
            gHUD.text = [gHUD.text stringByAppendingFormat:@"\n> %@", msg];
            [gHUD scrollRangeToVisible:NSMakeRange(gHUD.text.length - 1, 1)];
        }
    });
    
    // Try file log as backup in a more permissive path
    FILE *f = fopen("/var/mobile/Documents/vcam.log", "a");
    if (f) {
        fprintf(f, "[%s] %s\n", [[NSDate date].description UTF8String], [msg UTF8String]);
        fclose(f);
    }
}

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
                v.backgroundColor = [UIColor blackColor];
                [p insertSubview:v atIndex:0];
                
                // Create HUD
                gHUD = [[UITextView alloc] initWithFrame:CGRectMake(10, 40, p.bounds.size.width - 20, 150)];
                gHUD.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
                gHUD.textColor = [UIColor greenColor];
                gHUD.font = [UIFont fontWithName:@"Courier" size:10];
                gHUD.editable = NO;
                gHUD.selectable = NO;
                gHUD.userInteractionEnabled = NO;
                gHUD.text = @"--- VCAM V255 DIAGNOSTIC HUD ---";
                [p addSubview:gHUD];
            }
            if (gLastFrame) v.image = gLastFrame;
        }
    }
}
%end

%ctor {
    os_log(OS_LOG_DEFAULT, "[VCam] Constructor start");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        VCamHUDLog([NSString stringWithFormat:@"Init in: %@", [NSBundle mainBundle].bundleIdentifier]);
        VCamHUDLog([NSString stringWithFormat:@"URL: %@", streamURL]);
        
        NSURL *url = [NSURL URLWithString:[streamURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        if (!url) {
            VCamHUDLog(@"CRITICAL: Invalid URL");
            return;
        }
        
        gReader = [[MJPEGStreamReader alloc] initWithURL:url];
        gReader.frameCallback = ^(UIImage *f) { 
            static BOOL firstFrame = YES;
            if (firstFrame) { VCamHUDLog(@"FIRST FRAME RECEIVED!"); firstFrame = NO; }
            gLastFrame = f; 
        };
        gReader.errorCallback = ^(NSError *e) {
            VCamHUDLog([NSString stringWithFormat:@"STREAM ERROR: %@", e.localizedDescription]);
        };
        
        VCamHUDLog(@"Starting network fetcher...");
        [gReader startStreaming];
    });
}
