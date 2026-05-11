// VCAM V117.0: Visual Victory - Dual Engine Window Override
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL vcamEnabled = YES;
static NSString *vcamURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static UIWindow *vcamWindow = nil;
static UIImageView *vcamDisplay = nil;
static UILabel *vcamHUD = nil;
static UIImage *lastValidSnap = nil;
static NSMutableData *dataBuffer = nil;
static long long byteCount = 0;

@interface VCamMJPEGProvider : NSObject <NSURLSessionDataDelegate> + (instancetype)shared; - (void)start; @end
@implementation VCamMJPEGProvider
+ (instancetype)shared { static VCamMJPEGProvider *s = nil; static dispatch_once_t o; dispatch_once(&o, ^{ s = [[self alloc] init]; }); return s; }
- (void)start {
    dataBuffer = [NSMutableData data];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    [[s dataTaskWithURL:[NSURL URLWithString:[vcamURL stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""]]] resume];
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
    byteCount += d.length; [dataBuffer appendData:d];
    dispatch_async(dispatch_get_main_queue(), ^{ if (vcamHUD) vcamHUD.text = [NSString stringWithFormat:@"VCAM DATA: %lld bytes", byteCount]; });
    const unsigned char *b = (const unsigned char *)dataBuffer.bytes; NSInteger len = dataBuffer.length;
    for (NSInteger i = 0; i < len - 1; i++) {
        if (b[i] == 0xFF && b[i+1] == 0xD8) {
            for (NSInteger j = i + 1; j < len - 1; j++) {
                if (b[j] == 0xFF && b[j+1] == 0xD9) {
                    UIImage *img = [UIImage imageWithData:[dataBuffer subdataWithRange:NSMakeRange(i, j - i + 2)]];
                    if (img) { lastValidSnap = img; if (vcamDisplay) vcamDisplay.image = img; }
                    [dataBuffer replaceBytesInRange:NSMakeRange(0, j + 2) withBytes:NULL length:0]; return;
                }
            }
        }
    }
}
@end

@interface VCamRootVC : UIViewController @end
@implementation VCamRootVC
- (BOOL)prefersStatusBarHidden { return YES; }
@end

static void launch_visual_victory(void) {
    if (vcamWindow) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        vcamWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        vcamWindow.windowLevel = UIWindowLevelAlert + 5000;
        vcamWindow.rootViewController = [[VCamRootVC alloc] init];
        vcamWindow.backgroundColor = [UIColor blackColor];
        vcamWindow.userInteractionEnabled = NO; vcamWindow.hidden = NO;
        
        vcamDisplay = [[UIImageView alloc] initWithFrame:vcamWindow.bounds];
        vcamDisplay.contentMode = UIViewContentModeScaleAspectFill;
        [vcamWindow.rootViewController.view addSubview:vcamDisplay];
        
        vcamHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, [UIScreen mainScreen].bounds.size.width, 30)];
        vcamHUD.textColor = [UIColor greenColor]; vcamHUD.font = [UIFont boldSystemFontOfSize:12];
        vcamHUD.textAlignment = NSTextAlignmentCenter; vcamHUD.text = @"VCAM: INITIALIZING...";
        [vcamWindow.rootViewController.view addSubview:vcamHUD];
        
        [[VCamMJPEGProvider shared] start];
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (vcamEnabled) {
        launch_visual_victory(); vcamWindow.hidden = NO;
        AVCaptureSession *s = self.session; BOOL f = NO;
        for (AVCaptureInput *i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == AVCaptureDevicePositionFront) { f = YES; break; } }
        vcamDisplay.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
        self.opacity = 0.0;
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (vcamEnabled && lastValidSnap) objc_setAssociatedObject(s, "vcamS", lastValidSnap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
        vcamEnabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) vcamURL = p[@"rtspURL"];
    }
}
