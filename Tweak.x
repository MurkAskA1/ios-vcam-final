// VCAM V133.0: The Pure Engine - Native MJPEG & Absolute Photo Hijack
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIImageView *vcamDisplayView = nil;
static UIImage *lastGlobalFrame = nil;
static NSMutableData *mjpegBuffer = nil;

@interface VCamMJPEGProvider : NSObject <NSURLSessionDataDelegate> + (instancetype)shared; - (void)start; @end
@implementation VCamMJPEGProvider
+ (instancetype)shared { static VCamMJPEGProvider *s = nil; static dispatch_once_t once; dispatch_once(&once, ^{ s = [[self alloc] init]; }); return s; }
- (void)start {
    mjpegBuffer = [NSMutableData data];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    [[session dataTaskWithURL:[NSURL URLWithString:streamURL]] resume];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    [mjpegBuffer appendData:data];
    const unsigned char *b = (const unsigned char *)mjpegBuffer.bytes;
    NSInteger len = mjpegBuffer.length;
    for (NSInteger i = 0; i < len - 1; i++) {
        if (b[i] == 0xFF && b[i+1] == 0xD8) {
            for (NSInteger j = i + 1; j < len - 1; j++) {
                if (b[j] == 0xFF && b[j+1] == 0xD9) {
                    NSData *jpeg = [mjpegBuffer subdataWithRange:NSMakeRange(i, j - i + 2)];
                    UIImage *img = [UIImage imageWithData:jpeg];
                    if (img) { 
                        lastGlobalFrame = img; 
                        if (vcamDisplayView) vcamDisplayView.image = img; 
                    }
                    [mjpegBuffer replaceBytesInRange:NSMakeRange(0, j + 2) withBytes:NULL length:0];
                    return;
                }
            }
        }
    }
}
@end

static void setup_native_engine(UIView *parent) {
    if (!parent) return;
    if (!vcamDisplayView) {
        vcamDisplayView = [[UIImageView alloc] initWithFrame:parent.bounds];
        vcamDisplayView.contentMode = UIViewContentModeScaleAspectFill;
        vcamDisplayView.backgroundColor = [UIColor blackColor];
        vcamDisplayView.userInteractionEnabled = NO;
        [[VCamMJPEGProvider shared] start];
    }
    if (vcamDisplayView.superview != parent) [parent insertSubview:vcamDisplayView atIndex:0];
    vcamDisplayView.frame = parent.bounds;
    [parent bringSubviewToFront:vcamDisplayView];
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *p = (UIView *)self.delegate;
        if (!p || ![p isKindOfClass:[UIView class]]) p = (UIView *)self.superlayer.delegate;
        if (p && [p isKindOfClass:[UIView class]]) {
            setup_native_engine(p);
            vcamDisplayView.frame = p.bounds;
            AVCaptureSession *s = self.session; BOOL f = NO;
            if (s) {
                for (id i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == 2) { f = YES; break; } }
            }
            vcamDisplayView.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
            [self setOpacity:0.0]; // Hide real camera feed
        }
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && lastGlobalFrame) return UIImageJPEGRepresentation(lastGlobalFrame, 0.95);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation {
    if (enabled && lastGlobalFrame) return lastGlobalFrame.CGImage;
    return %orig;
}
- (struct CGImage *)previewCGImageRepresentation {
    if (enabled && lastGlobalFrame) return lastGlobalFrame.CGImage;
    return %orig;
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(id)s delegate:(id)d { %orig; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = [p[@"rtspURL"] stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
    }
}
