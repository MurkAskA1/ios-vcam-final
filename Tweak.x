// VirtualCamPro V216.0: The Ultimate System Hijacker
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIImage *globalLastImage = nil;
static CVPixelBufferRef globalLastPixelBuffer = NULL;

// --- Core Hijack: Replacing Device Input ---

%hook AVCaptureSession
- (void)addInput:(AVCaptureInput *)input {
    if (enabled && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        if (deviceInput.device.position == AVCaptureDevicePositionBack || deviceInput.device.position == AVCaptureDevicePositionFront) {
            NSLog(@"[VirtualCamPro] Blocking real camera input for position: %ld", (long)deviceInput.device.position);
            // We don't return, we just let it add, but we will block the data downstream
        }
    }
    %orig(input);
}
%end

// --- Data Stream Hijack (The "Everywhere" Fix) ---

@interface VCAPDelegateWrapper : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id originalDelegate;
@end

@implementation VCAPDelegateWrapper
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && globalLastPixelBuffer) {
        CMSampleTimingInfo timingInfo;
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &timingInfo);
        CMVideoFormatDescriptionRef formatDesc = NULL;
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, globalLastPixelBuffer, &formatDesc);
        
        CMSampleBufferRef newBuffer = NULL;
        CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, globalLastPixelBuffer, formatDesc, &timingInfo, &newBuffer);
        
        if (newBuffer) {
            [self.originalDelegate captureOutput:output didOutputSampleBuffer:newBuffer fromConnection:connection];
            CFRelease(newBuffer);
            if (formatDesc) CFRelease(formatDesc);
            return;
        }
    }
    [self.originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
}
@end

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (enabled) {
        VCAPDelegateWrapper *wrapper = [[VCAPDelegateWrapper alloc] init];
        wrapper.originalDelegate = delegate;
        %orig(wrapper, sampleBufferCallbackQueue);
    } else {
        %orig(delegate, sampleBufferCallbackQueue);
    }
}
%end

// --- Visual Hijack (Preview Everywhere) ---

%hook AVCaptureVideoPreviewLayer
- (void)setSession:(AVCaptureSession *)session {
    %orig(session);
    if (enabled) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *parent = nil;
            if ([self.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.delegate;
            if (parent) {
                UIImageView *vcamView = (UIImageView *)[parent viewWithTag:9933];
                if (!vcamView) {
                    vcamView = [[UIImageView alloc] initWithFrame:parent.bounds];
                    vcamView.backgroundColor = [UIColor blackColor];
                    vcamView.contentMode = UIViewContentModeScaleAspectFill;
                    vcamView.tag = 9933;
                    vcamView.userInteractionEnabled = NO;
                    [parent addSubview:vcamView];
                    [parent bringSubviewToFront:vcamView];
                }
                
                [NSTimer scheduledTimerWithTimeInterval:0.04 repeats:YES block:^(NSTimer *t) {
                    if (enabled && globalLastImage) vcamView.image = globalLastImage;
                }];
            }
        });
    }
}
%end

// --- Photo & Gallery Hijack ---

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && globalLastImage) return UIImageJPEGRepresentation(globalLastImage, 0.9);
    return %orig;
}
%end

%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && globalLastImage) %orig(globalLastImage);
    else %orig;
}
%end

// --- Global Frame Sync ---

static void start_global_sync() {
    static BOOL isRunning = NO;
    if (isRunning) return;
    isRunning = YES;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        while (enabled) {
            @autoreleasepool {
                NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:streamURL]];
                if (data) {
                    UIImage *img = [UIImage imageWithData:data];
                    if (img) {
                        globalLastImage = img;
                        CVPixelBufferRef old = globalLastPixelBuffer;
                        
                        // Convert to PixelBuffer for injection
                        CGImageRef cgImage = img.CGImage;
                        CVPixelBufferRef pxbuffer = NULL;
                        NSDictionary *options = @{(id)kCVPixelBufferCGImageCompatibilityKey: @YES, (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES};
                        CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &pxbuffer);
                        CVPixelBufferLockBaseAddress(pxbuffer, 0);
                        void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
                        CGContextRef context = CGBitmapContextCreate(pxdata, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), 8, CVPixelBufferGetBytesPerRow(pxbuffer), CGColorSpaceCreateDeviceRGB(), (CGBitmapInfo)kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
                        CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)), cgImage);
                        CGContextRelease(context);
                        CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
                        
                        globalLastPixelBuffer = pxbuffer;
                        if (old) CFRelease(old);
                    }
                }
            }
            [NSThread sleepForTimeInterval:0.04];
        }
        isRunning = NO;
    });
}

%ctor {
    // Fix the suite name to match the preference bundle exactly
    NSUserDefaults *defs = [[NSUserDefaults alloc] initWithSuiteName:@"com.murkaska.virtualcampro"];
    enabled = [defs objectForKey:@"enabled"] ? [defs boolForKey:@"enabled"] : YES;
    NSString *str = [defs stringForKey:@"rtspURL"];
    if (str && str.length > 5) streamURL = str;

    if (enabled) {
        start_global_sync();
    }
    NSLog(@"[VirtualCamPro] Ultimate System Hijacker V216.0 Loaded");
}