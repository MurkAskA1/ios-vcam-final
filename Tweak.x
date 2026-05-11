// VCAM V149.0: The Stability Master - Fix for Crashes & Perfect Scaling
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIImageView *vcamImageView = nil;
static UIImage *lastFrame = nil;

static void setup_vcam_stable(UIView *parent) {
    if (!parent) return;
    if (vcamImageView && vcamImageView.superview == parent) return;
    
    if (vcamImageView) [vcamImageView removeFromSuperview];

    vcamImageView = [[UIImageView alloc] initWithFrame:parent.bounds];
    vcamImageView.backgroundColor = [UIColor blackColor];
    vcamImageView.contentMode = UIViewContentModeScaleAspectFill;
    vcamImageView.clipsToBounds = YES;
    vcamImageView.userInteractionEnabled = NO;
    
    [parent insertSubview:vcamImageView atIndex:0];

    // Efficient Background Loader
    static dispatch_once_t onceToken;
    static dispatch_queue_t queue;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.vcam.loader", DISPATCH_QUEUE_SERIAL);
    });

    dispatch_async(queue, ^{
        while (enabled) {
            @autoreleasepool {
                NSURL *url = [NSURL URLWithString:streamURL];
                NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:nil];
                if (data && data.length > 500) {
                    UIImage *img = [UIImage imageWithData:data];
                    if (img) {
                        lastFrame = img;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (vcamImageView) vcamImageView.image = img;
                        });
                    }
                }
            }
            [NSThread sleepForTimeInterval:0.05];
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
            setup_vcam_stable(p);
            vcamImageView.frame = p.bounds;
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