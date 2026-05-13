// VirtualCamPro V230.0: The Forensic Pro (Native MJPEG & Stealth)
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

// --- Native MJPEG Async Downloader (No WebView = No Question Mark) ---
static void start_native_stream() {
    static BOOL isRunning = NO;
    if (isRunning) return;
    isRunning = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        while (enabled) {
            @autoreleasepool {
                // Direct data fetch is more reliable than WebView for local MJPEG
                NSURL *url = [NSURL URLWithString:streamURL];
                NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:nil];
                
                if (data) {
                    UIImage *img = [UIImage imageWithData:data];
                    if (img) {
                        globalLastImage = img;
                        
                        // Prepare PixelBuffer for deep injection
                        CGImageRef cgImage = img.CGImage;
                        CVPixelBufferRef px = NULL;
                        NSDictionary *options = @{
                            (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
                            (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
                        };
                        CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &px);
                        
                        if (px) {
                            CVPixelBufferLockBaseAddress(px, 0);
                            CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(px), CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), 8, CVPixelBufferGetBytesPerRow(px), CGColorSpaceCreateDeviceRGB(), (CGBitmapInfo)kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
                            CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)), cgImage);
                            CGContextRelease(context);
                            CVPixelBufferUnlockBaseAddress(px, 0);
                            
                            CVPixelBufferRef old = globalLastPixelBuffer;
                            globalLastPixelBuffer = px;
                            if (old) CVPixelBufferRelease(old);
                        }
                    }
                }
            }
            [NSThread sleepForTimeInterval:0.04]; // ~25 FPS
        }
        isRunning = NO;
    });
}

// --- Global Hijack (AVFoundation Level) ---
%hook AVCaptureConnection
- (BOOL)isEnabled {
    if (enabled && [self.output isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")]) return NO;
    return %orig;
}
%end

// --- Visual Overlay (Everywhere Fix) ---
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *parent = nil;
        if ([self.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.delegate;
        else if ([self.superlayer.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.superlayer.delegate;

        if (parent) {
            UIImageView *vcam = (UIImageView *)[parent viewWithTag:9900];
            if (!vcam) {
                vcam = [[UIImageView alloc] initWithFrame:parent.bounds];
                vcam.backgroundColor = [UIColor blackColor];
                vcam.contentMode = UIViewContentModeScaleAspectFill;
                vcam.tag = 9900;
                vcam.userInteractionEnabled = NO;
                [parent addSubview:vcam];
                [parent bringSubviewToFront:vcam];
                
                [NSTimer scheduledTimerWithTimeInterval:0.04 repeats:YES block:^(NSTimer *t) {
                    if (enabled && globalLastImage) vcam.image = globalLastImage;
                }];
            }
            vcam.frame = parent.bounds;
        }
    }
}
%end

// --- Anti-KYC Identity Spoofing ---
%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
- (BOOL)isVirtualDevice { return NO; }
%end

// --- Metadata & Gallery Hijack ---
%hook AVCapturePhoto
- (NSDictionary *)metadata {
    NSMutableDictionary *m = [%orig mutableCopy];
    if (enabled) {
        NSMutableDictionary *exif = [m[(id)kCGImagePropertyExifDictionary] ?: @{} mutableCopy];
        exif[(id)kCGImagePropertyExifLensModel] = @"iPhone 13 Pro back camera";
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

%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && globalLastImage) %orig(globalLastImage);
    else %orig;
}
%end

%ctor {
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
    if (enabled) start_native_stream();
    NSLog(@"[VirtualCamPro] Forensic Pro V230.0 Active");
}