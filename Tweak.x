#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static CVPixelBufferRef gGlobalBuffer = NULL;
static CIContext *gCIContext = nil;

static void RefreshBuffer() {
    if (!gVideoOutput || !enabled || !gPlayer) return;
    CMTime vTime = [gPlayer.currentItem currentTime];
    if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
        CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
        if (pb) {
            CVPixelBufferRef old = gGlobalBuffer;
            gGlobalBuffer = pb; 
            if (old) CVPixelBufferRelease(old);
        }
    }
}

// Глубокий перехват данных фото
%hook AVCapturePhoto

- (CVPixelBufferRef)pixelBuffer {
    if (enabled && gGlobalBuffer) return CVPixelBufferRetain(gGlobalBuffer);
    return %orig;
}

- (CVPixelBufferRef)previewPixelBuffer {
    if (enabled && gGlobalBuffer) return CVPixelBufferRetain(gGlobalBuffer);
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    if (enabled && gGlobalBuffer) {
        if (!gCIContext) gCIContext = [[CIContext alloc] initWithOptions:nil];
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        return [gCIContext createCGImage:ci fromRect:ci.extent];
    }
    return %orig;
}

- (NSData *)fileDataRepresentation {
    if (enabled && gGlobalBuffer) {
        if (!gCIContext) gCIContext = [[CIContext alloc] initWithOptions:nil];
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        CGImageRef cg = [gCIContext createCGImage:ci fromRect:ci.extent];
        if (cg) {
            UIImage *ui = [UIImage imageWithCGImage:cg];
            NSData *data = UIImageJPEGRepresentation(ui, 0.9);
            CGImageRelease(cg);
            return data;
        }
    }
    return %orig;
}
%end

// Хук на видеопоток (для Telegram/WhatsApp и прецизионного захвата фото)
%hook AVCaptureVideoDataOutput
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && gGlobalBuffer) {
        CMSampleBufferRef newSbuf = NULL;
        CMFormatDescriptionRef formatDesc = NULL;
        CMVideoFormatDescriptionCreateForImageBuffer(NULL, gGlobalBuffer, (CMVideoFormatDescriptionRef *)&formatDesc);
        CMSampleTimingInfo timing;
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &timing);
        CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, gGlobalBuffer, YES, NULL, NULL, (CMVideoFormatDescriptionRef)formatDesc, &timing, &newSbuf);
        if (newSbuf) {
            %orig(output, newSbuf, connection);
            CFRelease(newSbuf);
            if (formatDesc) CFRelease(formatDesc);
            return;
        }
    }
    %orig;
}
%end

// Основной хук для замены картинки на экране
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.hidden = YES;

    if (!gPlayer) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
        if (prefs) {
            enabled = [prefs[@"enabled"] boolValue];
            NSString *url = prefs[@"rtspURL"];
            if (url) streamURL = url;
        }
        
        gPlayer = [[AVPlayer alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
        [gPlayer.currentItem addOutput:gVideoOutput];
        [gPlayer play];

        AVPlayerLayer *pl = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
        pl.frame = self.bounds;
        pl.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.superlayer insertSublayer:pl above:self];

        [NSTimer scheduledTimerWithTimeInterval:0.03 repeats:YES block:^(NSTimer *t) {
            RefreshBuffer();
        }];
    }
}
%end

%ctor {
    %init;
}
