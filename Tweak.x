// VirtualCamPro Tweak Version 91.0 - Multi-Camera + Fallback + Mirror
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

// Freeze frame storage
static CIImage *lastValidFrame = nil;
static UIImage *lastValidUIImage = nil;

// Fallback timer
static NSTimer *fallbackTimer = nil;
static BOOL usingFallback = NO;

#pragma mark - Logging

void vcam_log(NSString *message) {
    NSString *logPath = @"/var/mobile/Documents/vcam_DEBUG.log";
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                             dateStyle:NSDateFormatterShortStyle
                                                             timeStyle:NSDateFormatterLongStyle];
    NSString *formatted = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (fi) {
        [fh seekToEndOfFile];
        [fh writeData:[formatted dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [formatted writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

#pragma mark - Status HUD

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
        overlayWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0,
                                                                     [UIScreen mainScreen].bounds.size.width, 100)];
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

#pragma mark - Freeze Frame grabber

static CADisplayLink *frameGrabLink = nil;

static void capture_current_frame(void) {
    if (!vcamVideoOutput || !vcamPlayer || !vcamPlayer.currentItem) return;
    CMTime itemTime = [vcamPlayer.currentItem currentTime];
    if (![vcamVideoOutput hasNewPixelBufferForItemTime:itemTime]) return;

    CVPixelBufferRef pb = [vcamVideoOutput copyPixelBufferForItemTime:itemTime
                                                       itemTimeForDisplay:NULL];
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
+ (void)start;
+ (void)stop;
+ (void)tick:(CADisplayLink *)link;
@end

@implementation VCamFrameGrabber
+ (void)start {
    if (frameGrabLink) return;
    frameGrabLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    frameGrabLink.preferredFramesPerSecond = 30;
    [frameGrabLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
+ (void)stop {
    [frameGrabLink invalidate];
    frameGrabLink = nil;
}
+ (void)tick:(CADisplayLink *)link {
    capture_current_frame();
}
@end

#pragma mark - Freeze Frame Layer

@interface VCamFreezeLayer : CALayer
@end

@implementation VCamFreezeLayer
- (void)display {
    if (!lastValidFrame) return;
    CIContext *ctx = [CIContext contextWithOptions:nil];
    CGImageRef cg = [ctx createCGImage:lastValidFrame fromRect:lastValidFrame.extent];
    if (cg) {
        self.contents = (__bridge id)cg;
        CGImageRelease(cg);
    }
}
@end

static VCamFreezeLayer *freezeLayer = nil;

static void show_freeze_layer(CALayer *parent, CGRect bounds) {
    if (!freezeLayer) {
        freezeLayer = [VCamFreezeLayer layer];
        freezeLayer.zPosition = 998;
        freezeLayer.contentsGravity = kCAGravityResizeAspectFill;
    }
    freezeLayer.frame = bounds;
    if (freezeLayer.superlayer != parent) {
        [parent addSublayer:freezeLayer];
    }
    [freezeLayer setNeedsDisplay];
}

#pragma mark - Front Camera Detection

static BOOL is_front_camera_active(AVCaptureVideoPreviewLayer *previewLayer) {
    AVCaptureSession *session = previewLayer.session;
    if (!session) return NO;
    for (AVCaptureInput *input in session.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
            if (deviceInput.device.position == AVCaptureDevicePositionFront) {
                return YES;
            }
        }
    }
    return NO;
}

#pragma mark - Fallback Logic

static void setup_vcam_player_with_url(NSString *url);

static void on_fallback_timer(void) {
    if (!vcamPlayer || !vcamPlayer.currentItem) return;
    if (vcamPlayer.currentItem.status == AVPlayerItemStatusReadyToPlay) return;
    if (usingFallback) return;

    usingFallback = YES;
    NSString *baseURL = rtspURL;
    NSString *fb = [baseURL stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
    if ([fb isEqualToString:baseURL]) {
        fb = fallbackURL;
    }
    vcam_log([NSString stringWithFormat:@"V91: HLS timeout, falling back to: %@", fb]);
    update_vcam_status(@"FALLBACK MJPEG...", [UIColor orangeColor]);
    setup_vcam_player_with_url(fb);
}

static void start_fallback_timer(void) {
    [fallbackTimer invalidate];
    fallbackTimer = nil;
    fallbackTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                        repeats:NO
                                                          block:^(NSTimer *t) {
        on_fallback_timer();
    }];
}

static void cancel_fallback_timer(void) {
    [fallbackTimer invalidate];
    fallbackTimer = nil;
}

#pragma mark - Player Setup

static void setup_vcam_player_with_url(NSString *url) {
    if (vcamPlayer) {
        [[NSNotificationCenter defaultCenter] removeObserver:vcamPlayer.currentItem];
        [vcamPlayer pause];
        [VCamFrameGrabber stop];
        vcamPlayer = nil;
        vcamLayer = nil;
        vcamVideoOutput = nil;
    }

    update_vcam_status(@"CONNECTING...", [UIColor yellowColor]);
    vcam_log([NSString stringWithFormat:@"V91: Loading URL: %@", url]);

    NSURL *nsurl = [NSURL URLWithString:url];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:nsurl];

    if (@available(iOS 15.0, *)) {
        item.preferredForwardBufferDuration = 1.0;
    }

    vcamPlayer = [AVPlayer playerWithPlayerItem:item];
    vcamPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    vcamPlayer.muted = YES;

    vcamLayer = [AVPlayerLayer playerLayerWithPlayer:vcamPlayer];
    vcamLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    NSDictionary *opts = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    vcamVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:opts];
    [item addOutput:vcamVideoOutput];

    [[NSNotificationCenter defaultCenter]
        addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification
                    object:item
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) {
        NSError *err = n.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
        NSString *errMsg = err ? err.localizedDescription : @"unknown error";
        vcam_log([NSString stringWithFormat:@"V91: Stream failed - %@", errMsg]);
        update_vcam_status(@"RECONNECTING...", [UIColor orangeColor]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{setup_vcam_player_with_url(url);});
    }];

    [[NSNotificationCenter defaultCenter]
        addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                    object:item
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) {
        [vcamPlayer seekToTime:kCMTimeZero];
        [vcamPlayer play];
    }];

    [vcamPlayer play];
    [VCamFrameGrabber start];
    start_fallback_timer();
}

