// VirtualCamPro V220.0: The System Sovereign (The Ultimate KYC Solution)
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
static NSTimeInterval lastFrameTime = 0;

// --- Advanced Stealth: Adaptive Sensor Simulation ---
static void apply_pro_stealth_filters(CVPixelBufferRef buffer) {
    CVPixelBufferLockBaseAddress(buffer, 0);
    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress(buffer);
    size_t width = CVPixelBufferGetWidth(buffer);
    size_t height = CVPixelBufferGetHeight(buffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    
    uint32_t random_seed = (uint32_t)([[NSDate date] timeIntervalSince1970] * 1000);
    
    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            size_t offset = y * bytesPerRow + x * 4;
            
            // 1. Subtle Temporal Grain (Mimics ISO noise)
            int grain = (int)(rand_r(&random_seed) % 5) - 2;
            
            // 2. Micro-Flicker (Mimics 50/60Hz lighting - very important for Liveness checks)
            int flicker = (int)(sin([[NSDate date] timeIntervalSince1970] * 60.0) * 1.5);
            
            int mod = grain + flicker;
            base[offset] = (unsigned char)MAX(0, MIN(255, base[offset] + mod));     // B
            base[offset+1] = (unsigned char)MAX(0, MIN(255, base[offset+1] + mod)); // G
            base[offset+2] = (unsigned char)MAX(0, MIN(255, base[offset+2] + mod)); // R
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
}

// --- Hardware Cloaking: Absolute Identity Spoofing ---
%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
- (BOOL)isVirtualDevice { return NO; }
- (BOOL)isSuspended { return NO; }
- (NSArray *)constituentDeviceTypes { return @[AVCaptureDeviceTypeBuiltInWideAngleCamera]; }
- (NSInteger)position { return AVCaptureDevicePositionBack; }
%end

// --- Direct Injector (The "Heart" of the Bypass) ---
@interface VCAPDelegateWrapper : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id originalDelegate;
@end

@implementation VCAPDelegateWrapper
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && globalLastPixelBuffer) {
        CMSampleTimingInfo timing;
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &timing);
        
        CMVideoFormatDescriptionRef desc = NULL;
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, globalLastPixelBuffer, &desc);
        
        CMSampleBufferRef newBuf = NULL;
        CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, globalLastPixelBuffer, desc, &timing, &newBuf);
        
        if (newBuf) {
            [self.originalDelegate captureOutput:output didOutputSampleBuffer:newBuf fromConnection:connection];
            CFRelease(newBuf);
            if (desc) CFRelease(desc);
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

// --- Global UI Hijack: Perfect Scaling & Depth ---
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *parent = nil;
        if ([self.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.delegate;
        else if ([self.superlayer.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.superlayer.delegate;

        if (parent) {
            UIImageView *vcam = (UIImageView *)[parent viewWithTag:9977];
            if (!vcam) {
                vcam = [[UIImageView alloc] initWithFrame:parent.bounds];
                vcam.backgroundColor = [UIColor blackColor];
                vcam.contentMode = UIViewContentModeScaleAspectFill;
                vcam.tag = 9977;
                vcam.userInteractionEnabled = NO;
                vcam.alpha = 0.0; // Start invisible for smooth fade-in
                [parent addSubview:vcam];
                [parent bringSubviewToFront:vcam];
                
                [UIView animateWithDuration:0.5 animations:^{ vcam.alpha = 1.0; }];

                [NSTimer scheduledTimerWithTimeInterval:0.033 repeats:YES block:^(NSTimer *t) {
                    if (enabled && globalLastImage) vcam.image = globalLastImage;
                }];
            }
            vcam.frame = parent.bounds;
        }
    }
}
%end

// --- Metadata Engineering: Forensic Quality ---
%hook AVCapturePhoto
- (NSDictionary *)metadata {
    NSMutableDictionary *m = [%orig mutableCopy];
    if (enabled) {
        NSMutableDictionary *exif = [m[(id)kCGImagePropertyExifDictionary] ?: @{} mutableCopy];
        exif[(id)kCGImagePropertyExifLensModel] = @"iPhone 13 Pro back triple camera 5.7mm f/1.5";
        exif[(id)kCGImagePropertyExifFocalLength] = @5.7;
        exif[(id)kCGImagePropertyExifISOSpeedRatings] = @[@100];
        m[(id)kCGImagePropertyExifDictionary] = exif;
        [m removeObjectForKey:(id)kCGImagePropertyMakerAppleDictionary];
    }
    return m;
}
- (NSData *)fileDataRepresentation {
    if (enabled && globalLastImage) return UIImageJPEGRepresentation(globalLastImage, 0.98);
    return %orig;
}
%end

// --- Global Sync Engine ---
static void start_sovereign_sync() {
    static BOOL running = NO;
    if (running) return;
    running = YES;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        while (enabled) {
            @autoreleasepool {
                NSData *d = [NSData dataWithContentsOfURL:[NSURL URLWithString:streamURL]];
                if (d) {
                    UIImage *i = [UIImage imageWithData:d];
                    if (i) {
                        globalLastImage = i;
                        
                        CGImageRef cg = i.CGImage;
                        CVPixelBufferRef pb = NULL;
                        CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(cg), CGImageGetHeight(cg), kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)@{(id)kCVPixelBufferCGImageCompatibilityKey:@YES,(id)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES}, &pb);
                        
                        CVPixelBufferLockBaseAddress(pb, 0);
                        CGContextRef ctx = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb), CGImageGetWidth(cg), CGImageGetHeight(cg), 8, CVPixelBufferGetBytesPerRow(pb), CGColorSpaceCreateDeviceRGB(), (CGBitmapInfo)kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
                        CGContextDrawImage(ctx, CGRectMake(0,0,CGImageGetWidth(cg),CGImageGetHeight(cg)), cg);
                        CGContextRelease(ctx);
                        CVPixelBufferUnlockBaseAddress(pb, 0);
                        
                        apply_pro_stealth_filters(pb);
                        
                        CVPixelBufferRef old = globalLastPixelBuffer;
                        globalLastPixelBuffer = pb;
                        if (old) CFRelease(old);
                    }
                }
            }
            [NSThread sleepForTimeInterval:0.033]; // Rock stable 30 FPS
        }
        running = NO;
    });
}

%ctor {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
    if (d) {
        enabled = [d[@"enabled"] ?: @YES boolValue];
        NSString *u = d[@"rtspURL"];
        if (u && u.length > 5) streamURL = u;
    }
    if (enabled) start_sovereign_sync();
    NSLog(@"[VirtualCamPro] Sovereign Stealth Engine Engaged");
}