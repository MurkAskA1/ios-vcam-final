// Tweak.x - VirtualCamPro V248.0: The Final Force
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES; // FORCED ON FOR DEBUGGING
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;
static UIWindow *gDiagnosticWindow = nil;
static UILabel *gDiagLabel = nil;

static void VCamShowDiagnostic(NSString *text, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gDiagnosticWindow) {
            gDiagnosticWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 100)];
            gDiagnosticWindow.windowLevel = UIWindowLevelStatusBar + 1;
            gDiagnosticWindow.backgroundColor = [UIColor clearColor];
            gDiagnosticWindow.userInteractionEnabled = NO;
            
            gDiagLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, gDiagnosticWindow.bounds.size.width, 60)];
            gDiagLabel.textAlignment = NSTextAlignmentCenter;
            gDiagLabel.numberOfLines = 0;
            gDiagLabel.font = [UIFont boldSystemFontOfSize:12];
            gDiagLabel.textColor = [UIColor whiteColor];
            [gDiagnosticWindow addSubview:gDiagLabel];
            [gDiagnosticWindow setHidden:NO];
        }
        gDiagLabel.text = text;
        gDiagLabel.backgroundColor = [color colorWithAlphaComponent:0.7];
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
            if (gLastFrame) v.image = gLastFrame;
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
    // Forced settings skip for reliability
    VCamShowDiagnostic([NSString stringWithFormat:@"VCam 248 Loaded\nURL: %@", streamURL], [UIColor orangeColor]);
    
    gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
    gReader.frameCallback = ^(UIImage *frame) {
        gLastFrame = frame;
        VCamShowDiagnostic([NSString stringWithFormat:@"Live | FPS: %lu", (unsigned long)gReader.frameCount], [UIColor greenColor]);
    };
    gReader.errorCallback = ^(NSError *err) {
        VCamShowDiagnostic([NSString stringWithFormat:@"Error: %ld\n%@", (long)err.code, err.localizedDescription], [UIColor redColor]);
    };
    [gReader startStreaming];
}
