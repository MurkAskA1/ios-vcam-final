// Tweak.x - VirtualCamPro V271.2: MJPEG Stream from RTSP Server
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <Photos/Photos.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import "MJPEGStreamReader.h"

static BOOL enabled = YES;
// ✅ ТВЕ RTSP SERVER MJPEG STREAM
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream";

static MJPEGStreamReader *gReader = nil;
static UIImage *gLastFrame = nil;

// ===== DEBUG LOGGING =====
static void VCamDebug(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[VCamPro] %@ | Time: %@\n", msg, [NSDate date]];
    NSLog(@"%@", line);
    // Логирование в файл для отладки
    @try {
        NSString *path = @"/tmp/vcam_tweak.log";
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } @catch (NSException *e) {
        NSLog(@"Log write failed: %@", e);
    }
}

// 1. Force ATS Bypass for all processes
%hook NSBundle
- (NSDictionary *)infoDictionary {
    NSMutableDictionary *dict = [%orig mutableCopy];
    if (!dict[@"NSAppTransportSecurity"]) {
        dict[@"NSAppTransportSecurity"] = @{ @"NSAllowsArbitraryLoads": @YES };
        VCamDebug(@"ATS bypass applied");
    }
    return dict;
}
%end

// 2. Hybrid Visual Engine: WKWebView для гарантированного подключения
@interface VCamWebView : WKWebView
@end
@implementation VCamWebView
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    self = [super initWithFrame:frame configuration:configuration];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.scrollView.backgroundColor = [UIColor blackColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}
@end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;
    
    self.opacity = 0.0;
    UIView *container = (UIView *)self.delegate;
    if ([container isKindOfClass:[UIView class]]) {
        VCamWebView *web = [container viewWithTag:8888];
        if (!web) {
            VCamDebug(@"Creating WebView for stream");
            
            WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
            config.allowsInlineMediaPlayback = YES;
            config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
            
            web = [[VCamWebView alloc] initWithFrame:container.bounds configuration:config];
            web.tag = 8888;
            [container insertSubview:web atIndex:0];
            
            // ===== CSS для MJPEG потока =====
            NSString *css = @"* { margin: 0; padding: 0; background: black !important; } "
                            "html, body { width: 100%; height: 100%; } "
                            "img { position: fixed !important; top: 0; left: 0; width: 100% !important; height: 100% !important; object-fit: cover !important; z-index: 9999 !important; background: black; } "
                            "video { position: fixed !important; top: 0; left: 0; width: 100% !important; height: 100% !important; object-fit: cover !important; z-index: 9999 !important; } "
                            ".ui, .controls, button, span, nav, header, footer { display: none !important; }";
            
            NSString *js = [NSString stringWithFormat:@"var s = document.createElement('style'); s.innerHTML = '%@'; document.head.appendChild(s);", css];
            WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
            [config.userContentController addUserScript:script];
            
            // ===== LOAD STREAM =====
            NSURL *url = [NSURL URLWithString:streamURL];
            NSURLRequest *req = [NSURLRequest requestWithURL:url];
            VCamDebug(@"Loading stream from: %@", streamURL);
            [web loadRequest:req];
        }
        web.frame = container.bounds;
        
        // On-screen Diagnostic Label
        UILabel *status = [container viewWithTag:7777];
        if (!status) {
            status = [[UILabel alloc] initWithFrame:CGRectMake(10, 100, container.bounds.size.width - 20, 100)];
            status.tag = 7777;
            status.textAlignment = NSTextAlignmentCenter;
            status.font = [UIFont boldSystemFontOfSize:11];
            status.textColor = [UIColor cyanColor];
            status.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
            status.numberOfLines = 0;
            [container addSubview:status];
        }
        
        NSString *readerStatus = @"PENDING";
        if (gReader) {
            if (gReader.frameCount > 0) {
                readerStatus = [NSString stringWithFormat:@"✅ STREAMING (%lu frames)", gReader.frameCount];
            } else {
                readerStatus = @"🔄 CONNECTING...";
            }
        }
        
        status.text = [NSString stringWithFormat:
            @"🎥 VCamPro v271.2\n"
            @"URL: %@\n"
            @"Photo Buffer: %@\n"
            @"Stream: %@",
            streamURL,
            (gLastFrame ? @"✓ READY" : @"✗ EMPTY"),
            readerStatus
        ];
        [container bringSubviewToFront:status];
    }
}
%end

// 3. Absolute Photo Hijack (For Gallery & KYC)
%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && gLastFrame) {
        VCamDebug(@"Returning captured frame as photo (%@)", NSStringFromCGSize(gLastFrame.size));
        return UIImageJPEGRepresentation(gLastFrame, 0.95);
    }
    return %orig;
}
- (CGImageRef)CGImageRepresentation {
    if (enabled && gLastFrame) {
        VCamDebug(@"Returning CGImage from stream frame");
        return gLastFrame.CGImage;
    }
    return %orig;
}
%end

// 4. Hook AVCaptureSession для полного контроля
%hook AVCaptureSession
- (void)startRunning {
    if (enabled) {
        VCamDebug(@"AVCaptureSession.startRunning intercepted");
    }
    %orig;
}
%end

%ctor {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    VCamDebug(@"Tweak loaded in app: %@", bid);
    
    if ([bid containsString:@"camera"] || [bid containsString:@"telegra"] || 
        [bid containsString:@"safari"] || [bid containsString:@"chrome"] || 
        [bid containsString:@"WebKit"] || [bid containsString:@"facetime"] ||
        [bid containsString:@"whatsapp"] || [bid containsString:@"telegram"] ||
        [bid containsString:@"instagram"] || [bid containsString:@"tiktok"] ||
        [bid containsString:@"snapchat"]) {
        
        VCamDebug(@"✓ Target app detected, initializing MJPEG stream reader");
        
        // Background reader for capturing frames
        gReader = [[MJPEGStreamReader alloc] initWithURL:[NSURL URLWithString:streamURL]];
        gReader.frameCallback = ^(UIImage *f) {
            gLastFrame = f;
            if (gReader.frameCount % 10 == 0) {
                VCamDebug(@"Frame received: %@ | Total: %lu", NSStringFromCGSize(f.size), gReader.frameCount);
            }
        };
        gReader.errorCallback = ^(NSError *error) {
            VCamDebug(@"❌ Stream error: %@", error.localizedDescription);
        };
        [gReader startStreaming];
    }
}
