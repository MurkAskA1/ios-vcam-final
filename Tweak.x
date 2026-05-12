// VirtualCamPro V214.0: The System Phantom (Professional KYC Stealth)
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

// --- Utility: Convert UIImage to CVPixelBuffer ---
static CVPixelBufferRef pixelBufferFromImage(UIImage *image) {
    CGImageRef cgImage = image.CGImage;
    NSDictionary *options = @{(id)kCVPixelBufferCGImageCompatibilityKey: @YES, (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES};
    CVPixelBufferRef pxbuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &pxbuffer);
    if (status != kCVReturnSuccess) return NULL;

    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), 8, CVPixelBufferGetBytesPerRow(pxbuffer), rgbColorSpace, (CGBitmapInfo)kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)), cgImage);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    return pxbuffer;
}

// --- Global Stream Sync (Shared Memory) ---
static void update_global_frame() {
    static BOOL isUpdating = NO;
    if (isUpdating) return;
    isUpdating = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        while (enabled) {
            @autoreleasepool {
                NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:streamURL]];
                if (data) {
                    UIImage *img = [UIImage imageWithData:data];
                    if (img) {
                        globalLastImage = img;
                        CVPixelBufferRef old = globalLastPixelBuffer;
                        globalLastPixelBuffer = pixelBufferFromImage(img);
                        if (old) CVPixelBufferRelease(old);
                    }
                }
            }
            [NSThread sleepForTimeInterval:0.06]; // ~15 FPS to save battery and reduce lag
        }
        isUpdating = NO;
    });
}

// --- Hardware Spoofing (KYC Bypass) ---
%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
%end

// --- Data Output Hijack (Telegram/Banks/KYC) ---
@interface VCAPDelegateWrapper : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id originalDelegate;
@end

@implementation VCAPDelegateWrapper
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && globalLastPixelBuffer) {
        // Replace frame metadata/pixels with our virtual frame
        CMSampleTimingInfo timingInfo;
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &timingInfo);
        
        CMSampleBufferRef newBuffer = NULL;
        CMVideoFormatDescriptionRef formatDesc = NULL;
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, globalLastPixelBuffer, &formatDesc);
        
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
    VCAPDelegateWrapper *wrapper = [[VCAPDelegateWrapper alloc] init];
    wrapper.originalDelegate = delegate;
    %orig(wrapper, sampleBufferCallbackQueue);
}
%end

// --- Preview Hijack (System UI) ---
%hook AVCaptureVideoPreviewLayer
- (void)setSession:(AVCaptureSession *)session {
    %orig(session);
    if (enabled) {
        UIImageView *overlay = [[UIImageView alloc] initWithFrame:((CALayer *)self).bounds];
        overlay.backgroundColor = [UIColor blackColor];
        overlay.contentMode = UIViewContentModeScaleAspectFill;
        overlay.tag = 9911;
        
        // In a tweak, we can't easily add subviews to a CALayer in some contexts,
        // but we can find the parent view if it exists.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *parent = nil;
            if ([self.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.delegate;
            if (parent) {
                if (![parent viewWithTag:9911]) {
                    [parent addSubview:overlay];
                    [parent bringSubviewToFront:overlay];
                    
                    [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t) {
                        if (globalLastImage) overlay.image = globalLastImage;
                    }];
                }
            }
        });
    }
}
%end

// --- Photo Hijack ---
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && globalLastImage) return UIImageJPEGRepresentation(globalLastImage, 0.9);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation {
    if (enabled && globalLastImage) return globalLastImage.CGImage;
    return %orig;
}
%end

// --- Gallery & UI Hijack ---
%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && globalLastImage) %orig(globalLastImage);
    else %orig;
}
%end

%hook PHImageManager
- (PHImageRequestID)requestImageForAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(PHImageContentMode)contentMode options:(PHImageRequestOptions *)options resultHandler:(void (^)(UIImage *result, NSDictionary *info))resultHandler {
    if (enabled && globalLastImage && [[NSDate date] timeIntervalSinceDate:asset.creationDate] < 45) {
        if (resultHandler) {
            resultHandler(globalLastImage, nil);
            return (PHImageRequestID)1;
        }
    }
    return %orig;
}
%end

%ctor {
    NSUserDefaults *defs = [[NSUserDefaults alloc] initWithSuiteName:@"com.murkaska.virtualcampro"];
    enabled = [defs objectForKey:@"enabled"] ? [defs boolForKey:@"enabled"] : YES;
    NSString *str = [defs stringForKey:@"rtspURL"];
    if (str && str.length > 5) streamURL = str;

    if (enabled) {
        update_global_frame();
    }
    NSLog(@"[VirtualCamPro] Phantom Stealth Engine V214.0 Loaded");
}