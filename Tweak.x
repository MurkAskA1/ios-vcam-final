#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Photos/Photos.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static CVPixelBufferRef gGlobalBuffer = NULL;
static dispatch_semaphore_t gLock;

static void RefreshBuffer() {
    if (!gVideoOutput || !enabled) return;
    
    dispatch_semaphore_wait(gLock, DISPATCH_TIME_FOREVER);
    CMTime vTime = [gPlayer.currentItem currentTime];
    if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
        CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
        if (pb) {
            if (gGlobalBuffer) CVPixelBufferRelease(gGlobalBuffer);
            gGlobalBuffer = pb; 
        }
    }
    dispatch_semaphore_signal(gLock);
}

// --- GALLERY HIJACK ---
%hook PHAssetCreationRequest
+ (instancetype)creationRequestForAssetFromImage:(UIImage *)image {
    if (enabled && gGlobalBuffer) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        return %orig([UIImage imageWithCIImage:ci]);
    }
    return %orig;
}

+ (instancetype)creationRequestForAssetFromImageData:(NSData *)imageData {
    if (enabled && gGlobalBuffer) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        CIContext *ctx = [CIContext contextWithOptions:nil];
        CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
        NSData *fakeData = UIImageJPEGRepresentation([UIImage imageWithCGImage:cg], 0.95);
        CGImageRelease(cg);
        return %orig(fakeData);
    }
    return %orig;
}
%end

// --- CAPTURE HIJACK ---
%hook AVCapturePhoto
- (CVPixelBufferRef)pixelBuffer {
    return (enabled && gGlobalBuffer) ? CVPixelBufferRetain(gGlobalBuffer) : %orig;
}
- (CVPixelBufferRef)previewPixelBuffer {
    return (enabled && gGlobalBuffer) ? CVPixelBufferRetain(gGlobalBuffer) : %orig;
}
- (NSData *)fileDataRepresentation {
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

// --- PREVIEW HIJACK ---
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.hidden = YES;

    if (!gPlayer) {
        gLock = dispatch_semaphore_create(1);
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
} 
%end