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

%hook PHAssetCreationRequest
+ (instancetype)creationRequestForAssetFromImage:(UIImage *)image {
    if (enabled) {
        RefreshBuffer();
        if (gGlobalBuffer) {
            CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
            UIImage *fakeImage = [UIImage imageWithCIImage:ci];
            return %orig(fakeImage);
        }
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
        NSDictionary *attrs = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
        gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attrs];
        [gPlayer.currentItem addOutput:gVideoOutput];
        [gPlayer play];

        AVPlayerLayer *pl = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
        pl.frame = self.bounds;
        pl.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.superlayer insertSublayer:pl above:self];

        NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0 repeats:YES block:^(NSTimer *timer) { RefreshBuffer(); }];
        [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
    }
    
    for (CALayer *sub in self.superlayer.sublayers) {
        if ([sub isKindOfClass:[AVPlayerLayer class]]) {
            sub.frame = self.bounds;
        }
    }
}
%end
