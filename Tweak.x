// VCAM V99.0: Blue Screen Hero - Pure Original Logic Restoration
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *rtspURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static UILabel *statusLabel = nil;
static UIWindow *overlayWindow = nil;
static AVPlayer *vcamPlayer = nil;
static AVPlayerLayer *vcamLayer = nil;
static AVPlayerItemVideoOutput *vcamVideoOutput = nil;
static UIImage *lastValidUIImage = nil;

void vcam_log(NSString *message) {
    NSString *logPath = @"/var/mobile/Documents/vcam_ORIGINAL.log";
    NSString *formatted = [NSString stringWithFormat:@"%@\n", message];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (fh) { [fh seekToEndOfFile]; [fh writeData:[formatted dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    else { [formatted writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
}

void update_vcam_status(NSString *status, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (statusLabel) { statusLabel.text = [NSString stringWithFormat:@"VCAM ORIGINAL: %@", status]; statusLabel.textColor = color; }
    });
}

void setup_status_bar(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (overlayWindow) return;
        overlayWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 100)];
        overlayWindow.windowLevel = UIWindowLevelAlert + 2;
        overlayWindow.userInteractionEnabled = NO;
        overlayWindow.backgroundColor = [UIColor clearColor];
        overlayWindow.hidden = NO;
        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, [UIScreen mainScreen].bounds.size.width - 20, 25)];
        statusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        statusLabel.textColor = [UIColor whiteColor];
        statusLabel.font = [UIFont boldSystemFontOfSize:11];
        statusLabel.layer.cornerRadius = 6;
        statusLabel.clipsToBounds = YES;
        statusLabel.textAlignment = NSTextAlignmentCenter;
        [overlayWindow addSubview:statusLabel];
    });
}

@interface VCamEngine : NSObject + (void)tick; @end
@implementation VCamEngine
+ (void)tick {
    if (!vcamVideoOutput || !vcamPlayer.currentItem) return;
    CMTime t = [vcamPlayer.currentItem currentTime];
    CVPixelBufferRef pb = [vcamVideoOutput copyPixelBufferForItemTime:t itemTimeForDisplay:NULL];
    if (pb) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:pb];
        if (ci) {
            CIContext *ctx = [CIContext contextWithOptions:nil];
            CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
            if (cg) { lastValidUIImage = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
        }
        CVPixelBufferRelease(pb);
    }
}
@end

static void setup_player(NSString *u) {
    if (vcamPlayer) { [vcamPlayer pause]; [vcamLayer removeFromSuperlayer]; vcamPlayer = nil; vcamLayer = nil; }
    NSURL *url = [NSURL URLWithString:u];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    vcamVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    [item addOutput:vcamVideoOutput];
    vcamPlayer = [AVPlayer playerWithPlayerItem:item];
    vcamPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    vcamLayer = [AVPlayerLayer playerLayerWithPlayer:vcamPlayer];
    vcamLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [vcamPlayer play];
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:[VCamEngine class] selector:@selector(tick)];
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    vcam_log(@"Original Player Started");
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    if (!vcamPlayer) setup_player(rtspURL);
    if (vcamLayer && vcamLayer.superlayer != self) [self addSublayer:vcamLayer];
    if (vcamLayer) {
        vcamLayer.frame = self.bounds; vcamLayer.zPosition = 9999;
        AVCaptureSession *s = self.session; BOOL f = NO;
        for (AVCaptureInput *i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == AVCaptureDevicePositionFront) { f = YES; break; } }
        vcamLayer.transform = f ? CATransform3DMakeAffineTransform(CGAffineTransformMakeScale(-1, 1)) : CATransform3DIdentity;
        update_vcam_status(f ? @"ORIGINAL (FRONT)" : @"ORIGINAL ACTIVE", [UIColor greenColor]);
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (enabled && lastValidUIImage) { objc_setAssociatedObject(s, "vcamSnapshot", lastValidUIImage, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    UIImage *snap = objc_getAssociatedObject(self.resolvedSettings, "vcamSnapshot");
    if (snap) return UIImageJPEGRepresentation(snap, 0.9);
    return %orig;
}
- (CGImageRef)CGImageRepresentation { UIImage *snap = objc_getAssociatedObject(self.resolvedSettings, "vcamSnapshot"); if (snap) return snap.CGImage; return %orig; }
%end

%hook AVCaptureSession
- (void)startRunning { %orig; setup_status_bar(); }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) { enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES; if (p[@"rtspURL"]) rtspURL = p[@"rtspURL"]; }
    vcam_log(@"VCAM V99.0 Original Ready");
}
