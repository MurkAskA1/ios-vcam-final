#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerLayer *gPlayerLayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;

static UIImage* GetCurrentFrame() {
    if (!gVideoOutput) return nil;
    CMTime vTime = [gPlayer.currentItem currentTime];
    if (![gVideoOutput hasNewPixelBufferForItemTime:vTime]) return nil;
    
    CVPixelBufferRef pixelBuffer = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
    if (!pixelBuffer) return nil;
    
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
    UIImage *uiImage = [UIImage imageWithCGImage:cgImage];
    
    CGImageRelease(cgImage);
    CVPixelBufferRelease(pixelBuffer);
    return uiImage;
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
        
        gPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
        gPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [gPlayer play];
    }

    gPlayerLayer.frame = self.bounds;
    if (gPlayerLayer.superlayer == nil && self.superlayer != nil) {
        [self.superlayer insertSublayer:gPlayerLayer above:self];
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled) {
        UIImage *frame = GetCurrentFrame();
        if (frame) return UIImageJPEGRepresentation(frame, 0.9);
    }
    return %orig;
}

- (CGImageRef)previewCGImageRepresentation {
    if (enabled) {
        UIImage *frame = GetCurrentFrame();
        if (frame) return frame.CGImage;
    }
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    if (enabled) {
        UIImage *frame = GetCurrentFrame();
        if (frame) return frame.CGImage;
    }
    return %orig;
}
%end
