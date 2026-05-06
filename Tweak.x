// VCAM V75.0: Enhanced Connection Watcher
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
static NSString *rtspURL = @"rtsp://192.168.1.44:554/live";
static BOOL addNoise = YES;
static CVPixelBufferRef vBuffer = NULL;
static AVPlayerItemVideoOutput *videoOutput = NULL;
static AVPlayer *player = NULL;
static UILabel *debugLabel = NULL;

static NSString *getPrefsPath() {
    NSString *rootless = @"/var/jb/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist";
    NSString *rootful = @"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist";
    if ([[NSFileManager defaultManager] fileExistsAtPath:rootless]) return rootless;
    return rootful;
}

static void writeLog(NSString *msg) {
    NSString *path = @"/var/mobile/Documents/vcam_ERROR.txt";
    NSString *content = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[content dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } else {
        [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
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

static void loadPrefs() {
    NSDictionary *prefs = [[NSDictionary alloc] initWithContentsOfFile:getPrefsPath()];
    if (prefs) {
        enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        rtspURL = prefs[@"rtspURL"] ?: @"rtsp://192.168.1.44:554/live";
        addNoise = prefs[@"addNoise"] ? [prefs[@"addNoise"] boolValue] : YES;
    }
}

static void startStreaming() {
    loadPrefs();
    if (!enabled) return;

    NSURL *url = [NSURL URLWithString:rtspURL];
    if (!url) {
        writeLog([NSString stringWithFormat:@"ERR: Invalid URL: %@", rtspURL]);
        return;
    }

    writeLog([NSString stringWithFormat:@"START: Connecting to %@", rtspURL]);

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    
    NSDictionary *pixBuffAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixBuffAttributes];
    [item addOutput:videoOutput];
    
    player = [AVPlayer playerWithPlayerItem:item];
    player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    
    [player addObserver:[[NSObject alloc] init] forKeyPath:@"status" options:0 context:NULL];
    
    writeLog(@"INFO: Player initialized and play() called");
    [player play];
}

%hookf(CVImageBufferRef, CMSampleBufferGetImageBuffer, CMSampleBufferRef sbuf) {
    if (enabled) {
        if (!player) startStreaming();
        
        if (player.status == AVPlayerStatusFailed) {
            if (debugLabel) [debugLabel setText:@"VCAM: PLAYER ERROR"];
            static BOOL logged = NO;
            if (!logged) {
                writeLog([NSString stringWithFormat:@"ERR: Player failed: %@", player.error.localizedDescription]);
                logged = YES;
            }
            player = nil;
            return %orig(sbuf);
        }

        if (player.status == AVPlayerStatusReadyToPlay) {
            CMTime itemTime = [videoOutput itemTimeForHostTime:CACurrentMediaTime()];
            if ([videoOutput hasNewPixelBufferForItemTime:itemTime]) {
                CVPixelBufferRef newBuffer = [videoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:NULL];
                if (newBuffer) {
                    if (vBuffer) CFRelease(vBuffer);
                    vBuffer = newBuffer;
                    if (addNoise) applyStealthNoise(vBuffer);
                    if (debugLabel) [debugLabel setText:@"VCAM: STREAMING"];
                }
            }
        }
        
        if (vBuffer) return vBuffer;
    }
    return %orig(sbuf);
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        if (vBuffer) {
            self.contents = (__bridge id)vBuffer;
            self.contentsGravity = kCAGravityResizeAspectFill;
        }
        
        if (!debugLabel) {
            debugLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, 240, 30)];
            debugLabel.textColor = [UIColor greenColor];
            debugLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
            debugLabel.font = [UIFont boldSystemFontOfSize:13];
            debugLabel.text = @"VCAM: CONNECTING...";
            [self addSublayer:debugLabel.layer];
        }

        for (CALayer *sub in self.sublayers) {
            if (sub != debugLabel.layer) sub.hidden = (vBuffer != NULL);
        }
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
        float quality = 0.85 + ((arc4random_uniform(10)) / 100.0);
        return UIImageJPEGRepresentation(ui, quality);
    }
    return %orig;
}
%end

%ctor {
    loadPrefs();
}