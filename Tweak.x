// VCAM V114.0: The MJPEG Immortal - Hybrid Window + Layer Override
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIWindow *vcamImmortalWindow = nil;
static UIImageView *vcamDisplayView = nil;
static UIImage *lastFrameV = nil;
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
                    if (img) { lastFrameV = img; if (vcamDisplayView) vcamDisplayView.image = img; }
                    [mjpegBuffer replaceBytesInRange:NSMakeRange(0, j + 2) withBytes:NULL length:0];
                    return;
                }
            }
        }
    }
}
@end

static void setup_immortal_view(UIView *parent) {
    if (!vcamDisplayView) {
        vcamDisplayView = [[UIImageView alloc] initWithFrame:parent.bounds];
        vcamDisplayView.contentMode = UIViewContentModeScaleAspectFill;
        vcamDisplayView.backgroundColor = [UIColor blueColor];
        vcamDisplayView.userInteractionEnabled = NO;
        [[VCamMJPEGProvider shared] start];
    }
    if (vcamDisplayView.superview != parent) [parent addSubview:vcamDisplayView];
    vcamDisplayView.frame = parent.bounds;
    [parent bringSubviewToFront:vcamDisplayView];
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        setup_immortal_view(self.superlayer.delegate && [self.superlayer.delegate isKindOfClass:[UIView class]] ? (UIView *)self.superlayer.delegate : nil);
        if (vcamDisplayView) {
             AVCaptureSession *s = self.session; BOOL f = NO;
             for (AVCaptureInput *i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == AVCaptureDevicePositionFront) { f = YES; break; } }
             vcamDisplayView.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
        }
        self.opacity = 0.01;
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (enabled && lastFrameV) objc_setAssociatedObject(s, "vcamS", lastFrameV, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    UIImage *snap = objc_getAssociatedObject(self.resolvedSettings, "vcamS");
    if (snap) return UIImageJPEGRepresentation(snap, 0.95);
    return %orig;
}
- (CGImageRef)CGImageRepresentation { UIImage *snap = objc_getAssociatedObject(self.resolvedSettings, "vcamS"); if (snap) return snap.CGImage; return %orig; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = [p[@"rtspURL"] stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
    }
}
