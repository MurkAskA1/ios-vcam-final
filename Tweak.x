// VCAM V148.0: The Reliable HLS Restoration - Zero Buffering, Stealth Integration
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static AVPlayer *vcamPlayer = nil;
static AVPlayerLayer *vcamPlayerLayer = nil;
static AVPlayerItemVideoOutput *videoOutput = nil;
static UILabel *statusLabel = nil;

static void update_status(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (statusLabel) statusLabel.text = [NSString stringWithFormat:@"VCAM: %@", text];
    });
}

static void setup_hls_player(UIView *parent) {
    if (!parent || (vcamPlayerLayer && vcamPlayerLayer.superlayer == parent.layer)) return;
    if (vcamPlayerLayer) [vcamPlayerLayer removeFromSuperlayer];
    if (statusLabel) [statusLabel removeFromSuperview];

    // Diagnostic Label
    statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, parent.bounds.size.width - 40, 60)];
    statusLabel.textColor = [UIColor greenColor];
    statusLabel.font = [UIFont boldSystemFontOfSize:12];
    statusLabel.numberOfLines = 0;
    statusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    [parent addSubview:statusLabel];
    update_status([NSString stringWithFormat:@"Loading %@", streamURL]);

    NSURL *url = [NSURL URLWithString:streamURL];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    
    vcamPlayer = [AVPlayer playerWithPlayerItem:item];
    vcamPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    vcamPlayer.automaticallyWaitsToMinimizeStalling = NO;

    videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    [item addOutput:videoOutput];

    vcamPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:vcamPlayer];
    vcamPlayerLayer.frame = parent.bounds;
    vcamPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    vcamPlayerLayer.backgroundColor = [UIColor blackColor].CGColor;

    [parent.layer insertSublayer:vcamPlayerLayer atIndex:0];
    [vcamPlayer play];

    // Observer for readiness
    [item addObserver:[[NSObject alloc] init] forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        UIView *p = (UIView *)self.delegate;
        if (!p || ![p isKindOfClass:[UIView class]]) p = (UIView *)self.superlayer.delegate;
        if (p && [p isKindOfClass:[UIView class]]) {
            setup_hls_player(p);
            vcamPlayerLayer.frame = p.bounds;
            
            AVCaptureSession *s = self.session;
            BOOL isFront = NO;
            if (s) {
                for (AVCaptureDeviceInput *i in s.inputs) {
                    if (i.device.position == 2) { isFront = YES; break; }
                }
            }
            vcamPlayerLayer.transform = isFront ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity;
            [self setOpacity:0.0];
        }
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && videoOutput) {
        CMTime itemTime = [vcamPlayer.currentItem currentTime];
        CVPixelBufferRef buffer = [videoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:nil];
        if (buffer) {
            CIImage *ci = [CIImage imageWithCVPixelBuffer:buffer];
            CIContext *context = [CIContext context];
            CGImageRef cgImg = [context createCGImage:ci fromRect:ci.extent];
            UIImage *img = [UIImage imageWithCGImage:cgImg];
            CGImageRelease(cgImg);
            CVPixelBufferRelease(buffer);
            return UIImageJPEGRepresentation(img, 0.95);
        }
    }
    return %orig;
}

- (struct CGImage *)CGImageRepresentation {
    if (enabled && videoOutput) {
        CVPixelBufferRef buffer = [videoOutput copyPixelBufferForItemTime:[vcamPlayer.currentItem currentTime] itemTimeForDisplay:nil];
        if (buffer) {
            CIImage *ci = [CIImage imageWithCVPixelBuffer:buffer];
            CGImageRef cg = [[CIContext context] createCGImage:ci fromRect:ci.extent];
            CVPixelBufferRelease(buffer);
            return cg;
        }
    }
    return %orig;
}
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) {
            NSString *raw = p[@"rtspURL"];
            if (![raw hasSuffix:@"/index.m3u8"]) {
                if ([raw hasSuffix:@"/"]) raw = [raw stringByAppendingString:@"index.m3u8"];
                else raw = [raw stringByAppendingString:@"/index.m3u8"];
            }
            streamURL = raw;
        }
    }
}