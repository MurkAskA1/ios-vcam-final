#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerLayer *gPlayerLayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;

static CMSampleBufferRef CreateSampleBufferFromPixelBuffer(CVPixelBufferRef pixelBuffer, CMTime timestamp) {
    if (!pixelBuffer) return NULL;
    CMVideoFormatDescriptionRef formatDescription;
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &formatDescription);
    CMSampleTimingInfo timingInfo = { kCMTimeInvalid, timestamp, kCMTimeInvalid };
    CMSampleBufferRef sampleBuffer = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, YES, NULL, NULL, formatDescription, &timingInfo, &sampleBuffer);
    CFRelease(formatDescription);
    return sampleBuffer;
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;

    self.opacity = 0.0; 

    if (!gPlayer) {
        gPlayer = [[AVPlayer alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
        gPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        
        NSDictionary *pixBuffAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
        gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixBuffAttributes];
        [gPlayer.currentItem addOutput:gVideoOutput];

        [gPlayer play];
    }

    // Привязываем кадр строго к границам оригинального слоя
    gPlayerLayer.frame = self.bounds;
    if (gPlayerLayer.superlayer == nil && self.superlayer != nil) {
        [self.superlayer insertSublayer:gPlayerLayer above:self];
    }
}
%end

// --- Глубокая подмена данных для приложений ---
%hook NSObject
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && gVideoOutput) {
        CMTime vTime = [gPlayer.currentItem currentTime];
        CVPixelBufferRef pixelBuffer = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
        if (pixelBuffer) {
            CMSampleBufferRef fakeBuffer = CreateSampleBufferFromPixelBuffer(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
            if (fakeBuffer) {
                %orig(output, fakeBuffer, connection);
                CFRelease(fakeBuffer);
                CVPixelBufferRelease(pixelBuffer);
                return;
            }
            CVPixelBufferRelease(pixelBuffer);
        }
    }
    %orig;
}
%end
