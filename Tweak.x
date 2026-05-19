#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerItemVideoOutput *gVideoOutput = nil;
static CVPixelBufferRef gGlobalBuffer = NULL;
static CIContext *gCIContext = nil;

static void loadPrefs() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
    if (prefs) {
        enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        NSString *url = prefs[@"rtspURL"];
        if (url && url.length > 0) streamURL = url;
    }
    if (!gCIContext) gCIContext = [CIContext contextWithOptions:nil];
}

static void RefreshBuffer() {
    if (!gVideoOutput || !enabled) return;
    CMTime vTime = [gPlayer.currentItem currentTime];
    if ([gVideoOutput hasNewPixelBufferForItemTime:vTime]) {
        CVPixelBufferRef pb = [gVideoOutput copyPixelBufferForItemTime:vTime itemTimeForDisplay:NULL];
        if (pb) {
            CVPixelBufferRef old = gGlobalBuffer;
            gGlobalBuffer = pb; 
            if (old) CVPixelBufferRelease(old);
        }
    }
}

@interface VCamUniversalProxy : NSProxy <AVCapturePhotoCaptureDelegate>
@property (nonatomic, strong) id originalDelegate;
@end

@implementation VCamUniversalProxy
- (instancetype)initWithDelegate:(id)delegate {
    _originalDelegate = delegate;
    return self;
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    return [self.originalDelegate methodSignatureForSelector:sel];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    [invocation invokeWithTarget:self.originalDelegate];
}
- (BOOL)respondsToSelector:(SEL)sel {
    return [self.originalDelegate respondsToSelector:sel];
}
@end

%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (enabled && delegate) {
        VCamUniversalProxy *proxy = [[VCamUniversalProxy alloc] initWithDelegate:delegate];
        %orig(settings, (id<AVCapturePhotoCaptureDelegate>)proxy);
        return;
    }
    %orig;
}
%end

%hook AVCapturePhoto
- (CVPixelBufferRef)pixelBuffer {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        NSLog(@"[VCP] Spoofing photo pixelBuffer");
        return CVPixelBufferRetain(gGlobalBuffer);
    }
    return %orig;
}

- (CVPixelBufferRef)previewPixelBuffer {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        return CVPixelBufferRetain(gGlobalBuffer);
    }
    return %orig;
}

- (CGImageRef)CGImageRepresentation {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        return [gCIContext createCGImage:ci fromRect:ci.extent];
    }
    return %orig;
}

- (NSData *)fileDataRepresentation {
    RefreshBuffer();
    if (enabled && gGlobalBuffer) {
        NSLog(@"[VCP] Spoofing fileDataRepresentation");
        CIImage *ci = [CIImage imageWithCVPixelBuffer:gGlobalBuffer];
        CGImageRef cg = [gCIContext createCGImage:ci fromRect:ci.extent];
        if (cg) {
            UIImage *ui = [UIImage imageWithCGImage:cg];
            NSData *data = UIImageJPEGRepresentation(ui, 0.9);
            CGImageRelease(cg);
            return data;
        }
    }
    return %orig;
}
%end

@interface VCamVideoDataProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) id originalDelegate;
@end

@implementation VCamVideoDataProxy
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (enabled) {
        RefreshBuffer();
        if (gGlobalBuffer) {
            CMSampleBufferRef newSbuf = NULL;
            CMFormatDescriptionRef formatDesc = NULL;
            CMVideoFormatDescriptionCreateForImageBuffer(NULL, gGlobalBuffer, (CMVideoFormatDescriptionRef *)&formatDesc);
            
            CMSampleTimingInfo timingInfo;
            CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &timingInfo);
            
            CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, gGlobalBuffer, YES, NULL, NULL, (CMVideoFormatDescriptionRef)formatDesc, &timingInfo, &newSbuf);
            
            if (newSbuf) {
                if ([self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                    [self.originalDelegate captureOutput:output didOutputSampleBuffer:newSbuf fromConnection:connection];
                }
                CFRelease(newSbuf);
                if (formatDesc) CFRelease(formatDesc);
                return;
            }
        }
    }
    if ([self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        [self.originalDelegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
    }
}
@end

%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)callbackQueue {
    if (enabled && delegate) {
        VCamVideoDataProxy *proxy = [[VCamVideoDataProxy alloc] init];
        proxy.originalDelegate = delegate;
        objc_setAssociatedObject(self, @selector(setSampleBufferDelegate:queue:), proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        %orig(proxy, callbackQueue);
    } else {
        %orig;
    }
}
%end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    self.hidden = YES;

    if (!gPlayer) {
        loadPrefs();
        gPlayer = [[AVPlayer alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gVideoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
        [gPlayer.currentItem addOutput:gVideoOutput];
        [gPlayer play];

        AVPlayerLayer *pl = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
        pl.frame = self.bounds;
        pl.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.superlayer insertSublayer:pl above:self];

        [NSTimer scheduledTimerWithTimeInterval:0.03 repeats:YES block:^(NSTimer *t) { RefreshBuffer(); }];
    }
}
%end

%ctor {
    loadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)loadPrefs, CFSTR("com.murkaska.virtualcampro/settingschanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);
    %init;
}
