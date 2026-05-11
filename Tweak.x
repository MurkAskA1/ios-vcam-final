// VCAM V107.0: The KYC Pro Evolution - Advanced Hijack & Diagnostics
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL vcamEnabled = YES;
static NSString *vcamURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static AVPlayer *vcamPlayer = nil;
static AVPlayerLayer *vcamLayer = nil;
static AVPlayerItemVideoOutput *vcamOutput = nil;
static UIImage *vcamLatestImage = nil;
static UILabel *vcamHUD = nil;
static UIWindow *vcamWindow = nil;

void vcam_pro_log(NSString *msg) {
    NSString *p = @"/var/mobile/Documents/vcam_PRO.log";
    NSString *f = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (h) { [h seekToEndOfFile]; [h writeData:[f dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
    else { [f writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
}

void update_vcam_hud(NSString *txt, UIColor *clr) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (vcamHUD) {
            vcamHUD.text = [NSString stringWithFormat:@"VCAM PRO: %@", txt];
            vcamHUD.textColor = clr;
        }
    });
}

@interface VCamFrameGrabber : NSObject + (void)grabTick; @end
@implementation VCamFrameGrabber
+ (void)grabTick {
    if (!vcamOutput || !vcamPlayer.currentItem) return;
    CMTime t = [vcamPlayer.currentItem currentTime];
    CVPixelBufferRef pb = [vcamOutput copyPixelBufferForItemTime:t itemTimeForDisplay:NULL];
    if (pb) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:pb];
        CIContext *ctx = [CIContext contextWithOptions:nil];
        CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
        if (cg) {
            vcamLatestImage = [UIImage imageWithCGImage:cg];
            CGImageRelease(cg);
        }
        CVPixelBufferRelease(pb);
    }
}
@end

static void start_vcam_engine(NSString *u) {
    if (vcamPlayer) { [vcamPlayer pause]; [vcamLayer removeFromSuperlayer]; vcamPlayer = nil; vcamLayer = nil; }
    
    vcam_pro_log([NSString stringWithFormat:@"BOOTING ENGINE: %@", u]);
    vcamPlayer = [AVPlayer playerWithURL:[NSURL URLWithString:u]];
    vcamOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    [vcamPlayer.currentItem addOutput:vcamOutput];
    
    vcamLayer = [AVPlayerLayer playerLayerWithPlayer:vcamPlayer];
    vcamLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    vcamLayer.backgroundColor = [UIColor blueColor].CGColor;
    
    [vcamPlayer play];
    
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:[VCamFrameGrabber class] selector:@selector(grabTick)];
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    update_vcam_hud(@"CONNECTING...", [UIColor yellowColor]);
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!vcamEnabled) return;
    if (!vcamPlayer) start_vcam_engine(vcamURL);
    if (vcamLayer.superlayer != self) [self addSublayer:vcamLayer];
    vcamLayer.frame = self.bounds;
    vcamLayer.zPosition = 99999;
    
    AVCaptureSession *s = self.session; BOOL f = NO;
    for (AVCaptureInput *i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == AVCaptureDevicePositionFront) { f = YES; break; } }
    vcamLayer.transform = f ? CATransform3DMakeAffineTransform(CGAffineTransformMakeScale(-1, 1)) : CATransform3DIdentity;
    
    if (vcamPlayer.status == AVPlayerStatusReadyToPlay) update_vcam_hud(f ? @"PRO ACTIVE (FRONT)" : @"PRO ACTIVE", [UIColor greenColor]);
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (vcamEnabled && vcamLatestImage) objc_setAssociatedObject(s, "vcamSnap", vcamLatestImage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    UIImage *img = objc_getAssociatedObject(self.resolvedSettings, "vcamSnap");
    if (img) { vcam_pro_log(@"KYC HIJACK: Success"); return UIImageJPEGRepresentation(img, 0.95); }
    return %orig;
}
- (CGImageRef)CGImageRepresentation { UIImage *img = objc_getAssociatedObject(self.resolvedSettings, "vcamSnap"); if (img) return img.CGImage; return %orig; }
%end

%hook AVCaptureSession
- (void)startRunning {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (vcamWindow) return;
        vcamWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 100)];
        vcamWindow.windowLevel = UIWindowLevelAlert + 100;
        vcamWindow.userInteractionEnabled = NO;
        vcamWindow.hidden = NO;
        vcamHUD = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, [UIScreen mainScreen].bounds.size.width - 20, 30)];
        vcamHUD.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        vcamHUD.textColor = [UIColor whiteColor];
        vcamHUD.font = [UIFont boldSystemFontOfSize:10];
        vcamHUD.textAlignment = NSTextAlignmentCenter;
        vcamHUD.layer.cornerRadius = 8; vcamHUD.clipsToBounds = YES;
        [vcamWindow addSubview:vcamHUD];
    });
}
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        vcamEnabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) vcamURL = p[@"rtspURL"];
    }
    vcam_pro_log(@"VCAM V107.0 PRO LOADED");
}
