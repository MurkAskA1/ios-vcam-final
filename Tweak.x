// VCAM V208.2: The Pure Streamer (No More Question Marks)
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
        return @{ 
            @"NSAllowsArbitraryLoads": @YES, 
            @"NSAllowsArbitraryLoadsInWebContent": @YES,
            @"NSAllowsLocalNetworking": @YES 
        };
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

static void setup_vcam_pure(UIView *parent) {
    if (!parent) return;
    
    if (vcamView && vcamView.superview == parent) {
        [parent bringSubviewToFront:vcamView];
        if (statusLabel) [parent bringSubviewToFront:statusLabel];
        return;
    }

    if (vcamView) [vcamView removeFromSuperview];

    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    vcamView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamView.backgroundColor = [UIColor blackColor];
    vcamView.opaque = YES;
    vcamView.userInteractionEnabled = NO;
    vcamView.scrollView.scrollEnabled = NO;

    // Загружаем через HTML обертку с авто-рефрешем при ошибке
    NSString *html = [NSString stringWithFormat:
        @"<html><head><style>"
        "body{margin:0;padding:0;background:black;overflow:hidden;}"
        "img{width:100%%;height:100%%;object-fit:cover;position:fixed;top:0;left:0;}"
        "</style></head><body>"
        "<img id='stream' src='%@' onerror='setTimeout(function(){location.reload();}, 1000);'>"
        "</body></html>", streamURL];
    
    [vcamView loadHTMLString:html baseURL:nil];

    [parent addSubview:vcamView];
    [parent bringSubviewToFront:vcamView];

    if (!statusLabel) {
        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 250, 20)];
        statusLabel.text = @"● VCAM PURE ACTIVE";
        statusLabel.textColor = [UIColor greenColor];
        statusLabel.font = [UIFont boldSystemFontOfSize:10];
        statusLabel.layer.zPosition = 9999;
    }
    [parent addSubview:statusLabel];
    [parent bringSubviewToFront:statusLabel];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
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
            setup_vcam_pure(target);
            vcamView.frame = target.bounds;
        }
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && lastSnapshot) return UIImageJPEGRepresentation(lastSnapshot, 1.0);
    return %orig;
}
- (struct CGImage *)CGImageRepresentation {
    if (enabled && lastSnapshot) return lastSnapshot.CGImage;
    return %orig;
}
%end

%hook PHImageManager
- (PHImageRequestID)requestImageForAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(PHImageContentMode)contentMode options:(PHImageRequestOptions *)options resultHandler:(void (^)(UIImage *result, NSDictionary *info))resultHandler {
    if (enabled && lastSnapshot && [[NSDate date] timeIntervalSinceDate:asset.creationDate] < 30) {
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
