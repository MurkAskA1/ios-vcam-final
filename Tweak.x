// Tweak.x - VirtualCamPro V253.0: Forensic Logger
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

// Logging helper to write to a file for Filza inspection
static void VCamLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSString *line = [NSString stringWithFormat:@"[VCam][%@] %@\n", [NSDate date], msg];
    NSLog(@"%@", line);
    
    @try {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/vcam.log"];
        if (!fh) {
            [[NSFileManager defaultManager] createFileAtPath:@"/tmp/vcam.log" contents:nil attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/vcam.log"];
        }
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    } @catch (NSException *e) {}
}

static void UpdateLabel(UIView *h, NSString *s, UIColor *c) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *l = (UILabel *)[h viewWithTag:7777];
        if (!l) {
            l = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, h.bounds.size.width, 60)];
            l.tag = 7777;
            l.textAlignment = NSTextAlignmentCenter;
            l.font = [UIFont boldSystemFontOfSize:14];
            l.textColor = [UIColor whiteColor];
            l.numberOfLines = 0;
            [h addSubview:l];
        }
        l.text = s;
        l.backgroundColor = [c colorWithAlphaComponent:0.7];
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
                VCamLog(@"Creating overlay view in process: %@", [NSBundle mainBundle].bundleIdentifier);
                v = [[UIImageView alloc] initWithFrame:p.bounds];
                v.tag = 9999;
                v.contentMode = UIViewContentModeScaleAspectFill;
                v.backgroundColor = [UIColor blackColor];
                [p insertSubview:v atIndex:0];
            }
            if (gLastFrame) v.image = gLastFrame;
            
            NSString *status = (gReader.frameCount > 0) ? 
                [NSString stringWithFormat:@"V253 | LIVE | FPS: %lu", (unsigned long)gReader.frameCount] : 
                [NSString stringWithFormat:@"V253 | WAITING...\nURL: %@", streamURL];
            
            UpdateLabel(p, status, (gReader.frameCount > 0 ? [UIColor greenColor] : [UIColor orangeColor]));
        }
    }
}
%end

%ctor {
    VCamLog(@"--- VirtualCamPro V253.0 Loaded in %@ ---", [NSBundle mainBundle].bundleIdentifier);
    
    // Only start networking if we are in an app, not a background daemon
    if ([UIApplication sharedApplication]) {
        VCamLog(@"Starting stream reader for %@", streamURL);
        gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gReader.frameCallback = ^(UIImage *f) { 
            gLastFrame = f; 
        };
        gReader.errorCallback = ^(NSError *e) {
            VCamLog(@"Stream Error: %@", e.localizedDescription);
        };
        [gReader startStreaming];
    } else {
        VCamLog(@"Skipping network start - not a UI app");
    }
}
