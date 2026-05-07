// VCAM V86.0: Visual Debugging (Blue Layer Test)
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

void setup_status_bar() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!overlayWindow) {
            overlayWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 100)];
            overlayWindow.windowLevel = UIWindowLevelAlert + 2;
            overlayWindow.userInteractionEnabled = NO;
            overlayWindow.backgroundColor = [UIColor clearColor];
            overlayWindow.hidden = NO;

            statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, 300, 25)];
            statusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
            statusLabel.textColor = [UIColor whiteColor];
            statusLabel.font = [UIFont boldSystemFontOfSize:12];
            statusLabel.layer.cornerRadius = 5;
            statusLabel.clipsToBounds = YES;
            statusLabel.textAlignment = NSTextAlignmentCenter;
            [overlayWindow addSubview:statusLabel];
        }
        overlayWindow.hidden = !enabled;
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        if (!vcamPlayer) {
            vcamPlayer = [AVPlayer playerWithURL:[NSURL URLWithString:rtspURL]];
            vcamLayer = [AVPlayerLayer playerLayerWithPlayer:vcamPlayer];
            vcamLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            // DEBUG: Blue background visible if no video is rendered
            vcamLayer.backgroundColor = [UIColor blueColor].CGColor;
            vcamPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
            [vcamPlayer play];

            // 5-second timeout: check whether the player has loaded anything
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (vcamPlayer.currentItem == nil || vcamPlayer.currentItem.status == AVPlayerItemStatusFailed) {
                    vcam_log(@"TIMEOUT: Player failed to load after 5 seconds");
                    update_vcam_status(@"LOAD TIMEOUT", [UIColor redColor]);
                } else if (vcamPlayer.status != AVPlayerStatusReadyToPlay) {
                    vcam_log(@"TIMEOUT: Player not ready after 5 seconds");
                    update_vcam_status(@"NOT READY", [UIColor orangeColor]);
                } else {
                    vcam_log(@"Timeout check passed - player ready");
                }
            });
        }

        // Always re-attach the layer if it was removed
        if (vcamLayer.superlayer != self) {
            [self addSublayer:vcamLayer];
        }

        // Always match the preview layer's size and stay on top
        vcamLayer.frame = self.bounds;
        vcamLayer.zPosition = 999;

        if (vcamPlayer.status == AVPlayerStatusReadyToPlay) {
            update_vcam_status(@"STREAMING ACTIVE", [UIColor greenColor]);
        } else {
            update_vcam_status(@"CONNECTING...", [UIColor yellowColor]);
        }
    }
}
%end

%hook AVCaptureSession
- (void)startRunning {
    %orig;
    vcam_log(@"Capture Session Started");
    setup_status_bar();
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
    vcam_log(@"Tweak Loaded - Version 86.0");
}
