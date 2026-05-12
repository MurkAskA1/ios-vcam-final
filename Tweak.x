// VirtualCamPro V217.0: The God Mode Hijacker (Mediaserverd Fix)
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

// --- Direct Preference Loading (Rootless Fix) ---
static void load_prefs() {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
    if (!dict) {
        // Try rootless path
        dict = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
    }
    
    if (dict) {
        enabled = [dict[@"enabled"] ?: @YES boolValue];
        NSString *url = dict[@"rtspURL"];
        if (url && url.length > 5) streamURL = url;
    }
}

// --- Utility: Image to PixelBuffer ---
static CVPixelBufferRef pixelBufferFromImage(UIImage *image) {
    if (!image) return NULL;
    CGImageRef cgImage = image.CGImage;
    CVPixelBufferRef pxbuffer = NULL;
    NSDictionary *options = @{(id)kCVPixelBufferCGImageCompatibilityKey: @YES, (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES};
    CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &pxbuffer);
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    CGContextRef context = CGBitmapContextCreate(pxdata, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), 8, CVPixelBufferGetBytesPerRow(pxbuffer), CGColorSpaceCreateDeviceRGB(), (CGBitmapInfo)kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)), cgImage);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    return pxbuffer;
}

// --- Global Stream Sync ---
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
                        globalLastPixelBuffer = pixelBufferFromImage(img);
                        if (old) CFRelease(old);
                    }
                }
            }
            [NSThread sleepForTimeInterval:0.04];
        }
        isRunning = NO;
    });
}

// --- THE BIG HOOK: AVCaptureSession everywhere ---

%hook AVCaptureSession
- (void)startRunning {
    %orig;
    if (enabled) {
        NSLog(@"[VirtualCamPro] Camera Session Started in App: %@", [NSBundle mainBundle].bundleIdentifier);
    }
}
%end

// --- Data Injection (Banks/Telegram/Safari) ---

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
    if (enabled && delegate && ![delegate isKindOfClass:[VCAPDelegateWrapper class]]) {
        VCAPDelegateWrapper *wrapper = [[VCAPDelegateWrapper alloc] init];
        wrapper.originalDelegate = delegate;
        %orig(wrapper, sampleBufferCallbackQueue);
    } else {
        %orig(delegate, sampleBufferCallbackQueue);
    }
}
%end

// --- Visual Preview Hijack ---

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *parent = nil;
        if ([self.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.delegate;
        else if ([self.superlayer.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.superlayer.delegate;

        if (parent) {
            UIImageView *vcamView = (UIImageView *)[parent viewWithTag:9944];
            if (!vcamView) {
                vcamView = [[UIImageView alloc] initWithFrame:parent.bounds];
                vcamView.backgroundColor = [UIColor blackColor];
                vcamView.contentMode = UIViewContentModeScaleAspectFill;
                vcamView.tag = 9944;
                vcamView.userInteractionEnabled = NO;
                [parent addSubview:vcamView];
                [parent bringSubviewToFront:vcamView];
                
                [NSTimer scheduledTimerWithTimeInterval:0.04 repeats:YES block:^(NSTimer *t) {
                    if (enabled && globalLastImage) vcamView.image = globalLastImage;
                }];
            }
            vcamView.frame = parent.bounds;
        }
    }
}
%end

// --- Photo Hijack ---

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

%ctor {
    load_prefs();
    if (enabled) {
        start_global_sync();
    }
    NSLog(@"[VirtualCamPro] V217.0 Stealth Loaded in %@", [NSBundle mainBundle].bundleIdentifier);
}