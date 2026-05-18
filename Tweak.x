#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerLayer *gPlayerLayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static CVPixelBufferRef gGlobalBuffer = NULL;

void RefreshGlobalBuffer() {
    if (!gVideoOutput) return;
    CMTime vTime = [gPlayer.currentItem currentTime];
    if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
        CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
        if (pb) {
            if (gGlobalBuffer) CVPixelBufferRelease(gGlobalBuffer);
            gGlobalBuffer = CVPixelBufferRetain(pb);
            CVPixelBufferRelease(pb);
        }
    }
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.hidden = YES;

    if (!gPlayer) {
        gPlayer = [[AVPlayer alloc] initWithURL:[NSURL URLWithString:streamURL]];
        NSDictionary *pixBuffAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
        gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixBuffAttributes];
        [gPlayer.currentItem addOutput:gVideoOutput];
        [gPlayer play];

        gPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
        gPlayerLayer.frame = self.bounds;
        gPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.superlayer insertSublayer:gPlayerLayer above:self];
    }
    gPlayerLayer.frame = self.bounds;
}
%end

%hook AVCapturePhoto
- (CVPixelBufferRef)pixelBuffer {
    RefreshGlobalBuffer();
    if (enabled && gGlobalBuffer) return CVPixelBufferRetain(gGlobalBuffer);
    return %orig;
}

- (NSData *)fileDataRepresentation {
    RefreshGlobalBuffer();
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

%hook NSObject
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled) {
        RefreshGlobalBuffer();
        if (gGlobalBuffer) {
            CMVideoFormatDescriptionRef fd;
            CMVideoFormatDescriptionCreateForImageBuffer(NULL, gGlobalBuffer, &fd);
            CMSampleTimingInfo ti = { kCMTimeInvalid, CMSampleBufferGetPresentationTimeStamp(sampleBuffer), kCMTimeInvalid };
            CMSampleBufferRef fake;
            CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, gGlobalBuffer, YES, NULL, NULL, fd, &ti, &fake);
            %orig(output, fake, connection);
            CFRelease(fake);
            CFRelease(fd);
            return;
        }
    }
    %orig;
}
%end
