// Tweak.x - VirtualCamPro V271.2: Fixed Rendering Engine
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES;
// Stream URL from your browser screenshot (port 8889)
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";

static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;
static UIImageView *gPreviewView = nil;

static void VCamDebug(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[VCamPro] %@ | Time: %@\n", msg, [NSDate date]];
    NSLog(@"%@", line);
}

%hook NSBundle
- (NSDictionary *)infoDictionary {
    NSMutableDictionary *dict = [%orig mutableCopy];
    if (!dict[@"NSAppTransportSecurity"]) {
        dict[@"NSAppTransportSecurity"] = @{ @"NSAllowsArbitraryLoads": @YES };
    }
    return dict;
}
%end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.opacity = 0.0;
    UIView *container = (UIView *)self.delegate;
    if ([container isKindOfClass:[UIView class]]) {
        if (!gPreviewView) {
            gPreviewView = [[UIImageView alloc] initWithFrame:container.bounds];
            gPreviewView.contentMode = UIViewContentModeScaleAspectFill;
            gPreviewView.backgroundColor = [UIColor blackColor];
            gPreviewView.tag = 8888;
            [container insertSubview:gPreviewView atIndex:0];
        }
        gPreviewView.frame = container.bounds;
        if (gLastFrame) gPreviewView.image = gLastFrame;
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && gLastFrame) {
        return UIImageJPEGRepresentation(gLastFrame, 0.95);
    }
    return %orig;
}
- (CGImageRef)CGImageRepresentation {
    if (enabled && gLastFrame) {
        return gLastFrame.CGImage;
    }
    return %orig;
}
%end

%hook AVCaptureSession
- (void)startRunning {
    %orig;
}
%end

%ctor {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    if ([bid containsString:@"camera"] || [bid containsString:@"telegra"] || 
        [bid containsString:@"safari"] || [bid containsString:@"chrome"] || 
        [bid containsString:@"WebKit"] || [bid containsString:@"facetime"] ||
        [bid containsString:@"whatsapp"] || [bid containsString:@"instagram"] || 
        [bid containsString:@"tiktok"] || [bid containsString:@"snapchat"]) {
        
        gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gReader.frameCallback = ^(UIImage *f) {
            gLastFrame = f;
            if (gPreviewView) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    gPreviewView.image = f;
                });
            }
        };
        [gReader startStreaming];
    }
}
