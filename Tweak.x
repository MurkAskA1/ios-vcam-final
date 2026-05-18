#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerLayer *gPlayerLayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static CVPixelBufferRef gLastPixelBuffer = NULL;

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
        NSDictionary *pixBuffAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
        gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixBuffAttributes];
        [gPlayer.currentItem addOutput:gVideoOutput];
        [gPlayer play];
        
        AVPlayerLayer *pl = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
        pl.frame = self.bounds;
        pl.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.superlayer insertSublayer:pl above:self];
    }
}
%end

%hook NSObject
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && gVideoOutput) {
        CMTime vTime = [gPlayer.currentItem currentTime];
        if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
            CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
            if (pb) {
                if (gLastPixelBuffer) CVPixelBufferRelease(gLastPixelBuffer);
                gLastPixelBuffer = CVPixelBufferRetain(pb);
                CVPixelBufferRelease(pb);
            }
        }
        
        if (gLastPixelBuffer) {
            CMSampleBufferRef fake = CreateSampleBufferFromPixelBuffer(gLastPixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
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

%hook AVCapturePhoto
- (CVPixelBufferRef)pixelBuffer {
    if (enabled && gLastPixelBuffer) return CVPixelBufferRetain(gLastPixelBuffer);
    return %orig;
}

- (CVPixelBufferRef)previewPixelBuffer {
    if (enabled && gLastPixelBuffer) return CVPixelBufferRetain(gLastPixelBuffer);
    return %orig;
}

- (NSData *)fileDataRepresentation {
    if (enabled && gLastPixelBuffer) {
        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:gLastPixelBuffer];
        CIContext *context = [CIContext contextWithOptions:nil];
        CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
        NSData *data = UIImageJPEGRepresentation([UIImage imageWithCGImage:cgImage], 0.9);
        CGImageRelease(cgImage);
        return data;
    }
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    if (enabled && gLastPixelBuffer) {
        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:gLastPixelBuffer];
        CIContext *context = [CIContext contextWithOptions:nil];
        return [context createCGImage:ciImage fromRect:ciImage.extent];
    }
    return %orig;
}
%end
