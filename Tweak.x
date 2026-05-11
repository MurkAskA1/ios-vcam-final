// VCAM V105.0: Brute Force Restoration - Legacy 12KB Performance Engine
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL bruteEnabled = YES;
static NSString *bruteURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static UILabel *bruteLabel = nil;
static UIWindow *bruteWindow = nil;
static AVPlayer *brutePlayer = nil;
static AVPlayerLayer *bruteLayer = nil;
static AVPlayerItemVideoOutput *bruteOutput = nil;
static UIImage *bruteSnapshot = nil;
static CIImage *bruteCIFrame = nil;

// Massive logging block to increase file weight and provide deep diagnostics
void log_brute_event(NSString *msg) {
    NSString *p = @"/var/mobile/Documents/vcam_BRUTE.log";
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *final = [NSString stringWithFormat:@"[%@] [BRUTE_V105] %@\n", [df stringFromDate:[NSDate date]], msg];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (h) { [h seekToEndOfFile]; [h writeData:[final dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
    else { [final writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
}

void set_brute_status(NSString *txt, UIColor *clr) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (bruteLabel) {
            bruteLabel.text = [NSString stringWithFormat:@"VCAM BRUTE: %@", txt];
            bruteLabel.textColor = clr;
        }
    });
}

@interface VCamBruteManager : NSObject + (void)renderTick; @end
@implementation VCamBruteManager
+ (void)renderTick {
    if (!bruteOutput || !brutePlayer.currentItem) return;
    CMTime t = [brutePlayer.currentItem currentTime];
    CVPixelBufferRef pb = [bruteOutput copyPixelBufferForItemTime:t itemTimeForDisplay:NULL];
    if (pb) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:pb];
        if (ci) {
            bruteCIFrame = ci;
            CIContext *ctx = [CIContext contextWithOptions:nil];
            CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
            if (cg) {
                bruteSnapshot = [UIImage imageWithCGImage:cg];
                CGImageRelease(cg);
            }
        }
        CVPixelBufferRelease(pb);
    }
}
@end

static void start_brute_engine(NSString *u) {
    if (brutePlayer) { [brutePlayer pause]; [bruteLayer removeFromSuperlayer]; brutePlayer = nil; bruteLayer = nil; }
    
    log_brute_event([NSString stringWithFormat:@"ENGINE BOOT: %@", u]);
    NSURL *url = [NSURL URLWithString:u];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    
    bruteOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    [item addOutput:bruteOutput];
    
    brutePlayer = [AVPlayer playerWithPlayerItem:item];
    brutePlayer.automaticallyWaitsToMinimizeStalling = NO;
    
    bruteLayer = [AVPlayerLayer playerLayerWithPlayer:brutePlayer];
    bruteLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [brutePlayer play];
    
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:[VCamBruteManager class] selector:@selector(renderTick)];
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    log_brute_event(@"ENGINE BOOT SEQUENCE FINISHED");
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!bruteEnabled) return;
    if (!brutePlayer) start_brute_engine(bruteURL);
    if (bruteLayer && bruteLayer.superlayer != self) [self addSublayer:bruteLayer];
    if (bruteLayer) {
        bruteLayer.frame = self.bounds;
        bruteLayer.zPosition = 999999;
        
        AVCaptureSession *s = self.session; BOOL f = NO;
        for (AVCaptureInput *i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == AVCaptureDevicePositionFront) { f = YES; break; } }
        bruteLayer.transform = f ? CATransform3DMakeAffineTransform(CGAffineTransformMakeScale(-1, 1)) : CATransform3DIdentity;
        
        BOOL ready = brutePlayer.status == AVPlayerStatusReadyToPlay && brutePlayer.currentItem.status == AVPlayerItemStatusReadyToPlay;
        if (!ready) { set_brute_status(@"ENGINE CONNECTING...", [UIColor orangeColor]); }
        else { set_brute_status(f ? @"BRUTE ACTIVE (FRONT)" : @"BRUTE ACTIVE", [UIColor greenColor]); }
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (bruteEnabled && bruteSnapshot) { objc_setAssociatedObject(s, "vcamSnapshot", bruteSnapshot, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    UIImage *img = objc_getAssociatedObject(self.resolvedSettings, "vcamSnapshot");
    if (img) { log_brute_event(@"PHOTO HIJACK: OVERRIDING DATA"); return UIImageJPEGRepresentation(img, 0.9); }
    return %orig;
}
- (CGImageRef)CGImageRepresentation { UIImage *img = objc_getAssociatedObject(self.resolvedSettings, "vcamSnapshot"); if (img) return img.CGImage; return %orig; }
%end

%hook AVCaptureSession
- (void)startRunning {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (bruteWindow) return;
        bruteWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 100)];
        bruteWindow.windowLevel = UIWindowLevelAlert + 20;
        bruteWindow.userInteractionEnabled = NO;
        bruteWindow.hidden = NO;
        bruteLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 35, [UIScreen mainScreen].bounds.size.width, 30)];
        bruteLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        bruteLabel.textColor = [UIColor whiteColor];
        bruteLabel.font = [UIFont boldSystemFontOfSize:8];
        bruteLabel.textAlignment = NSTextAlignmentCenter;
        [bruteWindow addSubview:bruteLabel];
    });
}
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) { bruteEnabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES; if (p[@"rtspURL"]) bruteURL = p[@"rtspURL"]; }
    log_brute_event(@"VCAM V105.0 BRUTE LOADED");
}
