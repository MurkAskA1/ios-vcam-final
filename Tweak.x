// VCAM V207.1: White Screen Fix + HTML Wrapper
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live.mjpg";
static WKWebView *vcamView = nil;
static UIImage *lastSnapshot = nil;
static UILabel *statusLabel = nil;

%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"NSAppTransportSecurity"]) {
        return @{ @"NSAllowsArbitraryLoads": @YES, @"NSAllowsArbitraryLoadsInWebContent": @YES };
    }
    return %orig;
}
%end

%hook AVCaptureConnection
- (BOOL)isEnabled {
    if (enabled && [self.output isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")]) {
        return NO;
    }
    return %orig;
}
%end

static void setup_vcam_ultra(UIView *parent) {
    if (!parent) return;
    
    if (vcamView && vcamView.superview == parent) {
        [parent bringSubviewToFront:vcamView];
        if (statusLabel) [parent bringSubviewToFront:statusLabel];
        return;
    }

    if (vcamView) [vcamView removeFromSuperview];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    
    vcamView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamView.backgroundColor = [UIColor blackColor];
    vcamView.opaque = YES;
    vcamView.userInteractionEnabled = NO;
    vcamView.scrollView.scrollEnabled = NO;

    // Обертка в HTML для стабильного отображения MJPEG
    NSString *html = [NSString stringWithFormat:
        @"<html><head><style>body{margin:0;padding:0;background:black;overflow:hidden;} img{width:100%%;height:100%%;object-fit:cover;position:fixed;top:0;left:0;}</style></head>"
        "<body><img src='%@' onerror=\"this.src=this.src;\"></body></html>", streamURL];
    
    [vcamView loadHTMLString:html baseURL:nil];

    [parent addSubview:vcamView];
    [parent bringSubviewToFront:vcamView];

    if (!statusLabel) {
        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 250, 20)];
        statusLabel.text = @"● VCAM ULTRA ACTIVE (FIXED)";
        statusLabel.textColor = [UIColor greenColor];
        statusLabel.font = [UIFont boldSystemFontOfSize:10];
        statusLabel.layer.zPosition = 9999;
    }
    [parent addSubview:statusLabel];
    [parent bringSubviewToFront:statusLabel];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *t) {
            if (vcamView) {
                [vcamView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
                    if (img) lastSnapshot = img;
                }];
            }
        }];
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *target = nil;
        if ([self.delegate isKindOfClass:[UIView class]]) target = (UIView *)self.delegate;
        else if ([self.superlayer.delegate isKindOfClass:[UIView class]]) target = (UIView *)self.superlayer.delegate;

        if (target) {
            setup_vcam_ultra(target);
            vcamView.frame = target.bounds;
        }
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && lastSnapshot) return UIImageJPEGRepresentation(lastSnapshot, 0.9);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation {
    if (enabled && lastSnapshot) return lastSnapshot.CGImage;
    return %orig;
}
%end

%hook PHImageManager
- (PHImageRequestID)requestImageForAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(PHImageContentMode)contentMode options:(PHImageRequestOptions *)options resultHandler:(void (^)(UIImage *result, NSDictionary *info))resultHandler {
    if (enabled && lastSnapshot && [[NSDate date] timeIntervalSinceDate:asset.creationDate] < 15) {
        if (resultHandler) {
            resultHandler(lastSnapshot, nil);
            return (PHImageRequestID)1;
        }
    }
    return %orig;
}
%end

%ctor {
    NSUserDefaults *defs = [[NSUserDefaults alloc] initWithSuiteName:@"com.murkaska.virtualcampro"];
    enabled = [defs objectForKey:@"enabled"] ? [defs boolForKey:@"enabled"] : YES;
    NSString *str = [defs stringForKey:@"rtspURL"];
    if (str && str.length > 5) streamURL = str;
}
