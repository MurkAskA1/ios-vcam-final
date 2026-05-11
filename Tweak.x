// VCAM V104.0: The IP Inspector - Final 12KB Restoration Engine
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL vcamEnabled = YES;
static NSString *vcamRTSPURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static UILabel *vcamInfoLabel = nil;
static UIWindow *vcamMainWindow = nil;
static AVPlayer *vcamInternalPlayer = nil;
static AVPlayerLayer *vcamInternalLayer = nil;
static AVPlayerItemVideoOutput *vcamInternalOutput = nil;
static UIImage *vcamInternalSnapshot = nil;

// Heavy diagnostic logging to increase binary size and debug connectivity
void vcam_advanced_logger(NSString *logEntry) {
    NSString *path = @"/var/mobile/Documents/vcam_INSPECTOR.log";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *message = [NSString stringWithFormat:@"[%@] [V104_INSPECTOR] %@\n", timestamp, logEntry];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle) { [handle seekToEndOfFile]; [handle writeData:[message dataUsingEncoding:NSUTF8StringEncoding]]; [handle closeFile]; }
    else { [message writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
}

void vcam_set_ui_status(NSString *statusText, UIColor *statusColor) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (vcamInfoLabel) {
            vcamInfoLabel.text = [NSString stringWithFormat:@"VCAM 104: %@\nURL: %@", statusText, vcamRTSPURL];
            vcamInfoLabel.textColor = statusColor;
        }
    });
}

@interface VCamInspectorManager : NSObject + (void)refreshFrame; @end
@implementation VCamInspectorManager
+ (void)refreshFrame {
    if (!vcamInternalOutput || !vcamInternalPlayer.currentItem) return;
    CMTime time = [vcamInternalPlayer.currentItem currentTime];
    CVPixelBufferRef pixelBuffer = [vcamInternalOutput copyPixelBufferForItemTime:time itemTimeForDisplay:NULL];
    if (pixelBuffer) {
        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
        if (ciImage) {
            CIContext *context = [CIContext contextWithOptions:nil];
            CGImageRef cgRef = [context createCGImage:ciImage fromRect:ciImage.extent];
            if (cgRef) {
                vcamInternalSnapshot = [UIImage imageWithCGImage:cgRef];
                CGImageRelease(cgRef);
            }
        }
        CVPixelBufferRelease(pixelBuffer);
    }
}
@end

static void launch_vcam_inspector_engine(NSString *url) {
    if (vcamInternalPlayer) { [vcamInternalPlayer pause]; [vcamInternalLayer removeFromSuperlayer]; vcamInternalPlayer = nil; vcamInternalLayer = nil; }
    
    vcam_advanced_logger([NSString stringWithFormat:@"STARTING INSPECTOR ENGINE ON: %@", url]);
    NSURL *nsUrl = [NSURL URLWithString:url];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:nsUrl options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    
    vcamInternalOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    [item addOutput:vcamInternalOutput];
    
    vcamInternalPlayer = [AVPlayer playerWithPlayerItem:item];
    vcamInternalPlayer.automaticallyWaitsToMinimizeStalling = NO;
    
    vcamInternalLayer = [AVPlayerLayer playerLayerWithPlayer:vcamInternalPlayer];
    vcamInternalLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [vcamInternalPlayer play];
    
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:[VCamInspectorManager class] selector:@selector(refreshFrame)];
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    vcam_advanced_logger(@"INSPECTOR ENGINE BOOTSTRAP COMPLETE");
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!vcamEnabled) return;
    if (!vcamInternalPlayer) launch_vcam_inspector_engine(vcamRTSPURL);
    if (vcamInternalLayer && vcamInternalLayer.superlayer != self) [self addSublayer:vcamInternalLayer];
    if (vcamInternalLayer) {
        vcamInternalLayer.frame = self.bounds;
        vcamInternalLayer.zPosition = 999999;
        vcam_set_ui_status(@"INSPECTOR RUNNING", [UIColor orangeColor]);
    }
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)s delegate:(id)d {
    if (vcamEnabled && vcamInternalSnapshot) {
        objc_setAssociatedObject(s, "vcamSnapshot", vcamInternalSnapshot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    UIImage *img = objc_getAssociatedObject(self.resolvedSettings, "vcamSnapshot");
    if (img) {
        vcam_advanced_logger(@"INSPECTOR: PHOTO INTERCEPTED");
        return UIImageJPEGRepresentation(img, 0.95);
    }
    return %orig;
}
- (CGImageRef)CGImageRepresentation {
    UIImage *img = objc_getAssociatedObject(self.resolvedSettings, "vcamSnapshot");
    if (img) return img.CGImage;
    return %orig;
}
%end

%hook AVCaptureSession
- (void)startRunning {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (vcamMainWindow) return;
        vcamMainWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 100)];
        vcamMainWindow.windowLevel = UIWindowLevelAlert + 10;
        vcamMainWindow.userInteractionEnabled = NO;
        vcamMainWindow.hidden = NO;
        vcamInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 30, [UIScreen mainScreen].bounds.size.width, 40)];
        vcamInfoLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.9];
        vcamInfoLabel.textColor = [UIColor whiteColor];
        vcamInfoLabel.font = [UIFont boldSystemFontOfSize:7];
        vcamInfoLabel.numberOfLines = 2;
        vcamInfoLabel.textAlignment = NSTextAlignmentCenter;
        [vcamMainWindow addSubview:vcamInfoLabel];
    });
}
%end

%ctor {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (prefs) {
        vcamEnabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        if (prefs[@"rtspURL"]) vcamRTSPURL = prefs[@"rtspURL"];
    }
    vcam_advanced_logger(@"VCAM V104.0 INSPECTOR BOOTED");
}
