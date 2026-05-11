// VCAM V122.0: Core Hijack - Direct Signal Replacement (Telegram & Photo Fix)
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *vURL = @"http://192.168.1.44:8889/live/stream";
static UIImage *sharedSnap = nil;
static NSMutableData *vBuffer = nil;

@interface VCamEngine : NSObject <NSURLSessionDataDelegate> + (instancetype)shared; - (void)start; @end
@implementation VCamEngine
+ (instancetype)shared { static VCamEngine *s = nil; static dispatch_once_t o; dispatch_once(&o, ^{ s = [[self alloc] init]; }); return s; }
- (void)start {
    vBuffer = [NSMutableData data];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    [[s dataTaskWithURL:[NSURL URLWithString:vURL]] resume];
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
    [vBuffer appendData:d];
    const unsigned char *b = (const unsigned char *)vBuffer.bytes; NSInteger len = vBuffer.length;
    for (NSInteger i = 0; i < len - 1; i++) {
        if (b[i] == 0xFF && b[i+1] == 0xD8) {
            for (NSInteger j = i + 1; j < len - 1; j++) {
                if (b[j] == 0xFF && b[j+1] == 0xD9) {
                    UIImage *img = [UIImage imageWithData:[vBuffer subdataWithRange:NSMakeRange(i, j - i + 2)]];
                    if (img) sharedSnap = img;
                    [vBuffer replaceBytesInRange:NSMakeRange(0, j + 2) withBytes:NULL length:0]; return;
                }
            }
        }
    }
}
@end

// 1. Hooking the Preview Layer to show our stream INSIDE it
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        [[VCamEngine shared] start];
        CALayer *targetLayer = nil;
        for (CALayer *sub in self.sublayers) {
            if ([sub.name isEqualToString:@"vcamLayer"]) { targetLayer = sub; break; }
        }
        if (!targetLayer) {
            targetLayer = [CALayer layer];
            targetLayer.name = @"vcamLayer";
            targetLayer.contentsGravity = kCAGravityResizeAspectFill;
            targetLayer.zPosition = 9999;
            [self addSublayer:targetLayer];
        }
        if (sharedSnap) targetLayer.contents = (__bridge id)sharedSnap.CGImage;
        targetLayer.frame = self.bounds;
        
        // Mirroring logic
        AVCaptureSession *session = self.session;
        BOOL isFront = NO;
        for (AVCaptureInput *input in session.inputs) {
            if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                if (((AVCaptureDeviceInput *)input).device.position == 2) { isFront = YES; break; }
            }
        }
        targetLayer.transform = isFront ? CATransform3DMakeAffineTransform(CGAffineTransformMakeScale(-1, 1)) : CATransform3DIdentity;
    }
}
%end

// 2. Direct Photo Hijack - replacing the captured image data
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && sharedSnap) return UIImageJPEGRepresentation(sharedSnap, 0.95);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation {
    if (enabled && sharedSnap) return sharedSnap.CGImage;
    return %orig;
}
%end

// 3. Ensuring stability in session-based apps like Telegram
%hook AVCaptureSession
- (void)startRunning {
    [[VCamEngine shared] start];
    %orig;
}
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) vURL = [p[@"rtspURL"] stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
    }
}
