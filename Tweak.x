#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

static BOOL enabled = YES;
// Попробуем основной путь HLS от MediaMTX
static NSString *streamURL = @"http://192.168.1.44:8888/live/stream/index.m3u8";

static AVPlayer *gPlayer = nil;
static AVPlayerLayer *gPlayerLayer = nil;
static UILabel *gStatusLabel = nil;

@interface AVCaptureVideoPreviewLayer (VCam)
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
@end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (!enabled) return;

    self.opacity = 0.0; // Прячем реальную камеру (черный экран - признак работы)

    UIView *container = (UIView *)self.delegate;
    if ([container isKindOfClass:[UIView class]]) {
        if (!gPlayer) {
            NSLog(@"[VCam] Initializing Player with URL: %@", streamURL);
            
            NSURL *url = [NSURL URLWithString:streamURL];
            gPlayer = [AVPlayer playerWithURL:url];
            
            gPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
            gPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            gPlayerLayer.frame = container.bounds;
            
            // Добавляем слой видео прямо в камеру
            [container.layer addSublayer:gPlayerLayer];
            
            gStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, 280, 60)];
            gStatusLabel.textColor = [UIColor yellowColor];
            gStatusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
            gStatusLabel.font = [UIFont boldSystemFontOfSize:12];
            gStatusLabel.numberOfLines = 0;
            gStatusLabel.text = @"VCam: Connecting to stream...";
            [container addSubview:gStatusLabel];
            
            [gPlayer play];
            
            // Следим за статусом игрока
            [gPlayer addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
        }
        gPlayerLayer.frame = container.bounds;
    }
}

// Обработка ошибок плеера
%new
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"status"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gPlayer.status == AVPlayerStatusFailed) {
                gStatusLabel.text = [NSString stringWithFormat:@"VCam Error: %@", gPlayer.error.localizedDescription];
                gStatusLabel.textColor = [UIColor redColor];
            } else if (gPlayer.status == AVPlayerStatusReadyToPlay) {
                gStatusLabel.text = @"● LIVE";
                gStatusLabel.textColor = [UIColor greenColor];
            }
        });
    }
}
%end
