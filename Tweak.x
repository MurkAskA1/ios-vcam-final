// VCAM V142.0: The Stealth King - Native MJPEG & Total Hijack
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIImageView *vcamView = nil;
static UIImage *lastFrame = nil;

static void setup_vcam(UIView *parent) {
    if (!parent || (vcamView && vcamView.superview == parent)) return;
    if (vcamView) [vcamView removeFromSuperview];

    vcamView = [[UIImageView alloc] initWithFrame:parent.bounds];
    vcamView.backgroundColor = [UIColor blackColor];
    vcamView.contentMode = UIViewContentModeScaleAspectFill;
    vcamView.clipsToBounds = YES;
    [parent insertSubview:vcamView atIndex:0];

    // Light MJPEG Polling Engine
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (enabled) {
            @autoreleasepool {
                NSURL *url = [NSURL URLWithString:streamURL];
                NSData *data = [NSData dataWithContentsOfURL:url];
                if (data) {
                    UIImage *img = [UIImage imageWithData:data];
                    if (img) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            vcamView.image = img;
                            lastFrame = img;
                        });
                    }
                }
            }
            [NSThread sleepForTimeInterval:0.03]; // ~30 FPS
        }
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *p = (UIView *)self.delegate;
        if (!p || ![p isKindOfClass:[UIView class]]) p = (UIView *)self.superlayer.delegate;
        if (p && [p isKindOfClass:[UIView class]]) {
            setup_vcam(p);
            vcamView.frame = p.bounds;
            
            AVCaptureSession *s = self.session;
            BOOL isFront = NO;
            if (s) {
                for (AVCaptureDeviceInput *i in s.inputs) {
                    if (i.device.position == 2) { isFront = YES; break; }
                }
            }
            vcamView.transform = isFront ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
            [self setOpacity:0.0];
        }
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && lastFrame) return UIImageJPEGRepresentation(lastFrame, 0.95);
    return %orig;
}

- (struct CGImage *)CGImageRepresentation {
    if (enabled && lastFrame) return lastFrame.CGImage;
    return %orig;
}

- (struct CGImage *)previewCGImageRepresentation {
    if (enabled && lastFrame) return lastFrame.CGImage;
    return %orig;
}
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) {
            NSString *raw = p[@"rtspURL"];
            raw = [raw stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
            if ([raw hasSuffix:@"/"]) raw = [raw substringToIndex:[raw length]-1];
            streamURL = raw;
        }
    }
}