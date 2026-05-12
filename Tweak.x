// VirtualCamPro V221.0: The Stealth King (Final Build Fix)
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#import <ImageIO/ImageIO.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIImage *globalLastImage = nil;
static CVPixelBufferRef globalLastPixelBuffer = NULL;

// --- Stealth: Dynamic Grain to Mimic Real Sensor ---
static void apply_stealth_filters(CVPixelBufferRef buffer) {
    CVPixelBufferLockBaseAddress(buffer, 0);
    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress(buffer);
    size_t width = CVPixelBufferGetWidth(buffer);
    size_t height = CVPixelBufferGetHeight(buffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    
    static uint32_t seed = 0;
    seed++;
    
    for (size_t y = 0; y < height; y += 2) {
        for (size_t x = 0; x < width; x += 2) {
            size_t offset = y * bytesPerRow + x * 4;
            int grain = (int)((arc4random() % 5) - 2);
            base[offset] = (unsigned char)MAX(0, MIN(255, base[offset] + grain));
            base[offset+1] = (unsigned char)MAX(0, MIN(255, base[offset+1] + grain));
            base[offset+2] = (unsigned char)MAX(0, MIN(255, base[offset+2] + grain));
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
}

// --- Anti-KYC Identity Spoofing ---
%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
- (BOOL)isVirtualDevice { return NO; }
- (NSInteger)position { return AVCaptureDevicePositionBack; }
%end

// --- Global Stream Logic ---
static void start_stealth_sync() {
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
                        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)@{(id)kCVPixelBufferCGImageCompatibilityKey:@YES,(id)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES}, &pxbuffer);
                        
                        CVPixelBufferLockBaseAddress(pxbuffer, 0);
                        CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pxbuffer), w, h, 8, CVPixelBufferGetBytesPerRow(pxbuffer), CGColorSpaceCreateDeviceRGB(), (CGBitmapInfo)kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
                        CGContextDrawImage(context, CGRectMake(0, 0, w, h), cgImage);
                        CGContextRelease(context);
                        CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
                        
                        apply_stealth_filters(pxbuffer);
                        
                        CVPixelBufferRef old = globalLastPixelBuffer;
                        globalLastPixelBuffer = pxbuffer;
                        if (old) CVPixelBufferRelease(old);
                    }
                }
            }
            [NSThread sleepForTimeInterval:0.033];
        }
        isRunning = NO;
    });
}

// --- Direct Buffer Injection (Everywhere) ---
@interface VCAPDelegateWrapper : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id originalDelegate;
@end

@implementation VCAPDelegateWrapper
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && globalLastPixelBuffer) {
        CMSampleTimingInfo timing;
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &timing);
        CMVideoFormatDescriptionRef formatDesc = NULL;
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, globalLastPixelBuffer, &formatDesc);
        CMSampleBufferRef newBuffer = NULL;
        CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, globalLastPixelBuffer, formatDesc, &timing, &newBuffer);
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
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate queue:(dispatch_queue_t)queue {
    if (enabled && delegate && ![delegate isKindOfClass:[VCAPDelegateWrapper class]]) {
        VCAPDelegateWrapper *wrapper = [[VCAPDelegateWrapper alloc] init];
        wrapper.originalDelegate = delegate;
        %orig(wrapper, queue);
    } else {
        %orig(delegate, queue);
    }
}
%end

// --- Visual Overlay Fix ---
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *parent = nil;
        if ([self.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.delegate;
        else if ([self.superlayer.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.superlayer.delegate;

        if (parent) {
            UIImageView *vcam = (UIImageView *)[parent viewWithTag:9988];
            if (!vcam) {
                vcam = [[UIImageView alloc] initWithFrame:parent.bounds];
                vcam.backgroundColor = [UIColor blackColor];
                vcam.contentMode = UIViewContentModeScaleAspectFill;
                vcam.tag = 9988;
                vcam.userInteractionEnabled = NO;
                [parent addSubview:vcam];
                [parent bringSubviewToFront:vcam];

                [NSTimer scheduledTimerWithTimeInterval:0.033 repeats:YES block:^(NSTimer *t) {
                    if (globalLastImage) vcam.image = globalLastImage;
                }];
            }
            vcam.frame = parent.bounds;
        }
    }
}
%end

// --- Metadata Engineering ---
%hook AVCapturePhoto
- (NSDictionary *)metadata {
    NSMutableDictionary *m = [%orig mutableCopy];
    if (enabled) {
        NSMutableDictionary *exif = [m[(id)kCGImagePropertyExifDictionary] ?: @{} mutableCopy];
        exif[(id)kCGImagePropertyExifLensModel] = @"iPhone 13 Pro triple camera";
        m[(id)kCGImagePropertyExifDictionary] = exif;
        [m removeObjectForKey:(id)kCGImagePropertyMakerAppleDictionary];
    }
    return m;
}
- (NSData *)fileDataRepresentation {
    if (enabled && globalLastImage) return UIImageJPEGRepresentation(globalLastImage, 0.95);
    return %orig;
}
%end

%ctor {
    // Force search in both standard and rootless paths for maximum compatibility
    NSArray *paths = @[@"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist", 
                       @"/var/jb/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d) {
            enabled = [d[@"enabled"] ?: @YES boolValue];
            NSString *u = d[@"rtspURL"];
            if (u && u.length > 5) streamURL = u;
            break;
        }
    }
    if (enabled) start_stealth_sync();
    NSLog(@"[VirtualCamPro] V221.0 Final Stealth Active");
}