// VCAM V82.0: UI Robustness & Prefs Fix
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

static BOOL enabled = YES; // Default YES for easier debug
static NSString *rtspURL = @"http://192.168.1.44:8889/live/stream";
static UILabel *statusLabel = nil;
static UIWindow *overlayWindow = nil;

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

void setup_vcam_ui() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!overlayWindow) {
            overlayWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 100)];
            overlayWindow.windowLevel = UIWindowLevelAlert + 1;
            overlayWindow.userInteractionEnabled = NO;
            overlayWindow.backgroundColor = [UIColor clearColor];
            overlayWindow.hidden = NO;
            
            statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, 300, 30)];
            statusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
            statusLabel.textColor = [UIColor whiteColor];
            statusLabel.font = [UIFont boldSystemFontOfSize:14];
            statusLabel.layer.cornerRadius = 8;
            statusLabel.clipsToBounds = YES;
            statusLabel.textAlignment = NSTextAlignmentCenter;
            statusLabel.text = @"VCAM: INITIALIZING...";
            [overlayWindow addSubview:statusLabel];
        }
        overlayWindow.hidden = !enabled;
    });
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

%hook AVCaptureSession
- (void)startRunning {
    %orig;
    vcam_log(@"Capture Session Started");
    setup_vcam_ui();
    if (enabled) {
        update_vcam_status(@"CONNECTING...", [UIColor yellowColor]);
    }
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
    vcam_log(@"Tweak Loaded - Version 82.0");
    // Ensure UI is ready when first possible
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        setup_vcam_ui();
    });
}
