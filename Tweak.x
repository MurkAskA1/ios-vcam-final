// VCAM V92.0: Ultimate KYC & Front Cam Fix
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *rtspURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static NSString *fallbackURL = @"http://192.168.1.44:8889/live/stream";
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
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                         dateStyle:NSDateFormatterShortStyle
                                                         timeStyle:NSDateFormatterLongStyle];
    NSString *formatted = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[formatted dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [formatted writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

void update_vcam_status(NSString *status, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (statusLabel) {
            statusLabel.text = [NSString stringWithFormat:@"VCAM: %@", status];
            statusLabel.textColor = color;
        }
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

        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, 300, 25)];
        statusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
        statusLabel.textColor = [UIColor whiteColor];
        statusLabel.font = [UIFont boldSystemFontOfSize:12];
        statusLabel.layer.cornerRadius = 5;
        statusLabel.clipsToBounds = YES;
        statusLabel.textAlignment = NSTextAlignmentCenter;
        [overlayWindow addSubview:statusLabel];
        overlayWindow.hidden = !enabled;
    });
}

static CADisplayLink *frameGrabLink = nil;

static void capture_current_frame(void) {
    if (!vcamVideoOutput || !vcamPlayer || !vcamPlayer.currentItem) return;
    CMTime itemTime = [vcamPlayer.currentItem currentTime];
    if (![vcamVideoOutput hasNewPixelBufferForItemTime:itemTime]) return;

    CVPixelBufferRef pb = [vcamVideoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:NULL];
    if (!pb) return;

    CIImage *ci = [CIImage imageWithCVPixelBuffer:pb];
    if (ci) {
        lastValidFrame = ci;
        CIContext *ctx = [CIContext contextWithOptions:nil];
        CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
        if (cg) {
            lastValidUIImage = [UIImage imageWithCGImage:cg];
            CGImageRelease(cg);
        }
    }
    CVPixelBufferRelease(pb);
}

@interface VCamFrameGrabber : NSObject
+ (void)tick:(CADisplayLink *)link;
@end

@implementation VCamFrameGrabber
+ (void)tick:(CADisplayLink *)link {
    capture_current_frame();
}
@end

static void start_grabbing(void) {
    if (frameGrabLink) return;
    frameGrabLink = [CADisplayLink displayLinkWithTarget:[VCamFrameGrabber class] selector:@selector(tick:)];
    [frameGrabLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

static void stop_grabbing(void) {
    [frameGrabLink invalidate];
    frameGrabLink = nil;
}

@interface VCamFreezeLayer : CALayer
@end

@implementation VCamFreezeLayer
- (void)display {
    if (!lastValidFrame) return;
    CGImageRef cg = [[CIContext contextWithOptions:nil] createCGImage:lastValidFrame fromRect:lastValidFrame.extent];
    if (cg) {
        self.contents = (__bridge id)cg;
        CGImageRelease(cg);
    }
}
@end

static VCamFreezeLayer *freezeLayer = nil;
static void show_freeze_frame_layer(CALayer *parent, CGRect bounds) {
    if (!freezeLayer) {
        freezeLayer = [VCamFreezeLayer layer];
        freezeLayer.zPosition = 998;
        freezeLayer.contentsGravity = kCAGravityResizeAspectFill;
    }
    freezeLayer.frame = bounds;
    if (freezeLayer.superlayer != parent) [parent addSublayer:freezeLayer];
    [freezeLayer setNeedsDisplay];
}

static BOOL is_front_camera_active(AVCaptureVideoPreviewLayer *previewLayer) {
    AVCaptureSession *session = previewLayer.session;
    if (!session) return NO;
    for (AVCaptureInput *input in session.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
            if (deviceInput.device.position == AVCaptureDevicePositionFront) return YES;
        }
    }
    return NO;
}

static void setup_vcam_player_with_url(NSString *url);

static void setup_vcam_player_with_url(NSString *url) {
    if (vcamPlayer) {
        [vcamPlayer pause];
        stop_grabbing();
        vcamPlayer = nil;
    }
    update_vcam_status(@"CONNECTING...", [UIColor yellowColor]);
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:url]];
    vcamVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    [item addOutput:vcamVideoOutput];
    vcamPlayer = [AVPlayer playerWithPlayerItem:item];
    vcamLayer = [AVPlayerLayer playerLayerWithPlayer:vcamPlayer];
    vcamLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [vcamPlayer play];
    start_grabbing();

    if (!usingFallback) {
        [fallbackTimer invalidate];
        fallbackTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:NO block:^(NSTimer *timer) {
            if (usingFallback) return;
            if (vcamPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay) return;
            usingFallback = YES;
            NSString *fb = [rtspURL stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
            vcam_log(@"V92: HLS timeout, falling back to MJPEG");
            setup_vcam_player_with_url(fb);
        }];
    }
}

static void setup_vcam_player(void) {
    usingFallback = NO;
    setup_vcam_player_with_url(rtspURL);
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    if (!vcamPlayer) setup_vcam_player();
    if (vcamLayer && vcamLayer.superlayer != self) [self addSublayer:vcamLayer];
    if (vcamLayer) {
        vcamLayer.frame = self.bounds;
        vcamLayer.zPosition = 999;
        BOOL isFront = is_front_camera_active(self);
        vcamLayer.transform = isFront ? CATransform3DMakeAffineTransform(CGAffineTransformMakeScale(-1, 1)) : CATransform3DIdentity;
        if (freezeLayer) freezeLayer.transform = vcamLayer.transform;
        BOOL ready = vcamPlayer.status == AVPlayerStatusReadyToPlay && vcamPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay;
        if (!ready) {
            if (lastValidFrame) {
                show_freeze_frame_layer(self, self.bounds);
                update_vcam_status(@"FREEZE FRAME", [UIColor orangeColor]);
            } else {
                update_vcam_status(@"CONNECTING...", [UIColor yellowColor]);
            }
        } else {
            if (freezeLayer) [freezeLayer removeFromSuperlayer];
            update_vcam_status(isFront ? @"STREAMING (FRONT)" : @"STREAMING ACTIVE", [UIColor greenColor]);
        }
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id)delegate {
    if (enabled && lastValidUIImage) {
        objc_setAssociatedObject(settings, "vcamSnapshot", lastValidUIImage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    NSData *override = objc_getAssociatedObject(self, "vcamJPEGData");
    return override ? override : %orig;
}
%end

%hook NSObject
- (void)captureOutput:(id)output didFinishProcessingPhoto:(id)photo error:(id)error {
    if (enabled && !error && [photo isKindOfClass:objc_getClass("AVCapturePhoto")]) {
        if (lastValidUIImage) {
            NSData *jpeg = UIImageJPEGRepresentation(lastValidUIImage, 0.9);
            if (jpeg) objc_setAssociatedObject(photo, "vcamJPEGData", jpeg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    %orig;
}
%end

%hook AVCaptureSession
- (void)startRunning { %orig; setup_status_bar(); }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
    vcam_log(@"V92 Loaded");
}
