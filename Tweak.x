// VCAM V87.0: Error Hunting & Detailed Logging (Blue Layer Test)
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static BOOL enabled = YES;
static NSString *rtspURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";
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

            // V87.0: Add error observer on the player item for detailed error logging
            if (vcamPlayer.currentItem) {
                [vcamPlayer.currentItem addObserver:vcamPlayer
                                         forKeyPath:@"status"
                                            options:NSKeyValueObservingOptionNew
                                            context:nil];
                vcam_log(@"V87.0: Added KVO observer on currentItem.status");
            }

            // V87.0: Log player and item errors at creation time
            if (vcamPlayer.error) {
                vcam_log([NSString stringWithFormat:@"V87.0: Player error at init: %@", [vcamPlayer.error localizedDescription]]);
            }
            if (vcamPlayer.currentItem.error) {
                vcam_log([NSString stringWithFormat:@"V87.0: Item error at init: %@", [vcamPlayer.currentItem.error localizedDescription]]);
            }

            [vcamPlayer play];

            // 5-second timeout: check whether the player has loaded anything
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (vcamPlayer.currentItem == nil || vcamPlayer.currentItem.status == AVPlayerItemStatusFailed) {
                    // V87.0: Capture detailed error messages from player and item
                    NSString *playerError = [vcamPlayer.error localizedDescription] ?: @"(no player error)";
                    NSString *itemError = [vcamPlayer.currentItem.error localizedDescription] ?: @"(no item error)";
                    vcam_log([NSString stringWithFormat:@"TIMEOUT: Player failed after 5s. Player error: %@ | Item error: %@", playerError, itemError]);

                    // V87.0: Show truncated error in status label instead of generic 'LOAD TIMEOUT'
                    NSString *errorDetail = [vcamPlayer.currentItem.error localizedDescription] ?: [vcamPlayer.error localizedDescription] ?: @"unknown";
                    NSString *truncatedError = errorDetail;
                    if (truncatedError.length > 40) {
                        truncatedError = [[truncatedError substringToIndex:40] stringByAppendingString:@"..."];
                    }
                    update_vcam_status([NSString stringWithFormat:@"TIMEOUT: %@", truncatedError], [UIColor redColor]);
                } else if (vcamPlayer.status != AVPlayerStatusReadyToPlay) {
                    // V87.0: Also log errors in the not-ready branch
                    NSString *playerError = [vcamPlayer.error localizedDescription] ?: @"(none)";
                    NSString *itemError = [vcamPlayer.currentItem.error localizedDescription] ?: @"(none)";
                    vcam_log([NSString stringWithFormat:@"TIMEOUT: Player not ready after 5s. Status: %ld | Player error: %@ | Item error: %@", (long)vcamPlayer.status, playerError, itemError]);
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
    vcam_log(@"Tweak Loaded - Version 87.0");
}
