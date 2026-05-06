// VCAM V78.0: Ultimate KYC Stealth & USB-Ready Engine
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <ifaddrs.h>
#include <arpa/inet.h>

static BOOL enabled = YES;
static NSString *rtspURL = @"http://192.168.1.44:8888/live";
static BOOL addNoise = YES;
static CVPixelBufferRef vBuffer = NULL;
static AVPlayerItemVideoOutput *videoOutput = NULL;
static AVPlayer *player = NULL;
static UILabel *debugLabel = NULL;
static dispatch_queue_t streamerQueue = NULL;

static NSString *getIPAddress() {
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

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
        rtspURL = prefs[@"rtspURL"] ?: @"http://192.168.1.44:8888/live";
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
            int noise = ((int)arc4random_uniform(7)) - 3;
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
    
    if (player) {
        if (player.status == AVPlayerStatusFailed || player.status == AVPlayerStatusUnknown) {
            [player pause];
            player = nil;
            videoOutput = nil;
        } else {
            return;
        }
    }

    NSURL *url = [NSURL URLWithString:rtspURL];
    if (!url) {
        if (debugLabel) [debugLabel setText:[NSString stringWithFormat:@"VCAM ERROR: Invalid URL\nIP: %@", getIPAddress()]];
        return;
    }

    dispatch_async(streamerQueue, ^{
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{
            AVURLAssetPreferPreciseDurationAndTimingKey: @YES,
            @"AVURLAssetHTTPHeaderFieldsKey": @{},
            @"AVURLAssetHTTPTimeoutIntervalKey": @5.0
        }];
        
        AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
        
        NSDictionary *pixBuffAttributes = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey: @1280,
            (id)kCVPixelBufferHeightKey: @720
        };
        
        videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixBuffAttributes];
        [item addOutput:videoOutput];
        
        player = [AVPlayer playerWithPlayerItem:item];
        player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        
        if ([player respondsToSelector:@selector(setAutomaticallyWaitsToMinimizeStalling:)]) {
            [player setAutomaticallyWaitsToMinimizeStalling:NO];
        }
        
        [player play];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (debugLabel) [debugLabel setText:[NSString stringWithFormat:@"VCAM: CONNECTING...\nURL: %@", rtspURL]];
        });
    });
}

%hookf(CVImageBufferRef, CMSampleBufferGetImageBuffer, CMSampleBufferRef sbuf) {
    if (enabled) {
        if (!player) startStreaming();
        
        if (player) {
            if (player.status == AVPlayerStatusFailed) {
                if (debugLabel) [debugLabel setText:[NSString stringWithFormat:@"VCAM ERROR: Connection Failed\nIP: %@", getIPAddress()]];
                [player pause];
                player = nil;
                videoOutput = nil;
            }

            if (player.status == AVPlayerStatusReadyToPlay && videoOutput) {
                CMTime itemTime = [videoOutput itemTimeForHostTime:CACurrentMediaTime()];
                if ([videoOutput hasNewPixelBufferForItemTime:itemTime]) {
                    CVPixelBufferRef newBuffer = [videoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:NULL];
                    if (newBuffer) {
                        if (vBuffer) CFRelease(vBuffer);
                        vBuffer = newBuffer;
                        if (addNoise) applyStealthNoise(vBuffer);
                        if (debugLabel) [debugLabel setText:@"VCAM: STREAMING ACTIVE ✓"];
                        return vBuffer;
                    }
                } else {
                    if (debugLabel) [debugLabel setText:@"VCAM: BUFFERING..."];
                }
            } else if (player.status == AVPlayerStatusUnknown) {
                if (debugLabel) [debugLabel setText:@"VCAM: LOADING..."];
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
            debugLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, 300, 60)];
            debugLabel.textColor = [UIColor greenColor];
            debugLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
            debugLabel.font = [UIFont boldSystemFontOfSize:10];
            debugLabel.numberOfLines = 3;
            debugLabel.text = [NSString stringWithFormat:@"VCAM: INITIALIZING...\nIP: %@\nURL: %@", getIPAddress(), rtspURL];
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
    streamerQueue = dispatch_queue_create("com.murkaska.vcam.streamer", DISPATCH_QUEUE_SERIAL);
    loadPrefs();
}
