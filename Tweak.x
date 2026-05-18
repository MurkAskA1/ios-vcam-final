#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerLayer *gPlayerLayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static CVPixelBufferRef gGlobalBuffer = NULL;

// Функция синхронизации кадра
static void SyncFrame() {
    if (!gVideoOutput) return;
    CMTime vTime = [gPlayer.currentItem currentTime];
    if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
        CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
        if (pb) {
            if (gGlobalBuffer) CVPixelBufferRelease(gGlobalBuffer);
            gGlobalBuffer = pb; // copyPixelBuffer уже дает +1 к retain count
        }
    }
}

// Функция создания буфера для системы
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
    
    self.hidden = YES; // Прячем системное превью

    if (!gPlayer) {
        NSURL *url = [NSURL URLWithString:streamURL];
        gPlayer = [[AVPlayer alloc] initWithURL:url];
        
        NSDictionary *pixBuffAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
        gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixBuffAttributes];
        [gPlayer.currentItem addOutput:gVideoOutput];

        gPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
        gPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [gPlayer play];
    }

    if (gPlayerLayer) {
        gPlayerLayer.frame = self.bounds;
        if (gPlayerLayer.superlayer == nil && self.superlayer != nil) {
            [self.superlayer insertSublayer:gPlayerLayer above:self];
        }
    }
}
%end

// Глубокая подмена видеоданных
%hook NSObject
- (void)captureOutput:(id)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(id)connection {
    if (enabled) {
        SyncFrame();
        if (gGlobalBuffer) {
            CMSampleBufferRef fake = CreateSampleBufferFromPixelBuffer(gGlobalBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
            if (fake) {
                %orig(output, fake, connection);
                CFRelease(fake);
                return;
            }
        }
    }
    %orig;
}
%end

// Подмена фото
%hook AVCapturePhoto
- (CVPixelBufferRef)pixelBuffer {
    SyncFrame();
    if (enabled && gGlobalBuffer) return CVPixelBufferRetain(gGlobalBuffer);
    return %orig;
}

- (NSData *)fileDataRepresentation {
    SyncFrame();
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
