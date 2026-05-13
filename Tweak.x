// Tweak.x - VirtualCamPro V252.0: The Final Restoration
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

static CMSampleBufferRef CreateBufferFromImage(UIImage *img) {
    if (!img) return NULL;
    CGImageRef cg = img.CGImage;
    CVPixelBufferRef px = NULL;
    CVReturn s = CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(cg), CGImageGetHeight(cg), kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)@{ (id)kCVPixelBufferCGImageCompatibilityKey: @YES }, &px);
    if (s != kCVReturnSuccess) return NULL;

    CMVideoFormatDescriptionRef vdesc = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(nil, px, &vdesc);
    CMSampleTimingInfo t = { kCMTimeInvalid, kCMTimeZero, kCMTimeInvalid };
    CMSampleBufferRef sb = NULL;
    CMSampleBufferCreateForImageBuffer(nil, px, YES, nil, nil, vdesc, &t, &sb);
    
    CFRelease(px);
    if (vdesc) CFRelease(vdesc);
    return sb;
}

static void UpdateLabel(UIView *h, NSString *s, UIColor *c) {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.camera"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *l = (UILabel *)[h viewWithTag:7777];
        if (!l) {
            l = [[UILabel alloc] initWithFrame:CGRectMake(0, 80, h.bounds.size.width, 40)];
            l.tag = 7777;
            l.textAlignment = NSTextAlignmentCenter;
            l.font = [UIFont boldSystemFontOfSize:16];
            l.textColor = [UIColor whiteColor];
            l.numberOfLines = 0;
            [h addSubview:l];
        }
        l.text = s;
        l.backgroundColor = [c colorWithAlphaComponent:0.7];
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
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
            if (gReader.frameCount > 0) {
                UpdateLabel(p, [NSString stringWithFormat:@"V252.0 | LIVE | FPS: %lu", (unsigned long)gReader.frameCount], [UIColor greenColor]);
            } else {
                UpdateLabel(p, [NSString stringWithFormat:@"V252.0 | CONNECTING...\nURL: %@", streamURL], [UIColor orangeColor]);
            }
        }
    }
}
%end

%hook AVCaptureVideoDataOutput
- (void)captureOutput:(AVCaptureOutput *)o didOutputSampleBuffer:(CMSampleBufferRef)s fromConnection:(AVCaptureConnection *)c {
    if (enabled && gLastFrame) {
        CMSampleBufferRef f = CreateBufferFromImage(gLastFrame);
        if (f) {
            %orig(o, f, c);
            CFRelease(f);
            return;
        }
    }
    %orig(o, s, c);
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && gLastFrame) return UIImageJPEGRepresentation(gLastFrame, 0.9);
    return %orig;
}
%end

%ctor {
    NSString *b = [NSBundle mainBundle].bundleIdentifier;
    if ([b isEqualToString:@"com.apple.camera"] || [b isEqualToString:@"org.telegram.messenger"] || [b containsString:@"safari"] || [b containsString:@"chrome"]) {
        gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gReader.frameCallback = ^(UIImage *f) { gLastFrame = f; };
        [gReader startStreaming];
    }
}
