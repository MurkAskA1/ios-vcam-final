// Tweak.x - VirtualCamPro: Deep System Integration v4 (Status Overlay)
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8887/live/stream";

static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;
static UIImageView *gPreviewView = nil;
static UILabel *gStatusLabel = nil;

void UpdateStatus(NSString *text, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gStatusLabel) {
            gStatusLabel.text = text;
            gStatusLabel.textColor = color;
        }
    });
}

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
            [container insertSubview:gPreviewView atIndex:0];
            
            gStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, 200, 30)];
            gStatusLabel.font = [UIFont boldSystemFontOfSize:14];
            gStatusLabel.text = @"📡 WAITING...";
            gStatusLabel.textColor = [UIColor yellowColor];
            [container addSubview:gStatusLabel];
        }
        gPreviewView.frame = container.bounds;
        if (gLastFrame) gPreviewView.image = gLastFrame;
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && gLastFrame) return UIImageJPEGRepresentation(gLastFrame, 0.95);
    return %orig;
}
- (CGImageRef)CGImageRepresentation {
    if (enabled && gLastFrame) return gLastFrame.CGImage;
    return %orig;
}
%end

%ctor {
    gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
    gReader.frameCallback = ^(UIImage *f) {
        gLastFrame = f;
        UpdateStatus(@"✅ LIVE", [UIColor greenColor]);
        if (gPreviewView) {
            dispatch_async(dispatch_get_main_queue(), ^{
                gPreviewView.image = f;
            });
        }
    };
    gReader.errorCallback = ^(NSError *error) {
        UpdateStatus(@"❌ ERROR", [UIColor redColor]);
    };
    [gReader startStreaming];
}
