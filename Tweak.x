// VCAM V118.0: The Final Vision - Robust MJPEG Parser & Permission Fix
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL vEnabled = YES;
static NSString *vURL = @"http://192.168.1.44:8889/live/stream";
static UIWindow *vWindow = nil;
static UIImageView *vDisplay = nil;
static UILabel *vHUD = nil;
static UIImage *vLastSnap = nil;
static NSMutableData *vBuffer = nil;
static long long vBytes = 0;

// Reliable Logging with error checking
void log_v118(NSString *m) {
    NSString *p = @"/var/mobile/Documents/vcam_FINAL.log";
    NSString *f = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], m];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (h) { [h seekToEndOfFile]; [h writeData:[f dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
    else { [f writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
}

@interface VCamFetcher : NSObject <NSURLSessionDataDelegate> + (instancetype)shared; - (void)start; @end
@implementation VCamFetcher
+ (instancetype)shared { static VCamFetcher *s = nil; static dispatch_once_t o; dispatch_once(&o, ^{ s = [[self alloc] init]; }); return s; }
- (void)start {
    vBuffer = [NSMutableData data];
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    [[s dataTaskWithURL:[NSURL URLWithString:vURL]] resume];
    log_v118(@"Fetch Task Started");
}
- (void)URLSession:(NSURLSession *)s dataTask:(NSURLSessionDataTask *)t didReceiveData:(NSData *)d {
    vBytes += d.length;
    dispatch_async(dispatch_get_main_queue(), ^{ if (vHUD) vHUD.text = [NSString stringWithFormat:@"DATA: %lld bytes", vBytes]; });
    [vBuffer appendData:d];
    
    // Robust MJPEG Parsing
    uint8_t *b = (uint8_t *)vBuffer.mutableBytes;
    NSInteger len = vBuffer.length;
    if (len < 2) return;
    
    for (NSInteger i = 0; i < len - 1; i++) {
        if (b[i] == 0xFF && b[i+1] == 0xD8) { // SOI
            for (NSInteger j = i + 1; j < len - 1; j++) {
                if (b[j] == 0xFF && b[j+1] == 0xD9) { // EOI
                    NSData *jpeg = [vBuffer subdataWithRange:NSMakeRange(i, j - i + 2)];
                    UIImage *img = [UIImage imageWithData:jpeg];
                    if (img) {
                        vLastSnap = img;
                        if (vDisplay) { vDisplay.image = img; [vDisplay setNeedsDisplay]; }
                    }
                    [vBuffer replaceBytesInRange:NSMakeRange(0, j + 2) withBytes:NULL length:0];
                    return;
                }
            }
        }
    }
    if (vBuffer.length > 1024 * 1024) [vBuffer setLength:0]; // Guard
}
@end

@interface VCamRootVC : UIViewController @end
@implementation VCamRootVC
- (BOOL)prefersStatusBarHidden { return YES; }
@end

static void setup_v_window(void) {
    if (vWindow) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        vWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        vWindow.windowLevel = UIWindowLevelAlert + 5000;
        vWindow.rootViewController = [[VCamRootVC alloc] init];
        vWindow.backgroundColor = [UIColor blackColor];
        vWindow.userInteractionEnabled = NO;
        vWindow.hidden = NO;
        
        vDisplay = [[UIImageView alloc] initWithFrame:vWindow.bounds];
        vDisplay.contentMode = UIViewContentModeScaleAspectFill;
        [vWindow.rootViewController.view addSubview:vDisplay];
        
        vHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, [UIScreen mainScreen].bounds.size.width, 30)];
        vHUD.textColor = [UIColor greenColor];
        vHUD.font = [UIFont boldSystemFontOfSize:14];
        vHUD.textAlignment = NSTextAlignmentCenter;
        [vWindow.rootViewController.view addSubview:vHUD];
        
        [[VCamFetcher shared] start];
        log_v118(@"Visual Window Initialized");
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (vEnabled) {
        setup_v_window();
        vWindow.hidden = NO;
        AVCaptureSession *s = self.session; BOOL f = NO;
        for (AVCaptureInput *i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == AVCaptureDevicePositionFront) { f = YES; break; } }
        vDisplay.transform = f ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
        self.opacity = 0.01;
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (vEnabled && vLastSnap) objc_setAssociatedObject(s, "vcamS", vLastSnap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
- (void)stopRunning { %orig; if (vWindow) vWindow.hidden = YES; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        vEnabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) vURL = [p[@"rtspURL"] stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
    }
    log_v118(@"VCAM V118.0 Booted");
}
