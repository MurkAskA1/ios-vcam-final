#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES;
// ОБНОВИЛ ПУТЬ: добавил /stream и порт 8889 (стандарт MediaMTX для MJPEG)
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";

static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;
static UIImageView *gPreviewView = nil;
static UIView *gDebugPanel = nil;
static UILabel *gStatusLabel = nil;
static UILabel *gErrorLabel = nil;

// Лог теперь пишем в доступное место
#define LOG_PATH @"/var/mobile/Documents/vcam_debug.log"

void VLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[VCam] %@", msg);
    
    NSString *line = [NSString stringWithFormat:@"%@: %@\n", [NSDate date], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:LOG_PATH];
    if (!fh) {
        [line writeToFile:LOG_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

// --- Функция конвертации ---
CMSampleBufferRef CreateSampleBufferFromImage(UIImage *image, CMTime timestamp) {
    if (!image) return NULL;
    CGImageRef cgImage = image.CGImage;
    CVPixelBufferRef pxbuffer = NULL;
    NSDictionary *options = @{(id)kCVPixelBufferCGImageCompatibilityKey: @YES, (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES};
    CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &pxbuffer);
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pxbuffer), CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), 8, CVPixelBufferGetBytesPerRow(pxbuffer), CGColorSpaceCreateDeviceRGB(), kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)), cgImage);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    CMVideoFormatDescriptionRef formatDescription;
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, pxbuffer, &formatDescription);
    CMSampleTimingInfo timingInfo = { kCMTimeInvalid, timestamp, kCMTimeInvalid };
    CMSampleBufferRef sampleBuffer = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pxbuffer, YES, NULL, NULL, formatDescription, &timingInfo, &sampleBuffer);
    CFRelease(formatDescription);
    CVPixelBufferRelease(pxbuffer);
    return sampleBuffer;
}

// --- ХУКИ ---
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.opacity = 0.0;
    
    if (!gDebugPanel) {
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        gDebugPanel = [[UIView alloc] initWithFrame:CGRectMake(20, 50, 250, 100)];
        gDebugPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        gDebugPanel.layer.cornerRadius = 10;
        gDebugPanel.userInteractionEnabled = NO;
        
        gStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 230, 20)];
        gStatusLabel.textColor = [UIColor yellowColor];
        gStatusLabel.font = [UIFont boldSystemFontOfSize:12];
        gStatusLabel.text = @"Connecting to MediaMTX...";
        [gDebugPanel addSubview:gStatusLabel];
        
        UILabel *urlLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 35, 230, 15)];
        urlLbl.textColor = [UIColor whiteColor];
        urlLbl.font = [UIFont systemFontOfSize:10];
        urlLbl.text = streamURL;
        [gDebugPanel addSubview:urlLbl];

        gErrorLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 55, 230, 40)];
        gErrorLabel.textColor = [UIColor redColor];
        gErrorLabel.font = [UIFont systemFontOfSize:10];
        gErrorLabel.numberOfLines = 2;
        [gDebugPanel addSubview:gErrorLabel];
        
        [keyWindow addSubview:gDebugPanel];
        
        gPreviewView = [[UIImageView alloc] initWithFrame:[UIScreen mainScreen].bounds];
        gPreviewView.contentMode = UIViewContentModeScaleAspectFill;
        gPreviewView.backgroundColor = [UIColor blackColor];
        [keyWindow insertSubview:gPreviewView belowSubview:gDebugPanel];
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && gLastFrame) return UIImageJPEGRepresentation(gLastFrame, 0.9);
    return %orig;
}
%end

%hook NSObject
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && gLastFrame) {
        CMSampleBufferRef fake = CreateSampleBufferFromImage(gLastFrame, CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
        if (fake) { %orig(output, fake, connection); CFRelease(fake); return; }
    }
    %orig;
}
%end

%ctor {
    VLog(@"Tweak started. Target: %@", streamURL);
    gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
    gReader.frameCallback = ^(UIImage *f) {
        gLastFrame = f;
        dispatch_async(dispatch_get_main_queue(), ^{
            gStatusLabel.text = @"● LIVE (Receiving Frames)";
            gStatusLabel.textColor = [UIColor greenColor];
            gPreviewView.image = f;
            gErrorLabel.text = @"";
        });
    };
    gReader.errorCallback = ^(NSError *err) {
        VLog(@"Stream Error: %@", err.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{
            gStatusLabel.text = @"● STREAM ERROR";
            gStatusLabel.textColor = [UIColor redColor];
            gErrorLabel.text = err.localizedDescription;
        });
    };
    [gReader startStreaming];
}
