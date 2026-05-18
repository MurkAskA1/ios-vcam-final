#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Photos/Photos.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static CVPixelBufferRef gGlobalBuffer = NULL;
static dispatch_queue_t gBufferQueue;

static void RefreshBuffer() {
    if (!gVideoOutput || !enabled) return;
    
    dispatch_async(gBufferQueue, ^{
        CMTime vTime = [gPlayer.currentItem currentTime];
        if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
            CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
            if (pb) {
                CVPixelBufferRef old = gGlobalBuffer;
                gGlobalBuffer = pb; 
                if (old) CVPixelBufferRelease(old);
            }
        }
    });
}

// --- CAPTURE HIJACK ---
%hook AVCapturePhoto
- (CVPixelBufferRef)pixelBuffer {
    if (enabled && gGlobalBuffer) {
        return CVPixelBufferRetain(gGlobalBuffer);
    }
    return %orig;
}

- (NSData *)fileDataRepresentation {
    if (enabled && gGlobalBuffer) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        CIContext *ctx = [CIContext contextWithOptions:nil];
        CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
        NSData *data = UIImageJPEGRepresentation([UIImage imageWithCGImage:cg], 0.9);
        CGImageRelease(cg);
        return data;
    }
    return %orig;
}
%end

// --- GLOBAL STREAM HIJACK ---
%hook NSObject
- (void)captureOutput:(id)output didOutputSampleBuffer:(CMSampleBufferRef)sb fromConnection:(id)conn {
    if (enabled && gGlobalBuffer) {
        CMVideoFormatDescriptionRef fd;
        CMVideoFormatDescriptionCreateForImageBuffer(NULL, gGlobalBuffer, &fd);
        CMSampleTimingInfo ti = { kCMTimeInvalid, CMSampleBufferGetPresentationTimeStamp(sb), kCMTimeInvalid };
        CMSampleBufferRef fake = NULL;
        CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, gGlobalBuffer, YES, NULL, NULL, fd, &ti, &fake);
        
        %orig(output, fake, conn);
        
        if (fake) CFRelease(fake);
        if (fd) CFRelease(fd);
        return;
    }
    %orig;
}
%end

// --- PREVIEW HIJACK ---
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.hidden = YES;

    if (!gPlayer) {
        gBufferQueue = dispatch_queue_create("com.vcam.buffer", DISPATCH_QUEUE_SERIAL);
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