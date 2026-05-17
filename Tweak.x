#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live";

static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;
static UIImageView *gPreviewView = nil;

// UI Labels for Debugging
static UILabel *gStatusLabel = nil;
static UILabel *gUrlLabel = nil;
static UILabel *gStatsLabel = nil;
static UILabel *gErrorDetailLabel = nil;

// Logging helper
#define VLog(fmt, ...) NSLog(@"[VCamTweak] " fmt, ##__VA_ARGS__)

CMSampleBufferRef CreateSampleBufferFromImage(UIImage *image, CMTime timestamp) {
    if (!image) return NULL;
    CGImageRef cgImage = image.CGImage;
    CVPixelBufferRef pxbuffer = NULL;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    NSDictionary *options = @{(id)kCVPixelBufferCGImageCompatibilityKey: @YES, (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES};
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &pxbuffer);
    if (status != kCVReturnSuccess) return NULL;
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, width, height, 8, CVPixelBufferGetBytesPerRow(pxbuffer), rgbColorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGColorSpaceRelease(rgbColorSpace);
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

void UpdateDebugUI() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gStatsLabel && gReader) {
            gStatsLabel.text = [NSString stringWithFormat:@"Frames: %lu | URL: %s", (unsigned long)gReader.frameCount, gReader.isConnecting ? "Connecting" : "Idle"];
        }
    });
}

// --- ХУК 1: Подмена превью на экране ---
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    
    self.opacity = 0.0;
    UIView *container = (UIView *)self.delegate;
    
    if ([container isKindOfClass:[UIView class]]) {
        if (!gPreviewView) {
            VLog(@"Creating Debug UI on preview layer");
            gPreviewView = [[UIImageView alloc] initWithFrame:container.bounds];
            gPreviewView.contentMode = UIViewContentModeScaleAspectFill;
            gPreviewView.backgroundColor = [UIColor blackColor];
            [container insertSubview:gPreviewView atIndex:0];
            
            gStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, 200, 20)];
            gStatusLabel.font = [UIFont boldSystemFontOfSize:12];
            gStatusLabel.textColor = [UIColor yellowColor];
            [container addSubview:gStatusLabel];

            gUrlLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 60, container.bounds.size.width - 20, 20)];
            gUrlLabel.font = [UIFont systemFontOfSize:10];
            gUrlLabel.textColor = [UIColor whiteColor];
            gUrlLabel.text = [NSString stringWithFormat:@"URL: %@", streamURL];
            [container addSubview:gUrlLabel];

            gStatsLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 80, 200, 20)];
            gStatsLabel.font = [UIFont systemFontOfSize:10];
            gStatsLabel.textColor = [UIColor cyanColor];
            [container addSubview:gStatsLabel];

            gErrorDetailLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 100, container.bounds.size.width - 20, 40)];
            gErrorDetailLabel.font = [UIFont systemFontOfSize:10];
            gErrorDetailLabel.textColor = [UIColor redColor];
            gErrorDetailLabel.numberOfLines = 2;
            [container addSubview:gErrorDetailLabel];
        }
        gPreviewView.frame = container.bounds;
        if (gLastFrame) gPreviewView.image = gLastFrame;
    }
}
%end

// --- ХУК 2: Подмена ФОТО ---
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && gLastFrame) {
        VLog(@"Injecting frame into photo representation");
        return UIImageJPEGRepresentation(gLastFrame, 0.95);
    }
    return %orig;
}
%end

// --- ХУК 3: ГЛУБОКАЯ ПОДМЕНА ---
%hook NSObject
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && gLastFrame) {
        CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        CMSampleBufferRef fakeBuffer = CreateSampleBufferFromImage(gLastFrame, timestamp);
        if (fakeBuffer) {
            %orig(output, fakeBuffer, connection);
            CFRelease(fakeBuffer);
            return;
        }
    }
    %orig;
}
%end

%ctor {
    VLog(@"Tweak loading... Connecting to %@", streamURL);
    gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
    
    gReader.frameCallback = ^(UIImage *f) {
        gLastFrame = f;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gStatusLabel) gStatusLabel.text = @"● LIVE";
            if (gStatusLabel) gStatusLabel.textColor = [UIColor greenColor];
            if (gPreviewView) gPreviewView.image = f;
            if (gErrorDetailLabel) gErrorDetailLabel.text = @"";
            UpdateDebugUI();
        });
    };
    
    gReader.errorCallback = ^(NSError *error) {
        VLog(@"Stream Error: %@", error.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gStatusLabel) gStatusLabel.text = @"● ERROR";
            if (gStatusLabel) gStatusLabel.textColor = [UIColor redColor];
            if (gErrorDetailLabel) gErrorDetailLabel.text = error.localizedDescription;
            UpdateDebugUI();
        });
    };
    
    [gReader startStreaming];
}
