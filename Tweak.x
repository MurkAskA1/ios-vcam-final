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

// Хук на сам объект фотографии
%hook AVCapturePhoto

- (CVPixelBufferRef)pixelBuffer {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        NSLog(@"[VCP] Spoofing photo pixelBuffer");
        return CVPixelBufferRetain(gGlobalBuffer);
    }
    return %orig;
}

- (CVPixelBufferRef)previewPixelBuffer {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        return CVPixelBufferRetain(gGlobalBuffer);
    }
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        if (!gCIContext) gCIContext = [[CIContext alloc] initWithOptions:nil];
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        return [gCIContext createCGImage:ci fromRect:ci.extent];
    }
    return %orig;
}

- (NSData *)fileDataRepresentation {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        NSLog(@"[VCP] Spoofing fileDataRepresentation");
        if (!gCIContext) gCIContext = [[CIContext alloc] initWithOptions:nil];
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        CGImageRef cg = [gCIContext createCGImage:ci fromRect:ci.extent];
        if (cg) {
            UIImage *ui = [UIImage imageWithCGImage:cg];
            NSData *data = UIImageJPEGRepresentation(ui, 0.8);
            CGImageRelease(cg);
            return data;
        }
    }
    return %orig;
}

%end

// Хук для старых систем и некоторых сторонних приложений
%hook AVCaptureStillImageOutput
- (void)captureStillImageAsynchronouslyFromConnection:(id)connection completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler {
    if (enabled && gGlobalBuffer) {
        CMSampleBufferRef sbuf = NULL;
        CMVideoFormatDescriptionRef formatDesc = NULL;
        CMVideoFormatDescriptionCreateForImageBuffer(NULL, gGlobalBuffer, &formatDesc);
        CMSampleTimingInfo timing = { kCMTimeInvalid, kCMTimeInvalid, kCMTimeInvalid };
        CMSampleBufferCreateForImageBuffer(NULL, gGlobalBuffer, YES, NULL, NULL, formatDesc, &timing, &sbuf);
        if (sbuf) {
            handler(sbuf, nil);
            CFRelease(sbuf);
            if (formatDesc) CFRelease(formatDesc);
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
