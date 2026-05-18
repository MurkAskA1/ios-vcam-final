#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static UILabel *gStatusLabel = nil;

// Лог файл для Filza
#define DEBUG_LOG @"/var/mobile/vcam.log"

void WriteLog(NSString *msg) {
    NSLog(@"[VCam] %@", msg);
    NSString *content = [NSString stringWithFormat:@"%@: %@\n", [NSDate date], msg];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:DEBUG_LOG];
    if (!handle) {
        [content writeToFile:DEBUG_LOG atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [handle seekToEndOfFile];
        [handle writeData:[content dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

static CMSampleBufferRef CreateSampleBufferFromPixelBuffer(CVPixelBufferRef pixelBuffer, CMTime timestamp) {
    if (!pixelBuffer) return NULL;
    CMVideoFormatDescriptionRef formatDescription;
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &formatDescription);
    CMSampleTimingInfo timingInfo = { kCMTimeInvalid, timestamp, kCMTimeInvalid };
    CMSampleBufferRef sampleBuffer = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, YES, NULL, NULL, formatDescription, &timingInfo, &sampleBuffer);
    CFRelease(formatDescription);
    return sampleBuffer;
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.opacity = 0.0;

    if (!gPlayer) {
        WriteLog(@"Initializing Player...");
        
        UIWindow *win = [UIApplication sharedApplication].keyWindow;
        if (!win) win = [[UIApplication sharedApplication].windows firstObject];

        if (win) {
            gStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, win.bounds.size.width - 40, 100)];
            gStatusLabel.textColor = [UIColor yellowColor];
            gStatusLabel.numberOfLines = 0;
            gStatusLabel.textAlignment = NSTextAlignmentCenter;
            gStatusLabel.text = @"VCam: Loading Stream...";
            [win addSubview:gStatusLabel];
            
            NSURL *url = [NSURL URLWithString:streamURL];
            gPlayer = [AVPlayer playerWithURL:url];
            
            NSDictionary *pixBuffAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
            gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixBuffAttributes];
            [gPlayer.currentItem addOutput:gVideoOutput];
            
            AVPlayerLayer *pl = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
            pl.frame = win.bounds;
            pl.videoGravity = AVLayerVideoGravityResizeAspectFill;
            [win.layer insertSublayer:pl below:gStatusLabel.layer];
            
            [gPlayer play];
            WriteLog(@"Player started playing");
        }
    }
}
%end

%hook NSObject
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled && gVideoOutput) {
        CMTime vTime = [gPlayer.currentItem currentTime];
        if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
            CVPixelBufferRef pixelBuffer = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
            if (pixelBuffer) {
                CMSampleBufferRef fakeBuffer = CreateSampleBufferFromPixelBuffer(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
                if (fakeBuffer) {
                    %orig(output, fakeBuffer, connection);
                    CFRelease(fakeBuffer);
                    CVPixelBufferRelease(pixelBuffer);
                    return;
                }
                CVPixelBufferRelease(pixelBuffer);
            }
        }
    }
    %orig;
}
%end
