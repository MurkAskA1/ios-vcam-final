// VCAM V79.0.6: HLS Native Support (Raw Text Fix)
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *rtspURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static BOOL addNoise = YES;
static CVPixelBufferRef vBuffer = NULL;
static AVPlayerItemVideoOutput *videoOutput = NULL;
static AVPlayer *player = NULL;

static NSString *getPrefsPath() {
    NSString *rootless = @"/var/jb/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist";
    NSString *rootful = @"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist";
    if ([[NSFileManager defaultManager] fileExistsAtPath:rootless]) return rootless;
    return rootful;
}

static void loadPrefs() {
    NSDictionary *prefs = [[NSDictionary alloc] initWithContentsOfFile:getPrefsPath()];
    if (prefs) {
        enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        rtspURL = prefs[@"rtspURL"] ?: @"http://192.168.1.44:8889/live/stream/index.m3u8";
        addNoise = prefs[@"addNoise"] ? [prefs[@"addNoise"] boolValue] : YES;
    }
}

static void applyStealthNoise(CVPixelBufferRef buffer) {
    if (!buffer) return;
    CVPixelBufferLockBaseAddress(buffer, 0);
    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress(buffer);
    int width = (int)CVPixelBufferGetWidth(buffer);
    int height = (int)CVPixelBufferGetHeight(buffer);
    int bytesPerRow = (int)CVPixelBufferGetBytesPerRow(buffer);
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            int offset = (y * bytesPerRow) + (x * 4);
            int noise = ((int)arc4random_uniform(5)) - 2;
            for (int i = 0; i < 3; i++) {
                int val = base[offset + i] + noise;
                base[offset + i] = (unsigned char)MAX(0, MIN(255, val));
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
}

static void startStreaming() {
    loadPrefs();
    if (!enabled) return;

    NSURL *url = [NSURL URLWithString:rtspURL];
    if (url == nil) return;

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    
    if ([item respondsToSelector:@selector(setConfiguresCustomAvoidanceOfLoadingDelays:)]) {
        [item setConfiguresCustomAvoidanceOfLoadingDelays:YES];
    }
    item.preferredForwardBufferDuration = 0.5;

    NSDictionary *pixBuffAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixBuffAttributes];
    [item addOutput:videoOutput];
    
    player = [AVPlayer playerWithPlayerItem:item];
    player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    if ([player respondsToSelector:@selector(setAutomaticallyWaitsToMinimizeStalling:)]) {
        [player setAutomaticallyWaitsToMinimizeStalling:NO];
    }
    [player play];
}

%hookf(CVImageBufferRef, CMSampleBufferGetImageBuffer, CMSampleBufferRef sbuf) {
    if (enabled) {
        if (!player || player.status == AVPlayerStatusFailed) {
            startStreaming();
        }

        if (player.status == AVPlayerStatusReadyToPlay) {
            CMTime itemTime = [videoOutput itemTimeForHostTime:CACurrentMediaTime()];
            if ([videoOutput hasNewPixelBufferForItemTime:itemTime]) {
                CVPixelBufferRef newBuffer = [videoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:NULL];
                if (newBuffer) {
                    if (vBuffer) CFRelease(vBuffer);
                    vBuffer = newBuffer;
                    if (addNoise) applyStealthNoise(vBuffer);
                }
            }
        }
    }
    return (vBuffer != NULL) ? vBuffer : %orig(sbuf);
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled && vBuffer) {
        self.contents = (__bridge id)vBuffer;
        self.contentsGravity = kCAGravityResizeAspectFill;
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && vBuffer) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:vBuffer];
        CIContext *context = [CIContext contextWithOptions:nil];
        CGImageRef cgImg = [context createCGImage:ci fromRect:ci.extent];
        UIImage *ui = [UIImage imageWithCGImage:cgImg];
        CGImageRelease(cgImg);
        return UIImageJPEGRepresentation(ui, 0.90);
    }
    return %orig;
}
%end

%ctor {
    loadPrefs();
}
