// VirtualCamPro V233.0: The Pure Phantom Master (Black Screen & Safari Fix)
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static WKWebView *hiddenWebView = nil;
static UIImage *globalLastImage = nil;
static CVPixelBufferRef globalLastPixelBuffer = NULL;

// --- Direct Preference Loading ---
static void load_vcam_prefs() {
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
}

// --- Global Stream & Snapshot Engine ---
static void start_phantom_engine() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            WKWebViewConfiguration *config = [WKWebViewConfiguration new];
            config.allowsInlineMediaPlayback = YES;
            config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;

            hiddenWebView = [[WKWebView alloc] initWithFrame:CGRectMake(0,0,1280,720) configuration:config];
            hiddenWebView.backgroundColor = [UIColor blackColor];
            hiddenWebView.opaque = YES;
            
            NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]];
            [hiddenWebView loadRequest:req];

            [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
                if (enabled && hiddenWebView) {
                    [hiddenWebView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
                        if (img) {
                            globalLastImage = img;
                            
                            // Convert to PixelBuffer for deep injection
                            CGImageRef cgImage = img.CGImage;
                            CVPixelBufferRef pb = NULL;
                            NSDictionary *options = @{(id)kCVPixelBufferCGImageCompatibilityKey:@YES,(id)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES};
                            CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &pb);
                            
                            if (pb) {
                                CVPixelBufferLockBaseAddress(pb, 0);
                                CGContextRef ctx = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb), CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), 8, CVPixelBufferGetBytesPerRow(pb), CGColorSpaceCreateDeviceRGB(), (CGBitmapInfo)kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
                                CGContextDrawImage(ctx, CGRectMake(0, 0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)), cgImage);
                                CGContextRelease(ctx);
                                CVPixelBufferUnlockBaseAddress(pb, 0);
                                
                                CVPixelBufferRef old = globalLastPixelBuffer;
                                globalLastPixelBuffer = pb;
                                if (old) CFRelease(old);
                            }
                        }
                    }];
                }
            }];
        });
    });
}

// --- Data Output Hijack (WebRTC/Safari/Banks) ---
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

// --- Visual Preview Hijack ---
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *parent = nil;
        if ([self.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.delegate;
        else if ([self.superlayer.delegate isKindOfClass:[UIView class]]) parent = (UIView *)self.superlayer.delegate;

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
                
                [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t) {
                    if (enabled && globalLastImage) vcamView.image = globalLastImage;
                }];
            }
            vcamView.frame = parent.bounds;
        }
    }
}
%end

// --- Global ATS Fix ---
%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"NSAppTransportSecurity"]) {
        return @{ @"NSAllowsArbitraryLoads": @YES, @"NSAllowsArbitraryLoadsInWebContent": @YES, @"NSAllowsLocalNetworking": @YES };
    }
    return %orig;
}
%end

// --- Hardware Spoofing ---
%hook AVCaptureDevice
- (NSString *)uniqueID { return @"com.apple.avfoundation.avcapturedevice.built-in_video:back"; }
- (NSString *)localizedName { return @"Back Camera"; }
- (AVCaptureDeviceType)deviceType { return AVCaptureDeviceTypeBuiltInWideAngleCamera; }
- (BOOL)isVirtualDevice { return NO; }
%end

%ctor {
    load_vcam_prefs();
    if (enabled) {
        start_phantom_engine();
    }
    NSLog(@"[VirtualCamPro] Ghost Master V233.0 Ready");
}