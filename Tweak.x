#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerLayer *gPlayerLayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static CVPixelBufferRef gGlobalBuffer = NULL;

static void UpdateGlobalBuffer() {
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

static CMSampleBufferRef CreateFakeSampleBuffer(CMSampleBufferRef original) {
    UpdateGlobalBuffer();
    if (!gGlobalBuffer) return NULL;

    CMVideoFormatDescriptionRef fd;
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, gGlobalBuffer, &fd);
    CMSampleTimingInfo ti = { kCMTimeInvalid, CMSampleBufferGetPresentationTimeStamp(original), kCMTimeInvalid };
    
    CMSampleBufferRef fake = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, gGlobalBuffer, YES, NULL, NULL, fd, &ti, &fake);
    
    CFRelease(fd);
    return fake;
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.hidden = YES;

    if (!gPlayer) {
        gPlayer = [[AVPlayer alloc] initWithURL:[NSURL URLWithString:streamURL]];
        NSDictionary *attrs = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
        gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attrs];
        [gPlayer.currentItem addOutput:gVideoOutput];
        [gPlayer play];

        gPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
        gPlayerLayer.frame = self.bounds;
        gPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.superlayer insertSublayer:gPlayerLayer above:self];
        
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:gPlayerLayer selector:@selector(setNeedsDisplay)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    gPlayerLayer.frame = self.bounds;
}
%end

%hook NSObject
- (void)captureOutput:(id)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(id)connection {
    if (enabled) {
        CMSampleBufferRef fake = CreateFakeSampleBuffer(sampleBuffer);
        if (fake) {
            %orig(output, fake, connection);
            CFRelease(fake);
            return;
        }
    }
    %orig;
}
%end

%hook AVCapturePhoto
- (CVPixelBufferRef)pixelBuffer {
    UpdateGlobalBuffer();
    if (enabled && gGlobalBuffer) return CVPixelBufferRetain(gGlobalBuffer);
    return %orig;
}
- (NSData *)fileDataRepresentation {
    UpdateGlobalBuffer();
    if (enabled && gGlobalBuffer) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        CIContext *ctx = [CIContext contextWithOptions:nil];
        CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
        NSData *data = UIImageJPEGRepresentation([UIImage imageWithCGImage:cg], 0.9);
        if (cg) CGImageRelease(cg);
        return data;
    }
    return %orig;
}
%end
