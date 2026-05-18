#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static UILabel *gDebugLabel = nil;

// Функция для создания системного буфера из кадра плеера
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
    self.opacity = 0.0; // Скрываем оригинал

    UIView *container = (UIView *)self.delegate;
    if ([container isKindOfClass:[UIView class]] && !gPlayer) {
        // Инициализируем плеер для захвата кадров
        gPlayer = [AVPlayer playerWithURL:[NSURL URLWithString:streamURL]];
        
        // Магия: создаем выход для получения сырых кадров из видео
        NSDictionary *pixBuffAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
        gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixBuffAttributes];
        [gPlayer.currentItem addOutput:gVideoOutput];
        
        [gPlayer play];

        // Маленький индикатор в углу для вас
        gDebugLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, 100, 20)];
        gDebugLabel.textColor = [UIColor greenColor];
        gDebugLabel.font = [UIFont boldSystemFontOfSize:10];
        gDebugLabel.text = @"VCAM INJECTED";
        [container addSubview:gDebugLabel];
    }
}
%end

// --- СИСТЕМНАЯ ПОДМЕНА ВИДЕО ---
%hook NSObject
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && gVideoOutput) {
        CMTime vTime = [gPlayer.currentItem currentTime];
        if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
            CVPixelBufferRef pixelBuffer = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
            if (pixelBuffer) {
                // Создаем поддельный буфер с таймингом реальной камеры
                CMSampleBufferRef fakeBuffer = CreateSampleBufferFromPixelBuffer(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
                if (fakeBuffer) {
                    // ОТПРАВЛЯЕМ СИСТЕМЕ НАШ КАДР
                    %orig(output, fakeBuffer, connection);
                    CFRelease(fakeBuffer);
                    CVPixelBufferRelease(pixelBuffer);
                    return;
                }
                CVPixelBufferRelease(pixelBuffer);
            }
        }
    }
    %orig;
}
%end

// --- СИСТЕМНАЯ ПОДМЕНА ФОТО ---
%hook AVCapturePhoto
- (CGImageRef)CGImageRepresentation {
    if (enabled && gVideoOutput) {
        CMTime vTime = [gPlayer.currentItem currentTime];
        CVPixelBufferRef pixelBuffer = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
        if (pixelBuffer) {
            CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
            CIContext *context = [CIContext contextWithOptions:nil];
            CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
            CVPixelBufferRelease(pixelBuffer);
            return cgImage; // Возвращаем кадр из стрима вместо фото
        }
    }
    return %orig;
}
%end
