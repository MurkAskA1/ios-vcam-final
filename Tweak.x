// Tweak.x - VirtualCamPro V269.0: System Sovereign
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;
static UILabel *gDiagnosticsHUD = nil;

// Pro-level Helper: Convert UIImage to CMSampleBuffer for direct system injection
static CMSampleBufferRef CreateInjectedBuffer(UIImage *img) {
    if (!img) return NULL;
    CGImageRef cg = img.CGImage;
    CVPixelBufferRef px = NULL;
    CVReturn s = CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(cg), CGImageGetHeight(cg), kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)@{ (id)kCVPixelBufferCGImageCompatibilityKey: @YES }, &px);
    if (s != kCVReturnSuccess) return NULL;

    CMVideoFormatDescriptionRef vdesc = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, px, &vdesc);
    CMSampleTimingInfo t = { kCMTimeInvalid, kCMTimeZero, kCMTimeInvalid };
    CMSampleBufferRef sb = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, px, YES, nil, nil, vdesc, &t, &sb);
    
    CFRelease(px);
    if (vdesc) CFRelease(vdesc);
    return sb;
}

// 1. Core Data Injection: Forcing apps to take our frames instead of real ones
%hook AVCaptureVideoDataOutput
- (void)captureOutput:(AVCaptureOutput *)o didOutputSampleBuffer:(CMSampleBufferRef)s fromConnection:(AVCaptureConnection *)c {
    if (enabled && gLastFrame) {
        CMSampleBufferRef fake = CreateInjectedBuffer(gLastFrame);
        if (fake) {
            %orig(o, fake, c);
            CFRelease(fake);
            return;
        }
    }
    %orig;
}
%end

// 2. Visual Hijack (Preview for user)
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.opacity = 0.0;
    UIView *p = (UIView *)self.delegate;
    if ([p isKindOfClass:[UIView class]]) {
        UIImageView *v = [p viewWithTag:9999];
        if (!v) {
            v = [[UIImageView alloc] initWithFrame:p.bounds];
            v.tag = 9999;
            v.contentMode = UIViewContentModeScaleAspectFill;
            [p insertSubview:v atIndex:0];
        }
        if (gLastFrame) v.image = gLastFrame;
    }
}
%end

// 3. Global Capture Hijack (Photo/Video Files)
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && gLastFrame) return UIImageJPEGRepresentation(gLastFrame, 0.95);
    return %orig;
}
%end

// 4. Legacy Hijack (For older apps/banks)
%hook AVCaptureStillImageOutput
- (void)captureStillImageAsynchronouslyFromConnection:(AVCaptureConnection *)connection completionHandler:(void (^)(CMSampleBufferRef, NSError *))handler {
    if (enabled && gLastFrame) {
        CMSampleBufferRef fake = CreateInjectedBuffer(gLastFrame);
        handler(fake, nil);
        if (fake) CFRelease(fake);
        return;
    }
    %orig;
}
%end

%ctor {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    if ([bid containsString:@"camera"] || [bid containsString:@"telegra"] || [bid containsString:@"safari"] || [bid containsString:@"bank"]) {
        gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gReader.frameCallback = ^(UIImage *f) { gLastFrame = f; };
        [gReader startStreaming];
    }
}
