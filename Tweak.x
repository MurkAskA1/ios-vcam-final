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
static dispatch_queue_t gSyncQueue;

static void RefreshBuffer() {
    if (!gVideoOutput || !enabled) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ gSyncQueue = dispatch_queue_create("com.vcam.sync", DISPATCH_QUEUE_SERIAL); });

    dispatch_async(gSyncQueue, ^{
        CMTime vTime = [gPlayer.currentItem currentTime];
        if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
            CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
            if (pb) {
                if (gGlobalBuffer) CVPixelBufferRelease(gGlobalBuffer);
                gGlobalBuffer = pb;
            }
        }
    });
}

@interface VCamProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id originalDelegate;
@end

@implementation VCamProxy
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        CMVideoFormatDescriptionRef fd;
        CMVideoFormatDescriptionCreateForImageBuffer(NULL, gGlobalBuffer, &fd);
        CMSampleTimingInfo ti = { kCMTimeInvalid, CMSampleBufferGetPresentationTimeStamp(sampleBuffer), kCMTimeInvalid };
        CMSampleBufferRef fakeBuffer = NULL;
        CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, gGlobalBuffer, YES, NULL, NULL, fd, &ti, &fakeBuffer);
        
        if ([self.originalDelegate respondsToSelector:_cmd]) {
            [self.originalDelegate captureOutput:output didOutputSampleBuffer:fakeBuffer fromConnection:connection];
        }
        
        if (fakeBuffer) CFRelease(fakeBuffer);
        if (fd) CFRelease(fd);
    } else {
        if ([self.originalDelegate respondsToSelector:_cmd]) {
            [self.originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        }
    }
}
@end

@interface VCamPhotoDelegate : NSObject <AVCapturePhotoCaptureDelegate>
@property (nonatomic, strong) id originalDelegate;
@end

@implementation VCamPhotoDelegate
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    if ([self.originalDelegate respondsToSelector:_cmd]) {
        [self.originalDelegate captureOutput:output didFinishProcessingPhoto:photo error:error];
    }
}
@end

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {
    if (enabled && delegate && ![delegate isKindOfClass:[VCamProxy class]]) {
        VCamProxy *proxy = [[VCamProxy alloc] init];
        proxy.originalDelegate = delegate;
        %orig(proxy, queue);
        return;
    }
    %orig;
}
%end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (enabled && delegate && ![delegate isKindOfClass:[VCamPhotoDelegate class]]) {
        VCamPhotoDelegate *proxy = [[VCamPhotoDelegate alloc] init];
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
- (CVPixelBufferRef)previewPixelBuffer {
    RefreshBuffer();
    return (enabled && gGlobalBuffer) ? CVPixelBufferRetain(gGlobalBuffer) : %orig;
}
- (NSData *)fileDataRepresentation {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        CIContext *ctx = [CIContext contextWithOptions:nil];
        CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
        NSData *data = UIImageJPEGRepresentation([UIImage imageWithCGImage:cg], 0.95);
        CGImageRelease(cg);
        return data;
    }
    return %orig;
}
%end

%hook PHAssetCreationRequest
+ (instancetype)creationRequestForAssetFromImage:(UIImage *)image {
    if (enabled && gGlobalBuffer) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        UIImage *fake = [UIImage imageWithCIImage:ci];
        return %orig(fake);
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

        [NSTimer scheduledTimerWithTimeInterval:0.02 repeats:YES block:^(NSTimer *t) { RefreshBuffer(); }];
    }
    for (CALayer *sub in self.superlayer.sublayers) {
        if ([sub isKindOfClass:[AVPlayerLayer class]]) sub.frame = self.bounds;
    }
}
%end