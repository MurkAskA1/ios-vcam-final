// VCAM V125.0: The Final Proof - Stable Mirror & Touch Passthrough
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL enabled = YES;
static NSString *rtspURL = @"http://192.168.1.44:8889/live/stream/index.m3u8";
static UIWindow *proofWindow = nil;
static AVPlayer *proofPlayer = nil;
static AVPlayerLayer *proofLayer = nil;
static UILabel *proofHUD = nil;

void proof_log(NSString *msg) {
    NSString *path = @"/var/mobile/Documents/vcam_PROOF.log";
    NSString *formatted = [NSString stringWithFormat:@"[V125] %@\n", msg];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle) { [handle seekToEndOfFile]; [handle writeData:[formatted dataUsingEncoding:NSUTF8StringEncoding]]; [handle closeFile]; }
    else { [formatted writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
}

@interface VCamPassthroughWindow : UIWindow @end
@implementation VCamPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    // Return nil if the hit view is our window or root view, so touches pass to camera app
    if (hitView == self || hitView == self.rootViewController.view) return nil;
    return hitView;
}
@end

static void setup_proof_engine(void) {
    if (proofWindow) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        proofWindow = [[VCamPassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        proofWindow.windowLevel = UIWindowLevelAlert + 5000;
        proofWindow.userInteractionEnabled = YES;
        proofWindow.backgroundColor = [UIColor clearColor];
        proofWindow.hidden = NO;
        
        proofPlayer = [AVPlayer playerWithURL:[NSURL URLWithString:rtspURL]];
        proofLayer = [AVPlayerLayer playerLayerWithPlayer:proofPlayer];
        proofLayer.frame = proofWindow.bounds;
        proofLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        proofLayer.backgroundColor = [UIColor blueColor].CGColor;
        [proofWindow.layer addSublayer:proofLayer];
        
        proofHUD = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, [UIScreen mainScreen].bounds.size.width, 25)];
        proofHUD.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        proofHUD.textColor = [UIColor greenColor];
        proofHUD.font = [UIFont boldSystemFontOfSize:10];
        proofHUD.textAlignment = NSTextAlignmentCenter;
        proofHUD.text = @"[V125.0 ACTIVE]";
        [proofWindow addSubview:proofHUD];
        
        [proofPlayer play];
        proof_log(@"Engine Started");
    });
}

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        setup_proof_engine();
        proofWindow.hidden = NO;
        
        // Front camera mirroring
        AVCaptureSession *s = self.session; BOOL f = NO;
        if (s) {
            for (AVCaptureInput *i in s.inputs) {
                if ([i isKindOfClass:[AVCaptureDeviceInput class]] && ((AVCaptureDeviceInput *)i).device.position == 2) { f = YES; break; }
            }
        }
        proofLayer.transform = f ? CATransform3DMakeAffineTransform(CGAffineTransformMakeScale(-1, 1)) : CATransform3DIdentity;
        [self setOpacity:0.01];
    }
}
%end

%hook AVCaptureSession
- (void)stopRunning { %orig; if (proofWindow) proofWindow.hidden = YES; }
%end

%ctor {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.vcampro.plist"];
    if (p) {
        enabled = p[@"enabled"] ? [p[@"enabled"] boolValue] : YES;
        if (p[@"rtspURL"]) rtspURL = p[@"rtspURL"];
    }
    proof_log(@"Tweak Injected");
}
