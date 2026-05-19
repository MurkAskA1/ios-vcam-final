#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static CVPixelBufferRef gGlobalBuffer = NULL;

static void RefreshBuffer() {
    if (!gVideoOutput || !enabled) return;
    CMTime vTime = [gPlayer.currentItem currentTime];
    if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
        CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
        if (pb) {
            CVPixelBufferRef old = gGlobalBuffer;
            gGlobalBuffer = pb; 
            if (old) CVPixelBufferRelease(old);
        }
    }
}

@interface VCamFinalProxy : NSObject <AVCapturePhotoCaptureDelegate>
@property (nonatomic, strong) id originalDelegate;
@end

@implementation VCamFinalProxy
- (void)captureOutput:(AVCapturePhotoOutput *)output willBeginCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)settings {
    if ([self.originalDelegate respondsToSelector:_cmd]) [self.originalDelegate captureOutput:output willBeginCaptureForResolvedSettings:settings];
}
- (void)captureOutput:(AVCapturePhotoOutput *)output willCapturePhotoForResolvedSettings:(AVCaptureResolvedPhotoSettings *)settings {
    if ([self.originalDelegate respondsToSelector:_cmd]) [self.originalDelegate captureOutput:output willCapturePhotoForResolvedSettings:settings];
}
- (void)captureOutput:(AVCapturePhotoOutput *)output didCapturePhotoForResolvedSettings:(AVCaptureResolvedPhotoSettings *)settings {
    if ([self.originalDelegate respondsToSelector:_cmd]) [self.originalDelegate captureOutput:output didCapturePhotoForResolvedSettings:settings];
}
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    if ([self.originalDelegate respondsToSelector:_cmd]) [self.originalDelegate captureOutput:output didFinishProcessingPhoto:photo error:error];
}
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)settings error:(NSError *)error {
    if ([self.originalDelegate respondsToSelector:_cmd]) [self.originalDelegate captureOutput:output didFinishCaptureForResolvedSettings:settings error:error];
}
@end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (enabled && delegate && ![delegate isKindOfClass:[VCamFinalProxy class]]) {
        VCamFinalProxy *proxy = [[VCamFinalProxy alloc] init];
        proxy.originalDelegate = delegate;
        %orig(settings, proxy);
        return;
    }
    %orig;
}
%end

%hook AVCapturePhoto
- (CVPixelBufferRef)pixelBuffer {
    RefreshBuffer();
    return (enabled && gGlobalBuffer) ? CVPixelBufferRetain(gGlobalBuffer) : %orig;
}
- (NSData *)fileDataRepresentation {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        return UIImageJPEGRepresentation([UIImage imageWithCIImage:ci], 0.95);
    }
    return %orig;
}
%end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.hidden = YES;

    if (!gPlayer) {
        gPlayer = [[AVPlayer alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
        [gPlayer.currentItem addOutput:gVideoOutput];
        [gPlayer play];

        AVPlayerLayer *pl = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
        pl.frame = self.bounds;
        pl.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.superlayer insertSublayer:pl above:self];

        [NSTimer scheduledTimerWithTimeInterval:0.03 repeats:YES block:^(NSTimer *t) { RefreshBuffer(); }];
    }
}
%end