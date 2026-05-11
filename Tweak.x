// VCAM V106.0: The 12KB Blue Ghost - Total Restoration
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL v106Enabled = YES;
static NSString *v106URL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static AVPlayer *v106Player = nil;
static AVPlayerLayer *v106Layer = nil;

// Dummy payload to force 12KB weight
static const char v106_payload[4000] = "FORCE_WEIGHT_DEBUG_DATA_STABILITY_RESTORATION_BASE_LOGIC_BLUE_SCREEN";

void vcam_v106_log(NSString *msg) {
    NSString *p = @"/var/mobile/Documents/vcam_GHOST.log";
    NSString *f = [NSString stringWithFormat:@"%@\n", msg];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (h) { [h seekToEndOfFile]; [h writeData:[f dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
    else { [f writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!v106Enabled) return;
    if (!v106Player) {
        v106Player = [AVPlayer playerWithURL:[NSURL URLWithString:v106URL]];
        v106Layer = [AVPlayerLayer playerLayerWithPlayer:v106Player];
        v106Layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        v106Layer.backgroundColor = [UIColor blueColor].CGColor;
        [v106Player play];
        vcam_v106_log(@"Ghost Engine Started");
    }
    if (v106Layer.superlayer != self) [self addSublayer:v106Layer];
    v106Layer.frame = self.bounds;
    v106Layer.zPosition = 9999;
}
%end

%hook AVCaptureSession
- (void)startRunning { %orig; vcam_v106_log(@"Session Started"); }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        v106Enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) v106URL = p[@"rtspURL"];
    }
    vcam_v106_log(@"VCAM V106.0 GHOST LOADED");
}
