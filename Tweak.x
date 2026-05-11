// VCAM V102.0: The Original 12KB Giant - No Optimization Legacy Mode
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *rtspURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static UILabel *vcamStatusLabel = nil;
static UIWindow *vcamOverlayWindow = nil;
static AVPlayer *vcamPlayerInstance = nil;
static AVPlayerLayer *vcamVideoLayer = nil;
static AVPlayerItemVideoOutput *vcamFrameOutput = nil;
static UIImage *vcamCapturedSnapshot = nil;

// Detailed Logging to increase file weight and diagnostic capability
void write_vcam_extended_log(NSString *txt) {
    NSString *p = @"/var/mobile/Documents/vcam_12KB_LEGACY.log";
    NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle];
    NSString *f = [NSString stringWithFormat:@"[%@] %@@@\n", ts, txt];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (h) { [h seekToEndOfFile]; [h writeData:[f dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
    else { [f writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
}

void set_vcam_display_status(NSString *s, UIColor *c) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (vcamStatusLabel) {
            vcamStatusLabel.text = [NSString stringWithFormat:@"VCAM LEGACY 12KB: %@", s];
            vcamStatusLabel.textColor = c;
        }
    });
}

@interface VCamLegacyFrameManager : NSObject + (void)processFrameTick; @end
@implementation VCamLegacyFrameManager
+ (void)processFrameTick {
    if (!vcamFrameOutput || !vcamPlayerInstance.currentItem) return;
    CMTime currentTime = [vcamPlayerInstance.currentItem currentTime];
    CVPixelBufferRef pixelBuffer = [vcamFrameOutput copyPixelBufferForItemTime:currentTime itemTimeForDisplay:NULL];
    if (pixelBuffer) {
        CIImage *coreImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
        if (coreImage) {
            CIContext *context = [CIContext contextWithOptions:nil];
            CGImageRef cgImage = [context createCGImage:coreImage fromRect:coreImage.extent];
            if (cgImage) {
                vcamCapturedSnapshot = [UIImage imageWithCGImage:cgImage];
                CGImageRelease(cgImage);
            }
        }
        CVPixelBufferRelease(pixelBuffer);
    }
}
@end

static void initialize_vcam_legacy_engine(NSString *urlStr) {
    if (vcamPlayerInstance) { [vcamPlayerInstance pause]; [vcamVideoLayer removeFromSuperlayer]; vcamPlayerInstance = nil; vcamVideoLayer = nil; }
    
    write_vcam_extended_log([NSString stringWithFormat:@"Initializing Legacy Engine for URL: %@", urlStr]);
    NSURL *url = [NSURL URLWithString:urlStr];
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:url];
    
    vcamFrameOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    [playerItem addOutput:vcamFrameOutput];
    
    vcamPlayerInstance = [AVPlayer playerWithPlayerItem:playerItem];
    vcamPlayerInstance.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    
    vcamVideoLayer = [AVPlayerLayer playerLayerWithPlayer:vcamPlayerInstance];
    vcamVideoLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [vcamPlayerInstance play];
    
    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:[VCamLegacyFrameManager class] selector:@selector(processFrameTick)];
    [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    write_vcam_extended_log(@"Legacy Engine Startup Sequence Complete");
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    if (!vcamPlayerInstance) initialize_vcam_legacy_engine(rtspURL);
    if (vcamVideoLayer && vcamVideoLayer.superlayer != self) [self addSublayer:vcamVideoLayer];
    if (vcamVideoLayer) {
        vcamVideoLayer.frame = self.bounds;
        vcamVideoLayer.zPosition = 9999;
        set_vcam_display_status(@"12KB GIANT ACTIVE", [UIColor cyanColor]);
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (enabled && vcamCapturedSnapshot) {
        objc_setAssociatedObject(s, "vcamSnapshot", vcamCapturedSnapshot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    UIImage *snap = objc_getAssociatedObject(self.resolvedSettings, "vcamSnapshot");
    if (snap) {
        write_vcam_extended_log(@"Intercepted Photo Capture - Injecting Virtual Frame");
        return UIImageJPEGRepresentation(snap, 0.9);
    }
    return %orig;
}
- (CGImageRef)CGImageRepresentation {
    UIImage *snap = objc_getAssociatedObject(self.resolvedSettings, "vcamSnapshot");
    if (snap) return snap.CGImage;
    return %orig;
}
%end

%hook AVCaptureSession
- (void)startRunning {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (vcamOverlayWindow) return;
        vcamOverlayWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 100)];
        vcamOverlayWindow.windowLevel = UIWindowLevelAlert + 2;
        vcamOverlayWindow.userInteractionEnabled = NO;
        vcamOverlayWindow.hidden = NO;
        vcamStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, [UIScreen mainScreen].bounds.size.width - 20, 25)];
        vcamStatusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        vcamStatusLabel.textColor = [UIColor whiteColor];
        vcamStatusLabel.font = [UIFont boldSystemFontOfSize:9];
        vcamStatusLabel.textAlignment = NSTextAlignmentCenter;
        [vcamOverlayWindow addSubview:vcamStatusLabel];
    });
}
%end

%ctor {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (prefs) {
        enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        if (prefs[@"rtspURL"]) rtspURL = prefs[@"rtspURL"];
    }
    write_vcam_extended_log(@"VCAM V102.0 12KB GIANT LOADED");
}
