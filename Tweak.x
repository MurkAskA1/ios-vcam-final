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
static CIContext *gCIContext = nil;
static dispatch_semaphore_t gBufferSemaphore;

static void RefreshBufferSync() {
    if (!gVideoOutput || !enabled) return;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ 
        gBufferSemaphore = dispatch_semaphore_create(1); 
        gCIContext = [CIContext contextWithOptions:nil];
    });

    CMTime vTime = [gPlayer.currentItem currentTime];
    if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
        CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
        if (pb) {
            dispatch_semaphore_wait(gBufferSemaphore, DISPATCH_TIME_FOREVER);
            if (gGlobalBuffer) CVPixelBufferRelease(gGlobalBuffer);
            gGlobalBuffer = pb; 
            dispatch_semaphore_signal(gBufferSemaphore);
        }
    }
}

// --- PROXY DELEGATE FOR PHOTO SAVING ---
@interface VCamPhotoDelegate : NSObject <AVCapturePhotoCaptureDelegate>
@property (nonatomic, strong) id originalDelegate;
@end

@implementation VCamPhotoDelegate
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    // We let the system finish processing. Our hooks on AVCapturePhoto will supply the fake data.
    if ([self.originalDelegate respondsToSelector:_cmd]) {
        [self.originalDelegate captureOutput:output didFinishProcessingPhoto:photo error:error];
    }
}
@end

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
    RefreshBufferSync();
    dispatch_semaphore_wait(gBufferSemaphore, DISPATCH_TIME_FOREVER);
    CVPixelBufferRef pb = (enabled && gGlobalBuffer) ? CVPixelBufferRetain(gGlobalBuffer) : NULL;
    dispatch_semaphore_signal(gBufferSemaphore);
    return pb ? pb : %orig;
}

- (NSData *)fileDataRepresentation {
    RefreshBufferSync();
    dispatch_semaphore_wait(gBufferSemaphore, DISPATCH_TIME_FOREVER);
    CVPixelBufferRef pb = (enabled && gGlobalBuffer) ? CVPixelBufferRetain(gGlobalBuffer) : NULL;
    dispatch_semaphore_signal(gBufferSemaphore);

    if (pb) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:pb];
        CGImageRef cg = [gCIContext createCGImage:ci fromRect:ci.extent];
        UIImage *ui = [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp];
        NSData *data = UIImageJPEGRepresentation(ui, 0.95);
        if (cg) CGImageRelease(cg);
        CVPixelBufferRelease(pb);
        return data;
    }
    return %orig;
}
%end

// --- DEEPER GALLERY HOOK ---
%hook PHAssetCreationRequest
+ (instancetype)creationRequestForAssetFromImage:(UIImage *)image {
    if (enabled) {
        RefreshBufferSync();
        dispatch_semaphore_wait(gBufferSemaphore, DISPATCH_TIME_FOREVER);
        CVPixelBufferRef pb = gGlobalBuffer ? CVPixelBufferRetain(gGlobalBuffer) : NULL;
        dispatch_semaphore_signal(gBufferSemaphore);
        if (pb) {
            CIImage *ci = [CIImage imageWithCVPixelBuffer:pb];
            CGImageRef cg = [gCIContext createCGImage:ci fromRect:ci.extent];
            UIImage *fake = [UIImage imageWithCGImage:cg];
            CGImageRelease(cg);
            CVPixelBufferRelease(pb);
            return %orig(fake);
        }
    }
    return %orig;
}

+ (instancetype)creationRequestForAssetFromImageData:(NSData *)imageData {
    if (enabled) {
        RefreshBufferSync();
        dispatch_semaphore_wait(gBufferSemaphore, DISPATCH_TIME_FOREVER);
        CVPixelBufferRef pb = gGlobalBuffer ? CVPixelBufferRetain(gGlobalBuffer) : NULL;
        dispatch_semaphore_signal(gBufferSemaphore);
        if (pb) {
            CIImage *ci = [CIImage imageWithCVPixelBuffer:pb];
            CGImageRef cg = [gCIContext createCGImage:ci fromRect:ci.extent];
            NSData *fakeData = UIImageJPEGRepresentation([UIImage imageWithCGImage:cg], 0.95);
            CGImageRelease(cg);
            CVPixelBufferRelease(pb);
            return %orig(fakeData);
        }
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

        [NSTimer scheduledTimerWithTimeInterval:0.033 repeats:YES block:^(NSTimer *t) { RefreshBufferSync(); }];
    }
}
%end