// Tweak.x - VirtualCamPro: Deep System Integration v3 (Final Fix)
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8887/live/stream";

static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;
static UIImageView *gPreviewView = nil;

// --- DEEP INTEGRATION: HOOKING DATA OUTPUT ---

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)callbackQueue {
    %orig;
}
%end

%hook NSObject
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    %orig;
}
%end

// --- VISUAL LAYER: PREVIEW HIJACK ---

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    
    self.opacity = 0.0; // Hide real camera
    
    UIView *container = (UIView *)self.delegate;
    if ([container isKindOfClass:[UIView class]]) {
        if (!gPreviewView) {
            gPreviewView = [[UIImageView alloc] initWithFrame:container.bounds];
            gPreviewView.contentMode = UIViewContentModeScaleAspectFill;
            gPreviewView.backgroundColor = [UIColor blackColor];
            [container insertSubview:gPreviewView atIndex:0];
        }
        gPreviewView.frame = container.bounds;
        if (gLastFrame) {
            gPreviewView.image = gLastFrame;
        }
    }
}
%end

// --- PHOTO HIJACK: THE FINAL RESULT ---

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id)delegate {
    %orig;
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && gLastFrame) {
        return UIImageJPEGRepresentation(gLastFrame, 0.95);
    }
    return %orig;
}
- (CGImageRef)CGImageRepresentation {
    if (enabled && gLastFrame) {
        return gLastFrame.CGImage;
    }
    return %orig;
}
%end

// --- INITIALIZATION ---

%ctor {
    // Universal support enabled for all camera-using processes
    gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
    gReader.frameCallback = ^(UIImage *f) {
        gLastFrame = f;
        if (gPreviewView) {
            dispatch_async(dispatch_get_main_queue(), ^{
                gPreviewView.image = f;
            });
        }
    };
    [gReader startStreaming];
}
