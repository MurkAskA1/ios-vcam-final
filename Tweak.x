#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerLayer *gPlayerLayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static CVPixelBufferRef gGlobalBuffer = NULL;
static UILabel *gStatusLabel = nil;

// Функция для принудительного захвата кадра из плеера
static void SyncFrame() {
    if (!gVideoOutput) return;
    CMTime vTime = [gPlayer.currentItem currentTime];
    CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
    if (pb) {
        if (gGlobalBuffer) CVPixelBufferRelease(gGlobalBuffer);
        gGlobalBuffer = pb; // Retained by copyPixelBuffer
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gStatusLabel) {
                gStatusLabel.text = @"VCam: ● LIVE";
                gStatusLabel.textColor = [UIColor greenColor];
            }
        });
    }
}

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

    self.hidden = YES; // Скрываем оригинал полностью

    if (!gPlayer) {
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:streamURL]];
        NSDictionary *attrs = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
        gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attrs];
        [item addOutput:gVideoOutput];

        gPlayer = [[AVPlayer alloc] initWithPlayerItem:item];
        gPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
        gPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [gPlayer play];

        UIView *container = (UIView *)self.delegate;
        if ([container isKindOfClass:[UIView class]]) {
            gStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, 200, 30)];
            gStatusLabel.textColor = [UIColor yellowColor];
            gStatusLabel.font = [UIFont boldSystemFontOfSize:14];
            gStatusLabel.text = @"VCam: Loading...";
            [container addSubview:gStatusLabel];
            
            [container.layer insertSublayer:gPlayerLayer above:self];
        }

        // Запускаем цикл постоянной синхронизации кадров (60 FPS)
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:[NSBlockOperation blockOperationWithBlock:^{ SyncFrame(); }] selector:@selector(main)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }

    gPlayerLayer.frame = self.bounds;
}
%end

// --- Глубокая подмена данных для приложений (Видео) ---
%hook NSObject
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
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

// --- ЖЕЛЕЗНАЯ ПОДМЕНА ФОТО (iOS 16) ---
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
        NSData *data = UIImageJPEGRepresentation([UIImage imageWithCGImage:cg], 0.95);
        if (cg) CGImageRelease(cg);
        return data;
    }
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    SyncFrame();
    if (enabled && gGlobalBuffer) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        CIContext *ctx = [CIContext contextWithOptions:nil];
        return [ctx createCGImage:ci fromRect:ci.extent];
    }
    return %orig;
}
%end
