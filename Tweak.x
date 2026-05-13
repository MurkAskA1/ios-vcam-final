// Tweak.x - VirtualCamPro V249.0: Stability & Safety Fix
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;
static UILabel *gStatusLabel = nil;

// Safe UI update for diagnostics, only in Camera app
static void VCamUpdateStatus(UIView *host, NSString *text, UIColor *color) {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.camera"]) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *label = (UILabel *)[host viewWithTag:7777];
        if (!label) {
            label = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, host.bounds.size.width, 40)];
            label.tag = 7777;
            label.textAlignment = NSTextAlignmentCenter;
            label.font = [UIFont boldSystemFontOfSize:13];
            label.textColor = [UIColor whiteColor];
            label.numberOfLines = 0;
            [host addSubview:label];
        }
        label.text = text;
        label.backgroundColor = [color colorWithAlphaComponent:0.6];
    });
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
                [p insertSubview:v atIndex:0];
            }
            v.image = gLastFrame;
            
            if (gReader.frameCount > 0) {
                VCamUpdateStatus(p, [NSString stringWithFormat:@"Live | FPS: %lu", (unsigned long)gReader.frameCount], [UIColor greenColor]);
            } else {
                VCamUpdateStatus(p, @"Connecting to stream...", [UIColor orangeColor]);
            }
        }
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && gLastFrame) return UIImageJPEGRepresentation(gLastFrame, 0.9);
    return %orig;
}
%end

%ctor {
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
    // ONLY run network logic in specific apps to prevent system hangs
    if ([bundleID isEqualToString:@"com.apple.camera"] || 
        [bundleID isEqualToString:@"org.telegram.messenger"] || 
        [bundleID containsString:@"safari"] || 
        [bundleID containsString:@"chrome"]) {
        
        gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gReader.frameCallback = ^(UIImage *frame) { gLastFrame = frame; };
        gReader.errorCallback = ^(NSError *err) {
             NSLog(@"[VCam] Stream Error: %@", err.localizedDescription);
        };
        [gReader startStreaming];
    }
}
