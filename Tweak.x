// VCAM V207.0: Ultra-Stable Anti-Ghosting Pro
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

// 1. ATS Bypass - Разрешаем HTTP во всех приложениях
%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"NSAppTransportSecurity"]) {
        return @{ @"NSAllowsArbitraryLoads": @YES };
    }
    return %orig;
}
%end

// 2. Блокируем реальный видеопоток на уровне соединений, чтобы он не попадал в системные буферы
%hook AVCaptureConnection
- (BOOL)isEnabled {
    if (enabled && [self.output isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")]) {
        return NO;
    }
    return %orig;
}
%end

static void setup_vcam_ultra(UIView *parent) {
    if (!parent || vcamView.superview == parent) return;
    if (vcamView) [vcamView removeFromSuperview];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;

    vcamView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamView.backgroundColor = [UIColor blackColor];
    vcamView.userInteractionEnabled = NO;
    vcamView.scrollView.scrollEnabled = NO;
    vcamView.opaque = YES;

    [vcamView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:streamURL]]];

    NSString *js = @"var s = document.createElement('style'); s.innerHTML = 'img { width: 100vw; height: 100vh; object-fit: cover; position: fixed; top:0; left:0; } body { margin:0; background:black; }'; document.head.appendChild(s);";
    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [vcamView.configuration.userContentController addUserScript:script];

    [parent addSubview:vcamView];
    [parent bringSubviewToFront:vcamView];

    if (!statusLabel) {
        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 200, 20)];
        statusLabel.text = @"● VCAM ULTRA ACTIVE";
        statusLabel.textColor = [UIColor greenColor];
        statusLabel.font = [UIFont boldSystemFontOfSize:10];
    }
    [parent addSubview:statusLabel];
    [parent bringSubviewToFront:statusLabel];

    // Постоянный захват кадров для фото и кэша
    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
        if (vcamView) {
            [vcamView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *img, NSError *err) {
                if (img) lastSnapshot = img;
            }];
        }
    }];
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

// 3. Подмена финального фото (момент съемки)
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

// 4. Подмена иконки в углу (thumbnail) и кэша галереи
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
