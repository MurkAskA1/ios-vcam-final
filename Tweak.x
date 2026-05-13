// VirtualCamPro V245.0: The Final Verdict
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;
static UILabel *gStatusLabel = nil;

static void load_prefs() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
    if (prefs) {
        enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        NSString *u = prefs[@"rtspURL"];
        if (u && [u length] > 5) streamURL = u;
    }
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        self.opacity = 0.0;
        UIView *p = (UIView *)self.delegate;
        if ([p isKindOfClass:[UIView class]]) {
            UIImageView *vcam = [p viewWithTag:9999];
            if (!vcam) {
                vcam = [[UIImageView alloc] initWithFrame:p.bounds];
                vcam.tag = 9999;
                vcam.contentMode = UIViewContentModeScaleAspectFill;
                [p insertSubview:vcam atIndex:0];
                
                gStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, 300, 30)];
                gStatusLabel.textColor = [UIColor greenColor];
                gStatusLabel.font = [UIFont boldSystemFontOfSize:14];
                gStatusLabel.text = @"Connecting...";
                [p addSubview:gStatusLabel];
            }
            vcam.image = gLastFrame;
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
    load_prefs();
    if (enabled) {
        gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gReader.frameCallback = ^(UIImage *frame) {
            gLastFrame = frame;
            if (gStatusLabel) gStatusLabel.text = [NSString stringWithFormat:@"Live | FPS: %lu", (unsigned long)gReader.frameCount];
        };
        gReader.errorCallback = ^(NSError *err) {
            if (gStatusLabel) gStatusLabel.text = [NSString stringWithFormat:@"Error: %ld", (long)err.code];
        };
        [gReader startStreaming];
    }
}
