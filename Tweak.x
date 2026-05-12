// VCAM V208.0: The Ultimate Stealth Masterpiece
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

// 1. Глобальный обход ATS (HTTP во всех процессах)
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

// 2. Блокировка реального сенсора
%hook AVCaptureConnection
- (BOOL)isEnabled {
    if (enabled && [self.output isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")]) {
        return NO;
    }
    return %orig;
}
%end

static void setup_vcam_ultimate(UIView *parent) {
    if (!parent) return;
    
    if (vcamView && vcamView.superview == parent) {
        [parent bringSubviewToFront:vcamView];
        if (statusLabel) [parent bringSubviewToFront:statusLabel];
        return;
    }

    if (vcamView) [vcamView removeFromSuperview];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    vcamView = [[WKWebView alloc] initWithFrame:parent.bounds configuration:config];
    vcamView.backgroundColor = [UIColor blackColor];
    vcamView.opaque = YES;
    vcamView.userInteractionEnabled = NO; // Пропускаем клики к кнопкам камеры
    vcamView.scrollView.scrollEnabled = NO;
    vcamView.layer.zPosition = 9998; // Чуть ниже надписи

    // HTML с ядерной очисткой UI
    NSString *html = [NSString stringWithFormat:
        @"<html><head><style>"
        "body{margin:0;padding:0;background:black;overflow:hidden;user-select:none;-webkit-user-select:none;}"
        "img{width:100%%;height:100%%;object-fit:cover;position:fixed;top:0;left:0;pointer-events:none;}"
        "*::-webkit-media-controls { display:none !important; }"
        "</style></head>"
        "<body><img src='%@' onerror=\"this.src=this.src;\">"
        "<script>document.addEventListener('contextmenu', e => e.preventDefault());</script>"
        "</body></html>", streamURL];
    
    [vcamView loadHTMLString:html baseURL:nil];

    [parent addSubview:vcamView];
    [parent bringSubviewToFront:vcamView];

    if (!statusLabel) {
        statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 250, 20)];
        statusLabel.text = @"● VCAM ULTIMATE ACTIVE";
        statusLabel.textColor = [UIColor greenColor];
        statusLabel.font = [UIFont boldSystemFontOfSize:10];
        statusLabel.layer.zPosition = 9999;
        statusLabel.alpha = 0.7;
    }
    [parent addSubview:statusLabel];
    [parent bringSubviewToFront:statusLabel];

    // Таймер захвата кадров (Shared Buffer)
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

// Хук на превью (работает везде: Камера, TG, Браузеры)
%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *target = nil;
        if ([self.delegate isKindOfClass:[UIView class]]) target = (UIView *)self.delegate;
        else if ([self.superlayer.delegate isKindOfClass:[UIView class]]) target = (UIView *)self.superlayer.delegate;

        if (target) {
            setup_vcam_ultimate(target);
            vcamView.frame = target.bounds;
        }
    }
}
%end

// 3. Подмена финального фото (включая метаданные)
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

// 4. Идеальная подмена миниатюр (Thumbnail Hijack)
%hook PHImageManager
- (PHImageRequestID)requestImageForAsset:(PHAsset *)asset 
                             targetSize:(CGSize)targetSize 
                            contentMode:(PHImageContentMode)contentMode 
                                options:(PHImageRequestOptions *)options 
                          resultHandler:(void (^)(UIImage *result, NSDictionary *info))resultHandler {
    
    // Подменяем только свежие снимки (последние 30 сек), чтобы не портить старую галерею
    if (enabled && lastSnapshot && [[NSDate date] timeIntervalSinceDate:asset.creationDate] < 30) {
        if (resultHandler) {
            resultHandler(lastSnapshot, nil);
            return (PHImageRequestID)1;
        }
    }
    return %orig;
}
%end

// Для старых приложений и Telegram Picker
%hook UIImage
+ (UIImage *)imageWithCGImage:(CGImageRef)cgImage {
    if (enabled && lastSnapshot && cgImage) {
        // Если это фото из камеры (большое), подменяем
        size_t width = CGImageGetWidth(cgImage);
        if (width > 500) return lastSnapshot;
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
