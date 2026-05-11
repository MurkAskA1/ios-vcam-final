// VCAM V123.0: The Stealth Inlay - Direct View Injection (Buttons & TG Fix)
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *vURL = @"http://192.168.1.44:8889/live/stream";
static UIImageView *vcamContainer = nil;
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
                    if (img) { 
                        sharedSnap = img; 
                        if (vcamContainer) vcamContainer.image = img;
                    }
                    [vBuffer replaceBytesInRange:NSMakeRange(0, j + 2) withBytes:NULL length:0]; return;
                }
            }
        }
    }
}
@end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        [[VCamEngine shared] start];
        
        // Get the parent view that holds the preview layer
        UIView *parentView = (UIView *)self.delegate;
        if (parentView && [parentView isKindOfClass:[UIView class]]) {
            if (!vcamContainer) {
                vcamContainer = [[UIImageView alloc] initWithFrame:parentView.bounds];
                vcamContainer.contentMode = UIViewContentModeScaleAspectFill;
                vcamContainer.backgroundColor = [UIColor blackColor];
                vcamContainer.userInteractionEnabled = NO;
            }
            
            if (vcamContainer.superview != parentView) {
                [parentView insertSubview:vcamContainer atIndex:0]; // Insert behind controls
            }
            
            vcamContainer.frame = parentView.bounds;
            [parentView bringSubviewToFront:vcamContainer]; // Ensure it covers the real lens layer
            
            // Mirroring logic
            AVCaptureSession *s = self.session; BOOL f = NO;
            for (AVCaptureInput *i in s.inputs) { 
                if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == 2) { f = YES; break; } 
            }
            vcamContainer.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
            
            // HIDE REAL LENS PREVIEW
            [self setOpacity:0.0];
        }
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (enabled && sharedSnap) objc_setAssociatedObject(s, "vcamS", sharedSnap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    UIImage *snap = objc_getAssociatedObject([self resolvedSettings], "vcamS");
    if (snap) return UIImageJPEGRepresentation(snap, 0.95);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation {
    UIImage *snap = objc_getAssociatedObject([self resolvedSettings], "vcamS");
    if (snap) return snap.CGImage;
    return %orig;
}
%end

%hook AVCaptureSession
- (void)startRunning { [[VCamEngine shared] start]; %orig; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) vURL = [p[@"rtspURL"] stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
    }
}
