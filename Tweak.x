// VCAM V84.0: Full Feature (Stream + UI + Prefs)
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static BOOL enabled = YES;
static NSString *rtspURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static UILabel *statusLabel = nil;
static UIWindow *overlayWindow = nil;
static AVPlayer *vcamPlayer = nil;
static AVPlayerLayer *vcamLayer = nil;

void vcam_log(NSString *message) {
    NSString *logPath = @"/var/mobile/Documents/vcam_DEBUG.log";
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterLongStyle];
    NSString *formattedMessage = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[formattedMessage dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    } else {
        [formattedMessage writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

void update_vcam_status(NSString *status, UIColor *color) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (statusLabel) {
            statusLabel.text = [NSString stringWithFormat:@"VCAM: %@", status];
            statusLabel.textColor = color;
        }
    });
    vcam_log(status);
}

void setup_vcam_ui() {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID || ![bundleID hasPrefix:@"com.apple.camera"]) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!overlayWindow) {
            overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            overlayWindow.windowLevel = UIWindowLevelAlert + 1;
            overlayWindow.userInteractionEnabled = NO;
            overlayWindow.backgroundColor = [UIColor blackColor];
            overlayWindow.hidden = NO;
            
            vcamPlayer = [AVPlayer playerWithURL:[NSURL URLWithString:rtspURL]];
            vcamLayer = [AVPlayerLayer playerLayerWithPlayer:vcamPlayer];
            vcamLayer.frame = overlayWindow.bounds;
            vcamLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            [overlayWindow.layer addSublayer:vcamLayer];
            
            statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, 300, 30)];
            statusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
            statusLabel.textColor = [UIColor whiteColor];
            statusLabel.font = [UIFont boldSystemFontOfSize:14];
            statusLabel.layer.cornerRadius = 8;
            statusLabel.clipsToBounds = YES;
            statusLabel.textAlignment = NSTextAlignmentCenter;
            statusLabel.text = @"VCAM: INITIALIZING...";
            [overlayWindow addSubview:statusLabel];
            
            [vcamPlayer play];
        }
        overlayWindow.hidden = !enabled;
        if (enabled) {
            update_vcam_status(@"CONNECTING...", [UIColor yellowColor]);
            // Check if playing
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (vcamPlayer.status == AVPlayerStatusReadyToPlay) {
                    update_vcam_status(@"STREAMING ACTIVE", [UIColor greenColor]);
                }
            });
        }
    });
}

%hook AVCaptureSession
- (void)startRunning {
    %orig;
    vcam_log(@"Capture Session Started");
    setup_vcam_ui();
}
%end

static void loadPrefs() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (prefs) {
        enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        rtspURL = prefs[@"rtspURL"] ? prefs[@"rtspURL"] : rtspURL;
    }
}

%ctor {
    loadPrefs();
    vcam_log(@"Tweak Loaded - Version 84.0");
}
