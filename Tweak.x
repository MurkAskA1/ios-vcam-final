#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static CVPixelBufferRef gGlobalBuffer = NULL;

#define LOG_PATH @"/var/mobile/Documents/vcam_debug.log"

void VLog(NSString *msg) {
    @try {
        NSString *line = [NSString stringWithFormat:@"%@: [VCam] %@\n", [NSDate date], msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:LOG_PATH];
        if (!fh) {
            [line writeToFile:LOG_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    } @catch (NSException *e) {}
}

static void SyncFrame() {
    if (!gVideoOutput) return;
    CMTime vTime = [gPlayer.currentItem currentTime];
    CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
    if (pb) {
        if (gGlobalBuffer) CVPixelBufferRelease(gGlobalBuffer);
        gGlobalBuffer = pb;
    }
}

%hook AVCapturePhoto
- (CVPixelBufferRef)pixelBuffer {
    SyncFrame();
    if (enabled && gGlobalBuffer) {
        VLog(@"HOOK: Providing fake pixelBuffer to App");
        return CVPixelBufferRetain(gGlobalBuffer);
    }
    return %orig;
}
- (NSData *)fileDataRepresentation {
    SyncFrame();
    if (enabled && gGlobalBuffer) {
        VLog(@"HOOK: Providing fake JPEG data");
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        CIContext *ctx = [CIContext contextWithOptions:nil];
        CGImageRef cg = [ctx createCGImage:ci fromRect:ci.extent];
        NSData *data = UIImageJPEGRepresentation([UIImage imageWithCGImage:cg], 0.9);
        if (cg) CGImageRelease(cg);
        return data;
    }
    return %orig;
}
%end

%hook NSObject
- (void)captureOutput:(id)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(id)connection {
    if (enabled) {
        SyncFrame();
        if (gGlobalBuffer) {
            CMSampleBufferRef fake = NULL;
            CMVideoFormatDescriptionRef fd;
            CMVideoFormatDescriptionCreateForImageBuffer(NULL, gGlobalBuffer, &fd);
            CMSampleTimingInfo ti = { kCMTimeInvalid, CMSampleBufferGetPresentationTimeStamp(sampleBuffer), kCMTimeInvalid };
            CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, gGlobalBuffer, YES, NULL, NULL, fd, &ti, &fake);
            %orig(output, fake, connection);
            if (fake) CFRelease(fake);
            if (fd) CFRelease(fd);
            return;
        }
    }
    %orig;
}
%end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.hidden = YES;

    if (!gPlayer) {
        VLog(@"GodMode Player Init");
        gPlayer = [[AVPlayer alloc] initWithURL:[NSURL URLWithString:streamURL]];
        NSDictionary *attrs = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
        gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attrs];
        [gPlayer.currentItem addOutput:gVideoOutput];
        [gPlayer play];

        AVPlayerLayer *pl = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
        pl.frame = self.bounds;
        pl.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.superlayer insertSublayer:pl above:self];
    }
}
%end

%ctor {
    VLog([NSString stringWithFormat:@"Loaded in %@", [[NSProcessInfo processInfo] processName]]);
}
