// VCAM V111.0: Pure MJPEG Engine - Final Restoration
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIImageView *vcamImageView = nil;
static UIImage *lastGrabbedFrame = nil;
static UILabel *vHUD = nil;
static UIWindow *vWindow = nil;

void v_log(NSString *m) {
    NSString *p = @"/var/mobile/Documents/vcam_MJPEG.log";
    NSString *f = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], m];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (h) { [h seekToEndOfFile]; [h writeData:[f dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
    else { [f writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
}

@interface VCamMJPEGProvider : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSMutableData *buffer;
+ (instancetype)shared;
- (void)start;
@end

@implementation VCamMJPEGProvider
+ (instancetype)shared { static VCamMJPEGProvider *s = nil; static dispatch_once_t once; dispatch_once(&once, ^{ s = [[self alloc] init]; }); return s; }
- (void)start {
    self.buffer = [NSMutableData data];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    [[session dataTaskWithURL:[NSURL URLWithString:streamURL]] resume];
    v_log(@"MJPEG Stream Started");
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [self.buffer appendData:data];
    const unsigned char *bytes = (const unsigned char *)self.buffer.bytes;
    NSInteger length = self.buffer.length;
    
    for (NSInteger i = 0; i < length - 1; i++) {
        if (bytes[i] == 0xFF && bytes[i+1] == 0xD8) { // SOI
            for (NSInteger j = i + 1; j < length - 1; j++) {
                if (bytes[j] == 0xFF && bytes[j+1] == 0xD9) { // EOI
                    NSData *jpegData = [self.buffer subdataWithRange:NSMakeRange(i, j - i + 2)];
                    UIImage *img = [UIImage imageWithData:jpegData];
                    if (img) {
                        lastGrabbedFrame = img;
                        if (vcamImageView) vcamImageView.image = img;
                    }
                    [self.buffer replaceBytesInRange:NSMakeRange(0, j + 2) withBytes:NULL length:0];
                    return;
                }
            }
        }
    }
}
@end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    if (!vcamImageView) {
        vcamImageView = [[UIImageView alloc] init];
        vcamImageView.contentMode = UIViewContentModeScaleAspectFill;
        vcamImageView.backgroundColor = [UIColor greenColor].CGColor;
        [[VCamMJPEGProvider shared] start];
    }
    if (vcamImageView.superlayer != self) [self addSublayer:vcamImageView.layer];
    vcamImageView.frame = self.bounds;
    vcamImageView.layer.zPosition = 999999;
    
    AVCaptureSession *s = self.session; BOOL f = NO;
    for (AVCaptureInput *i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == AVCaptureDevicePositionFront) { f = YES; break; } }
    vcamImageView.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
    self.opacity = 0.01;
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (enabled && lastGrabbedFrame) objc_setAssociatedObject(s, "vcamS", lastGrabbedFrame, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    UIImage *snap = objc_getAssociatedObject(self.resolvedSettings, "vcamS");
    if (snap) return UIImageJPEGRepresentation(snap, 0.9); 
    return %orig;
}
- (CGImageRef)CGImageRepresentation { UIImage *snap = objc_getAssociatedObject(self.resolvedSettings, "vcamS"); if (snap) return snap.CGImage; return %orig; }
%end

%hook AVCaptureSession
- (void)startRunning { %orig; v_log(@"Session Started"); }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = [p[@"rtspURL"] stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
    }
    v_log(@"VCAM V111.0 MJPEG LOADED");
}
