// VCAM V98.0: The 11KB Legacy Restoration - Zero Latency Engine
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
static CIImage *lastValidCIFrame = nil;

void vcam_log(NSString *message) {
    NSString *logPath = @"/var/mobile/Documents/vcam_LEGACY.log";
    NSString *formatted = [NSString stringWithFormat:@"%@\n", message];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (fh) { [fh seekToEndOfFile]; [fh writeData:[formatted dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    else { [formatted writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
}

void update_vcam_status(NSString *status, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (statusLabel) { statusLabel.text = [NSString stringWithFormat:@"VCAM LEGACY: %@", status]; statusLabel.textColor = color; }
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
        statusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        statusLabel.textColor = [UIColor whiteColor];
        statusLabel.font = [UIFont boldSystemFontOfSize:10];
        statusLabel.layer.cornerRadius = 6;
        statusLabel.clipsToBounds = YES;
        statusLabel.textAlignment = NSTextAlignmentCenter;
        [overlayWindow addSubview:statusLabel];
    });
}

@interface VCamEngine : NSObject + (void)captureFrame; @end
@implementation VCamEngine
+ (void)captureFrame {
    if (!vcamVideoOutput || !vcamPlayer.currentItem) return;
    CMTime itemTime = [vcamPlayer.currentItem currentTime];
    CVPixelBufferRef pb = [vcamVideoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:NULL];
    if (pb) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:pb];
        if (ci) {
            lastValidCIFrame = ci;
            CIContext *ctx = [CIContext contextWithOptions:nil];
            CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
            if (cg) { lastValidUIImage = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
        }
        CVPixelBufferRelease(pb);
    }
}
@end

static CADisplayLink *legacyLink = nil;
@interface VCamLegacyLink : NSObject + (void)tick; @end
@implementation VCamLegacyLink
+ (void)tick { [VCamEngine captureFrame]; }
@end

@interface VCamFreezeLayer : CALayer @end
@implementation VCamFreezeLayer
- (void)display {
    if (!lastValidCIFrame) return;
    CGImageRef cg = [[CIContext contextWithOptions:nil] createCGImage:lastValidCIFrame fromRect:lastValidCIFrame.extent];
    if (cg) { self.contents = (__bridge id)cg; CGImageRelease(cg); }
}
@end

static VCamFreezeLayer *freezeLayer = nil;
static void show_freeze(CALayer *parent, CGRect bounds) {
    if (!freezeLayer) { freezeLayer = [VCamFreezeLayer layer]; freezeLayer.zPosition = 9998; freezeLayer.contentsGravity = kCAGravityResizeAspectFill; }
    freezeLayer.frame = bounds;
    if (freezeLayer.superlayer != parent) [parent addSublayer:freezeLayer];
    [freezeLayer setNeedsDisplay];
}

static void setup_legacy_player(NSString *u) {
    if (vcamPlayer) { [vcamPlayer pause]; [vcamLayer removeFromSuperlayer]; vcamPlayer = nil; vcamLayer = nil; }
    NSURL *url = [NSURL URLWithString:u];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    item.automaticallyPreservesTimeOffsetFromLive = YES;
    item.configuredTimeOffsetFromLive = kCMTimeZero;
    
    vcamVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    [item addOutput:vcamVideoOutput];
    
    vcamPlayer = [AVPlayer playerWithPlayerItem:item];
    vcamPlayer.automaticallyWaitsToMinimizeStalling = NO;
    vcamPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    
    vcamLayer = [AVPlayerLayer playerLayerWithPlayer:vcamPlayer];
    vcamLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [vcamPlayer play];
    
    if (!legacyLink) {
        legacyLink = [CADisplayLink displayLinkWithTarget:[VCamLegacyLink class] selector:@selector(tick)];
        [legacyLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    vcam_log(@"Legacy Player Initialized");
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    if (!vcamPlayer) setup_legacy_player(rtspURL);
    if (vcamLayer && vcamLayer.superlayer != self) [self addSublayer:vcamLayer];
    if (vcamLayer) {
        vcamLayer.frame = self.bounds; vcamLayer.zPosition = 9999;
        AVCaptureSession *s = self.session; BOOL f = NO;
        for (AVCaptureInput *i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == AVCaptureDevicePositionFront) { f = YES; break; } }
        vcamLayer.transform = f ? CATransform3DMakeAffineTransform(CGAffineTransformMakeScale(-1, 1)) : CATransform3DIdentity;
        if (freezeLayer) freezeLayer.transform = vcamLayer.transform;
        
        BOOL ready = vcamPlayer.status == AVPlayerStatusReadyToPlay && vcamPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay;
        if (!ready) {
            if (lastValidCIFrame) { show_freeze(self, self.bounds); update_vcam_status(@"SIGNAL LOST", [UIColor orangeColor]); }
            else { vcamLayer.backgroundColor = [UIColor blackColor].CGColor; update_vcam_status(@"CONNECTING LEGACY...", [UIColor yellowColor]); }
        } else {
            if (freezeLayer) [freezeLayer removeFromSuperlayer];
            vcamLayer.backgroundColor = [UIColor clearColor].CGColor;
            update_vcam_status(f ? @"LEGACY ACTIVE (FRONT)" : @"LEGACY ACTIVE", [UIColor greenColor]);
        }
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
    if (snap) return UIImageJPEGRepresentation(snap, 0.95);
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
    vcam_log(@"VCAM V98.0 Legacy Ready");
}
