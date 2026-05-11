// VCAM V113.0: Window Diagnostics & Hybrid Fallback Engine
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static UIWindow *vcamVideoWindow = nil;
static AVPlayer *vcamPlayer = nil;
static AVPlayerLayer *vcamLayer = nil;
static UIImage *lastVFrame = nil;
static AVPlayerItemVideoOutput *vOutput = nil;
static UILabel *diagHUD = nil;

void v_log(NSString *m) {
    NSString *p = @"/var/mobile/Documents/vcam_WINDOW.log";
    NSString *f = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], m];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (h) { [h seekToEndOfFile]; [h writeData:[f dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
    else { [f writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
}

@interface VCamFrameLink : NSObject + (void)tick; @end
@implementation VCamFrameLink
+ (void)tick {
    if (!vOutput || !vcamPlayer.currentItem) return;
    CMTime t = [vcamPlayer.currentItem currentTime];
    CVPixelBufferRef pb = [vOutput copyPixelBufferForItemTime:t itemTimeForDisplay:NULL];
    if (pb) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:pb];
        CIContext *ctx = [CIContext contextWithOptions:nil];
        CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
        if (cg) { lastVFrame = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
        CVPixelBufferRelease(pb);
    }
}
@end

static void setup_master_window(void) {
    if (vcamVideoWindow) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        vcamVideoWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        vcamVideoWindow.windowLevel = UIWindowLevelAlert + 1000;
        vcamVideoWindow.backgroundColor = [UIColor blueColor];
        vcamVideoWindow.userInteractionEnabled = NO;
        vcamVideoWindow.hidden = NO;
        
        diagHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, [UIScreen mainScreen].bounds.size.width, 40)];
        diagHUD.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        diagHUD.textColor = [UIColor whiteColor];
        diagHUD.font = [UIFont boldSystemFontOfSize:10];
        diagHUD.textAlignment = NSTextAlignmentCenter;
        diagHUD.numberOfLines = 2;
        diagHUD.text = [NSString stringWithFormat:@"WINDOW ACTIVE\nSTREAM: %@", streamURL];
        [vcamVideoWindow addSubview:diagHUD];
        
        vcamPlayer = [AVPlayer playerWithURL:[NSURL URLWithString:streamURL]];
        vcamPlayer.automaticallyWaitsToMinimizeStalling = NO;
        vcamLayer = [AVPlayerLayer playerLayerWithPlayer:vcamPlayer];
        vcamLayer.frame = vcamVideoWindow.bounds;
        vcamLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [vcamVideoWindow.layer addSublayer:vcamLayer];
        
        vOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
        [vcamPlayer.currentItem addOutput:vOutput];
        [vcamPlayer play];
        
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:[VCamFrameLink class] selector:@selector(tick)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        v_log(@"Master Window & HUD Created");
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        setup_master_window();
        vcamVideoWindow.hidden = NO;
        self.opacity = 0.0;
        if (vcamPlayer.status == AVPlayerStatusReadyToPlay) {
            diagHUD.text = @"STREAMING ACTIVE";
            diagHUD.textColor = [UIColor greenColor];
        }
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (enabled && lastVFrame) objc_setAssociatedObject(s, "vcamS", lastVFrame, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    UIImage *snap = objc_getAssociatedObject(self.resolvedSettings, "vcamS");
    if (snap) { v_log(@"Photo Hijack Success"); return UIImageJPEGRepresentation(snap, 0.95); }
    return %orig;
}
- (CGImageRef)CGImageRepresentation { UIImage *snap = objc_getAssociatedObject(self.resolvedSettings, "vcamS"); if (snap) return snap.CGImage; return %orig; }
%end

%hook AVCaptureSession
- (void)stopRunning { %orig; if (vcamVideoWindow) vcamVideoWindow.hidden = YES; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) streamURL = p[@"rtspURL"];
    }
    v_log(@"VCAM V113.0 Loaded");
}