static void setup_vcam_player(void) {
    usingFallback = NO;
    setup_vcam_player_with_url(rtspURL);
}

#pragma mark - Hooks

%£ook AVCaptureVideoPreviewLayer

- (void)layoutSublayers {
    %orig;
    if (!enabled) return;

    if (!vcamPlayer) {
        setup_vcam_player();
    }

    if (vcamPlayer.currentItem.error) {
        vcam_log([NSString stringWithFormat:@"V91: PlayerItem error: %@",
                  vcamPlayer.currentItem.error.localizedDescription]);
    }

    if (vcamLayer && vcamLayer.superlayer != self) {
        [self addSublayer:vcamLayer];
    }
    if (vcamLayer) {
        vcamLayer.frame = self.bounds;
        vcamLayer.zPosition = 999;
    }

    BOOL isFront = is_front_camera_active(self);
    if (isFront) {
        vcamLayer.transform = CATransform3DMakeAffineTransform(CGAffineTransformMakeScale(-1, 1));
        if (freezeLayer) {
            freezeLayer.transform = CATransform3DMakeAffineTransform(CGAffineTransformMakeScale(-1, 1));
        }
    } else {
        vcamLayer.transform = CATransform3DIdentity;
        if (freezeLayer) {
            freezeLayer.transform = CATransform3DIdentity;
        }
    }

    BOOL playerReady = vcamPlayer && (vcamPlayer.status == AVPayerStatusReadyToPlay);
    BOOL itemReady = vcamPlayer.currentItem &&
                     (vcamPlayer.currentItem.status == AVPayerItemStatusReadyToPlay);
    BOOL keepingUp = vcamPlayer.currentItem.isPlaybackLikelyToKeepUp;
    BOOL isBuffering = !playerReady || !itemReady || !keepingUp;

    if (isBuffering) {
        if (lastValidFrame) {
            show_freeze_layer(self, self.bounds);
            update_vcam_status(@"FREEZE FRAME (buffering)", [UIColor orangeColor]);
        } else {
            update_vcam_status(@"CONNECTING...", [UIColor yellowColor]);
        }
    } else {
        cancel_fallback_timer();
        if (freezeLayer && freezeLayer.superlayer) {
            [freezeLayer removeFromSuperlayer];
        }
        update_vcam_status(isFront ? @"STREAMING (FRONT)" : @"STREAMING ACTIVE", [UIColor greenColor]);
    }
}

%end

%hook AVCapturePhotoOutput

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings
                        delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (enabled && lastValidUIImage) {
        vcam_log(@"V91: Photo capture intercepted");
        objc_setAssociatedObject(settings, "vcamHijack", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIImage *frameSnapshot = lastValidUIImage;
        objc_setAssociatedObject(settings, "vcamSnapshot", frameSnapshot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
}

%end

%hook NSObject

- (void)captureOutput:(AVCapturePhotoOutput *)output
didFinishProcessingPhoto:(AVCapturePhoto *)photo
                error:(NSError *)error {
    if (enabled && !error) {
        UIImage *snap = objc_getAssociatedObject(output, "vcamSnapshot");
        if (!snap) snap = lastValidUIImage;
        if (snap) {
            NSData *jpeg = UIImageJPEGRepresentation(snap, 0.95);
            if (jpeg) {
                vcam_log(@"V91: Injecting virtual JPEG into AVCapturePhoto");
                objc_setAssociatedObject(photo, "vcamJPEGData", jpeg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
    %orig;
}

- (NSData *)fileDataRepresentation {
    NSData *override = objc_getAssociatedObject(self, "vcamJPEGData");
    if (override) {
        vcam_log(@"V91: fileDataRepresentation -> virtual frame served");
        return override;
    }
    return %orig;
}

%end

%hook AVCaptureSession

- (void)startRunning {
    %orig;
    vcam_log(@"Capture Session Started");
    setup_status_bar();
}

%end

#pragma mark - Preferences

static void loadPrefs(void) {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:
                       @"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) {
            rtspURL = p[@"rtspURL"];
            fallbackURL = [rtspURL stringByReplacingOccurrencesOfString:@"/index.m3u8" withString:@""];
        }
    }
}

%ctor {
    loadPrefs();
    vcam_log(@"Tweak Loaded - Version 91.0.0 Multi-Camera + Fallback + Mirror");
}
