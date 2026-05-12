// VirtualCamPro V219.0: The Invisible Phantom (Maximum Stealth & Beauty)
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#import <ImageIO/ImageIO.h>

static BOOL enabled = YES;
static BOOL addNoise = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIImage *globalLastImage = nil;
static CVPixelBufferRef globalLastPixelBuffer = NULL;

// --- Stealth: Grain Noise to Mimic CMOS Sensor ---
static void apply_sensor_grain(CVPixelBufferRef buffer) {
    if (!addNoise) return;
    CVPixelBufferLockBaseAddress(buffer, 0);
    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress(buffer);
    size_t width = CVPixelBufferGetWidth(buffer);
    size_t height = CVPixelBufferGetHeight(buffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    
    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            size_t offset = y * bytesPerRow + x * 4;
            int grain = (arc4random_uniform(7)) - 3; // -3 to +3 subtle grain
            base[offset] = (unsigned char)MAX(0, MIN(255, base[offset] + grain));     // B
            base[offset+1] = (unsigned char)MAX(0, MIN(255, base[offset+1] + grain)); // G
            base[offset+2] = (unsigned char)MAX(0, MIN(255, base[offset+2] + grain)); // R
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
}

// --- Hardware & Identity Spoofing (Anti-KYC) ---

%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
- (BOOL)isVirtualDevice { return NO; }
- (NSArray<AVCaptureDeviceType> *)constituentDeviceTypes { return @[AVCaptureDeviceTypeBuiltInWideAngleCamera]; }
- (BOOL)isSuspended { return NO; }
%end

// --- Global Stream Sync (Optimized) ---

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
                        
                        CGImageRef cgImage = img.CGImage;
                        size_t w = CGImageGetWidth(cgImage);
                        size_t h = CGImageGetHeight(cgImage);
                        
                        CVPixelBufferRef pxbuffer = NULL;
                        NSDictionary *options = @{(id)kCVPixelBufferCGImageCompatibilityKey: @YES, (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES};
                        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &pxbuffer);
                        
                        CVPixelBufferLockBaseAddress(pxbuffer, 0);
                        void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
                        CGContextRef context = CGBitmapContextCreate(pxdata, w, h, 8, CVPixelBufferGetBytesPerRow(pxbuffer), CGColorSpaceCreateDeviceRGB(), (CGBitmapInfo)kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
                        CGContextDrawImage(context, CGRectMake(0, 0, w, h), cgImage);
                        CGContextRelease(context);
                        CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
                        
                        apply_sensor_grain(pxbuffer);
                        
                        CVPixelBufferRef old = globalLastPixelBuffer;
                        globalLastPixelBuffer = pxbuffer;
                        if (old) CFRelease(old);
                    }
                }
            }
            [NSThread sleepForTimeInterval:0.03]; // ~30 FPS for smoothness
        }
        isRunning = NO;
    });
}

// --- Data Injection Delegate (The "KYC Phantom") ---

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

// --- Visual Overlay (Perfect Scaling & No Flicker) ---

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *parent = nil;
        if ([self.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.delegate;
        else if ([self.superlayer.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.superlayer.delegate;

        if (parent) {
            UIImageView *vcamView = (UIImageView *)[parent viewWithTag:9966];
            if (!vcamView) {
                vcamView = [[UIImageView alloc] initWithFrame:parent.bounds];
                vcamView.backgroundColor = [UIColor blackColor];
                vcamView.contentMode = UIViewContentModeScaleAspectFill;
                vcamView.tag = 9966;
                vcamView.userInteractionEnabled = NO;
                [parent addSubview:vcamView];
                [parent bringSubviewToFront:vcamView];
                
                [NSTimer scheduledTimerWithTimeInterval:0.03 repeats:YES block:^(NSTimer *t) {
                    if (enabled && globalLastImage) vcamView.image = globalLastImage;
                }];
            }
            vcamView.frame = parent.bounds;
        }
    }
}
%end

// --- EXIF & Metadata Spoofing ---

%hook AVCapturePhoto
- (NSDictionary *)metadata {
    NSMutableDictionary *meta = [%orig mutableCopy];
    if (enabled) {
        // Mimic real iPhone 13 Pro Camera metadata
        NSMutableDictionary *exif = [meta[(id)kCGImagePropertyExifDictionary] mutableCopy];
        exif[(id)kCGImagePropertyExifLensModel] = @"iPhone 13 Pro back triple camera 5.7mm f/1.5";
        exif[(id)kCGImagePropertyExifFocalLength] = @5.7;
        exif[(id)kCGImagePropertyExifExposureTime] = @0.02;
        meta[(id)kCGImagePropertyExifDictionary] = exif;
        [meta removeObjectForKey:(id)kCGImagePropertyMakerAppleDictionary];
    }
    return meta;
}
- (NSData *)fileDataRepresentation {
    if (enabled && globalLastImage) return UIImageJPEGRepresentation(globalLastImage, 0.96);
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
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
    if (dict) {
        enabled = [dict[@"enabled"] ?: @YES boolValue];
        addNoise = [dict[@"addNoise"] ?: @YES boolValue];
        NSString *url = dict[@"rtspURL"];
        if (url && url.length > 5) streamURL = url;
    }

    if (enabled) start_global_sync();
    NSLog(@"[VirtualCamPro] Phantom Stealth Engine V219.0 Engaged");
}