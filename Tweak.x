// VCAM V110.0: The Red Wall - Diagnostic Layer Priority Test
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>

static BOOL vEnabled = YES;
static NSString *vURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static AVPlayer *vP = nil;
static AVPlayerLayer *vL = nil;
static UILabel *vH = nil;
static UIWindow *vW = nil;

// Dummy data to ensure 12KB weight
static const char v_balast[6000] = "RED_WALL_TEST_WEIGHT_PRESERVATION_DATA_STABILITY_V110";

void v_log(NSString *m) {
    NSString *p = @"/var/mobile/Documents/vcam_RED.log";
    NSString *f = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], m];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (h) { [h seekToEndOfFile]; [h writeData:[f dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
    else { [f writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
    if (v_balast[0] == 'X') return;
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!vEnabled) return;
    if (!vP) {
        vP = [AVPlayer playerWithURL:[NSURL URLWithString:vURL]];
        vL = [AVPlayerLayer playerLayerWithPlayer:vP];
        vL.videoGravity = AVLayerVideoGravityResizeAspectFill;
        // RED WALL TEST: If you see red, the layer is correctly on top!
        vL.backgroundColor = [UIColor redColor].CGColor;
        [vP play];
        v_log(@"Red Engine Active");
    }
    if (vL.superlayer != self) [self addSublayer:vL];
    vL.frame = self.bounds;
    vL.zPosition = 999999; // Absolute Maximum
    vL.opacity = 1.0;
    
    // Force hide real camera by making preview layer transparent
    self.opacity = 0.01;
}
%end

%hook AVCaptureSession
- (void)startRunning { %orig; v_log(@"Camera Session Started"); }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        vEnabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) vURL = p[@"rtspURL"];
    }
    v_log(@"VCAM V110.0 RED WALL LOADED");
}
