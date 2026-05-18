#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Photos/Photos.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static CVPixelBufferRef gGlobalBuffer = NULL;

static void RefreshBuffer() {
    if (!gVideoOutput) return;
    CMTime vTime = [gPlayer.currentItem currentTime];
    if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
        CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
        if (pb) {
            if (gGlobalBuffer) CVPixelBufferRelease(gGlobalBuffer);
            gGlobalBuffer = pb;
        }
    }
}

%hook AVCapturePhoto
- (CVPixelBufferRef)pixelBuffer {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) return CVPixelBufferRetain(gGlobalBuffer);
    return %orig;
}

- (CVPixelBufferRef)previewPixelBuffer {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) return CVPixelBufferRetain(gGlobalBuffer);
    return %orig;
}

- (NSData *)fileDataRepresentation {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        CIContext *ctx = [CIContext contextWithOptions:nil];
        CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
        NSData *data = UIImageJPEGRepresentation([UIImage imageWithCGImage:cg], 0.95);
        if (cg) CGImageRelease(cg);
        return data;
    }
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        CIContext *ctx = [CIContext contextWithOptions:nil];
        return [ctx createCGImage:ci fromRect:ci.extent];
    }
    return %orig;
}
%end

%hook NSObject
- (void)captureOutput:(id)output didOutputSampleBuffer:(CMSampleBufferRef)sb fromConnection:(id)conn {
    if (enabled) {
        RefreshBuffer();
        if (gGlobalBuffer) {
            CMVideoFormatDescriptionRef fd;
            CMVideoFormatDescriptionCreateForImageBuffer(NULL, gGlobalBuffer, &fd);
            CMSampleTimingInfo ti = { kCMTimeInvalid, CMSampleBufferGetPresentationTimeStamp(sb), kCMTimeInvalid };
            CMSampleBufferRef fakeBuffer = NULL;
            CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, gGlobalBuffer, YES, NULL, NULL, fd, &ti, &fakeBuffer);
            %orig(output, fakeBuffer, conn);
            if (fakeBuffer) CFRelease(fakeBuffer);
            if (fd) CFRelease(fd);
            return;
        }
    }
    %orig;
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

        [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES block:^(NSTimer *t) { RefreshBuffer(); }];
    }
    
    for (CALayer *sub in self.superlayer.sublayers) {
        if ([sub isKindOfClass:[AVPlayerLayer class]]) {
            sub.frame = self.bounds;
        }
    }
}
%end
