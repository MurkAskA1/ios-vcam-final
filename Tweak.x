// VCAM V108.0: Zero Latency Pro - Enhanced Connectivity & HUD IP Monitor
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
            NSURL *u = [NSURL URLWithString:vcamURL];
            vcamHUD.text = [NSString stringWithFormat:@"VCAM PRO: %@\nTARGET: %@", txt, u.host];
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
        if (ci) {
            CIContext *ctx = [CIContext contextWithOptions:nil];
            CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
            if (cg) { vcamLatestImage = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
        }
        CVPixelBufferRelease(pb);
    }
}
@end

static void start_vcam_engine(NSString *u) {
    if (vcamPlayer) { [vcamPlayer pause]; [vcamLayer removeFromSuperlayer]; vcamPlayer = nil; vcamLayer = nil; }
    
    vcam_pro_log([NSString stringWithFormat:@"BOOTING ENGINE V108: %@", u]);
    NSURL *url = [NSURL URLWithString:u];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    
    vcamOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    [item addOutput:vcamOutput];
    
    vcamPlayer = [AVPlayer playerWithPlayerItem:item];
    vcamPlayer.automaticallyWaitsToMinimizeStalling = NO; // Zero Latency
    
    vcamLayer = [AVPlayerLayer playerLayerWithPlayer:vcamPlayer];
    vcamLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    vcamLayer.backgroundColor = [UIColor blueColor].CGColor;
    
    [vcamPlayer play];
    
    static CADisplayLink *link = nil;
    if (!link) {
        link = [CADisplayLink displayLinkWithTarget:[VCamFrameGrabber class] selector:@selector(grabTick)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    
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
    
    if (vcamPlayer.status == AVPlayerStatusReadyToPlay && vcamPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay) {
        update_vcam_hud(f ? @"PRO ACTIVE (FRONT)" : @"PRO ACTIVE", [UIColor greenColor]);
        vcamLayer.backgroundColor = [UIColor clearColor].CGColor;
    }
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
    if (img) return UIImageJPEGRepresentation(img, 0.95);
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
        vcamHUD = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, [UIScreen mainScreen].bounds.size.width - 20, 40)];
        vcamHUD.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        vcamHUD.textColor = [UIColor whiteColor];
        vcamHUD.font = [UIFont boldSystemFontOfSize:9];
        vcamHUD.numberOfLines = 2;
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
    vcam_pro_log(@"VCAM V108.0 PRO LOADED");
}
