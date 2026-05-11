// VCAM V115.0: The Final Mirror - MJPEG Window Engine
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIWindow *vcamWindow = nil;
static UIImageView *vcamView = nil;
static UIImage *lastFrame = nil;
static NSMutableData *mBuffer = nil;

@interface VCamFetcher : NSObject <NSURLSessionDataDelegate> + (instancetype)shared; - (void)start; @end
@implementation VCamFetcher
+ (instancetype)shared { static VCamFetcher *s = nil; static dispatch_once_t once; dispatch_once(&once, ^{ s = [[self alloc] init]; }); return s; }
- (void)start {
    mBuffer = [NSMutableData data];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    [[session dataTaskWithURL:[NSURL URLWithString:streamURL]] resume];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    [mBuffer appendData:data];
    const unsigned char *b = (const unsigned char *)mBuffer.bytes;
    NSInteger len = mBuffer.length;
    for (NSInteger i = 0; i < len - 1; i++) {
        if (b[i] == 0xFF && b[i+1] == 0xD8) {
            for (NSInteger j = i + 1; j < len - 1; j++) {
                if (b[j] == 0xFF && b[j+1] == 0xD9) {
                    NSData *jpeg = [mBuffer subdataWithRange:NSMakeRange(i, j - i + 2)];
                    UIImage *img = [UIImage imageWithData:jpeg];
                    if (img) { lastFrame = img; if (vcamView) vcamView.image = img; }
                    [mBuffer replaceBytesInRange:NSMakeRange(0, j + 2) withBytes:NULL length:0];
                    return;
                }
            }
        }
    }
}
@end

static void setup_vcam_window(void) {
    if (vcamWindow) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        vcamWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        vcamWindow.windowLevel = UIWindowLevelAlert + 2000;
        vcamWindow.backgroundColor = [UIColor blackColor];
        vcamWindow.userInteractionEnabled = NO;
        vcamWindow.hidden = NO;
        
        vcamView = [[UIImageView alloc] initWithFrame:vcamWindow.bounds];
        vcamView.contentMode = UIViewContentModeScaleAspectFill;
        [vcamWindow addSubview:vcamView];
        
        [[VCamFetcher shared] start];
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        setup_vcam_window();
        vcamWindow.hidden = NO;
        AVCaptureSession *s = self.session; BOOL f = NO;
        for (AVCaptureInput *i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == AVCaptureDevicePositionFront) { f = YES; break; } }
        vcamView.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
        self.opacity = 0.0;
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (enabled && lastFrame) objc_setAssociatedObject(s, "vcamS", lastFrame, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

%hook AVCaptureSession
- (void)stopRunning { %orig; if (vcamWindow) vcamWindow.hidden = YES; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = [p[@"rtspURL"] stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
    }
}
