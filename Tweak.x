// Tweak.x - VirtualCamPro V261.0: Core Force
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
static UILabel *gStatusHUD = nil;

// 1. Force Allow Local HTTP (ATS Bypass)
%hook NSBundle
- (NSDictionary *)infoDictionary {
    NSMutableDictionary *dict = [%orig mutableCopy];
    dict[@"NSAppTransportSecurity"] = @{ @"NSAllowsArbitraryLoads": @YES };
    return dict;
}
%end

static void UpdateHUD(UIView *host, NSString *status, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gStatusHUD) {
            gStatusHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, host.bounds.size.width, 60)];
            gStatusHUD.textAlignment = NSTextAlignmentCenter;
            gStatusHUD.font = [UIFont boldSystemFontOfSize:12];
            gStatusHUD.textColor = [UIColor whiteColor];
            gStatusHUD.numberOfLines = 0;
            gStatusHUD.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
            [host addSubview:gStatusHUD];
        }
        gStatusHUD.text = [NSString stringWithFormat:@"V261 | URL: %@\nSTATUS: %@", streamURL, status];
        gStatusHUD.textColor = color;
        [host bringSubviewToFront:gStatusHUD];
    });
}

// 2. Visual Substitution
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    
    self.opacity = 0.0;
    UIView *p = (UIView *)self.delegate;
    if ([p isKindOfClass:[UIView class]]) {
        UIImageView *vcam = [p viewWithTag:9999];
        if (!vcam) {
            vcam = [[UIImageView alloc] initWithFrame:p.bounds];
            vcam.tag = 9999;
            vcam.contentMode = UIViewContentModeScaleAspectFill;
            vcam.backgroundColor = [UIColor blackColor];
            [p insertSubview:vcam atIndex:0];
        }
        if (gLastFrame) vcam.image = gLastFrame;
        
        NSString *statStr = (gReader.frameCount > 0) ? 
            [NSString stringWithFormat:@"ACTIVE (FPS: %lu)", (unsigned long)gReader.frameCount] : 
            @"CONNECTING...";
        
        UpdateHUD(p, statStr, (gReader.frameCount > 0 ? [UIColor greenColor] : [UIColor orangeColor]));
    }
}
%end

// 3. Absolute Photo Hijack
%hook AVCapturePhoto
- (CGImageRef)CGImageRepresentation { if (enabled && gLastFrame) return gLastFrame.CGImage; return %orig; }
- (NSData *)fileDataRepresentation { if (enabled && gLastFrame) return UIImageJPEGRepresentation(gLastFrame, 0.9); return %orig; }
%end

%ctor {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    // Inject into any app that has a UI and might use camera
    if ([bid containsString:@"camera"] || [bid containsString:@"telegra"] || [bid containsString:@"safari"] || [bid containsString:@"chrome"] || [bid containsString:@"WebKit"]) {
        gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gReader.frameCallback = ^(UIImage *f) { gLastFrame = f; };
        [gReader startStreaming];
    }
}
