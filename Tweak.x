// VCAM V94.0: The Final Strike - Force MJPEG & Low-Level Photo Hijack
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

static CIImage *lastValidFrame = nil;
static UIImage *lastValidUIImage = nil;
static NSTimer *fallbackTimer = nil;
static BOOL usingFallback = NO;

void vcam_log(NSString *message) {
    NSString *logPath = @"/var/mobile/Documents/vcam_DEBUG.log";
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterLongStyle];
    NSString *formatted = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (fh) { [fh seekToEndOfFile]; [fh writeData:[formatted dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    else { [formatted writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
}

void update_vcam_status(NSString *status, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (statusLabel) { statusLabel.text = [NSString stringWithFormat:@"VCAM: %@", status]; statusLabel.textColor = color; }
    });
    vcam_log(status);
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

static CADisplayLink *frameGrabLink = nil;
@interface VCamFrameGrabber : NSObject
+ (void)tick:(CADisplayLink *)link;
@end
@implementation VCamFrameGrabber
+ (void)tick:(CADisplayLink *)link {
    if (!vcamVideoOutput || !vcamPlayer.currentItem) return;
    CMTime itemTime = [vcamPlayer.currentItem currentTime];
    if (![vcamVideoOutput hasNewPixelBufferForItemTime:itemTime]) return;
    CVPixelBufferRef pb = [vcamVideoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:NULL];
    if (pb) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:pb];
        if (ci) {
            lastValidFrame = ci;
            CIContext *ctx = [CIContext contextWithOptions:nil];
            CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
            if (cg) { lastValidUIImage = [UIImage imageWithCGImage:cg]; CGImageRelease(cg); }
        }
        CVPixelBufferRelease(pb);
    }
}
@end

static void start_grabbing(void) {
    if (frameGrabLink) return;
    frameGrabLink = [CADisplayLink displayLinkWithTarget:[VCamFrameGrabber class] selector:@selector(tick:)];
    [frameGrabLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

@interface VCamFreezeLayer : CALayer @end
@implementation VCamFreezeLayer
- (void)display {
    if (!lastValidFrame) return;
    CGImageRef cg = [[CIContext contextWithOptions:nil] createCGImage:lastValidFrame fromRect:lastValidFrame.extent];
    if (cg) { self.contents = (__bridge id)cg; CGImageRelease(cg); }
}
@end

static VCamFreezeLayer *freezeLayer = nil;
static void show_freeze(CALayer *parent, CGRect bounds) {
    if (!freezeLayer) { freezeLayer = [VCamFreezeLayer layer]; freezeLayer.zPosition = 998; freezeLayer.contentsGravity = kCAGravityResizeAspectFill; }
    freezeLayer.frame = bounds;
    if (freezeLayer.superlayer != parent) [parent addSublayer:freezeLayer];
    [freezeLayer setNeedsDisplay];
}

static BOOL is_front(AVCaptureVideoPreviewLayer *l) {
    AVCaptureSession *s = l.session;
    for (AVCaptureInput *i in s.inputs) { if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == AVCaptureDevicePositionFront) return YES; }
    return NO;
}

static void setup_player(NSString *u) {
    if (vcamPlayer) { [vcamPlayer pause]; [vcamLayer removeFromSuperlayer]; vcamPlayer = nil; vcamLayer = nil; }
    NSURL *url = [NSURL URLWithString:u];
    update_vcam_status([NSString stringWithFormat:@"CONN [%@]...", url.host], [UIColor yellowColor]);
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    vcamVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    [item addOutput:vcamVideoOutput];
    vcamPlayer = [AVPlayer playerWithPlayerItem:item];
    vcamLayer = [AVPlayerLayer playerLayerWithPlayer:vcamPlayer];
    vcamLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [vcamPlayer play];
    start_grabbing();
    if (!usingFallback) {
        [fallbackTimer invalidate];
        fallbackTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:NO block:^(NSTimer *timer) {
            if (usingFallback || vcamPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay) return;
            usingFallback = YES;
            NSString *fb = [rtspURL stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
            vcam_log(@"V94: HLS Timeout -> Force MJPEG");
            setup_player(fb);
        }];
    }
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    if (!vcamPlayer) setup_player(rtspURL);
    if (vcamLayer && vcamLayer.superlayer != self) [self addSublayer:vcamLayer];
    if (vcamLayer) {
        vcamLayer.frame = self.bounds; vcamLayer.zPosition = 999;
        BOOL f = is_front(self);
        vcamLayer.transform = f ? CATransform3DMakeAffineTransform(CGAffineTransformMakeScale(-1, 1)) : CATransform3DIdentity;
        if (freezeLayer) freezeLayer.transform = vcamLayer.transform;
        BOOL ready = vcamPlayer.status == AVPlayerStatusReadyToPlay && vcamPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay;
        if (!ready) {
            if (lastValidFrame) { show_freeze(self, self.bounds); update_vcam_status(@"SIGNAL LOST - FREEZING", [UIColor orangeColor]); }
        } else {
            if (freezeLayer) [freezeLayer removeFromSuperlayer];
            update_vcam_status(f ? @"STREAMING (FRONT)" : @"STREAMING ACTIVE", [UIColor greenColor]);
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
    if (snap) { vcam_log(@"Low-Level Photo Hijack Active"); return UIImageJPEGRepresentation(snap, 0.9); }
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
    vcam_log(@"VCAM V94.0 Ready");
}
