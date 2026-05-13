// VirtualCamPro V244.0: The Core Destroyer (Native Engine)
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

static BOOL enabled = YES;
static NSString *streamURL = @"http://192.168.1.44:8889/live/stream";
static UIImage *globalNativeFrame = nil;

@interface VCAMNativeFetcher : NSObject <NSURLSessionDataDelegate>
@property (strong) NSURLSessionDataTask *task;
@property (strong) NSMutableData *buffer;
- (void)start;
@end

@implementation VCAMNativeFetcher
- (instancetype)init {
    if (self = [super init]) {
        _buffer = [[NSMutableData alloc] init];
    }
    return self;
}
- (void)start {
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    _task = [session dataTaskWithURL:[NSURL URLWithString:streamURL]];
    [_task resume];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [_buffer appendData:data];
    const unsigned char startMarker[] = {0xff, 0xd8};
    const unsigned char endMarker[] = {0xff, 0xd9};
    NSData *startData = [NSData dataWithBytes:startMarker length:2];
    NSData *endData = [NSData dataWithBytes:endMarker length:2];
    
    NSRange startRange = [_buffer rangeOfData:startData options:NSDataSearchBackwards range:NSMakeRange(0, [_buffer length])];
    if (startRange.location != NSNotFound) {
        NSRange searchRange = NSMakeRange(startRange.location, [_buffer length] - startRange.location);
        NSRange endRange = [_buffer rangeOfData:endData options:0 range:searchRange];
        if (endRange.location != NSNotFound) {
            NSRange imgRange = NSMakeRange(startRange.location, endRange.location - startRange.location + 2);
            NSData *jpgData = [_buffer subdataWithRange:imgRange];
            UIImage *img = [UIImage imageWithData:jpgData];
            if (img) globalNativeFrame = img;
            [_buffer replaceBytesInRange:NSMakeRange(0, endRange.location + 2) withBytes:NULL length:0];
        }
    }
    if ([_buffer length] > 1024 * 1024 * 5) [_buffer setLength:0];
}
@end

static VCAMNativeFetcher *fetcher = nil;

static void load_prefs() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.murkaska.virtualcampro.plist"];
    if (prefs) {
        enabled = prefs[@"enabled"] ? [prefs[@"enabled"] boolValue] : YES;
        NSString *u = prefs[@"rtspURL"];
        if (u && [u length] > 5) streamURL = u;
    }
}

%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"NSAppTransportSecurity"]) {
        return @{ @"NSAllowsArbitraryLoads": @YES, @"NSAllowsLocalNetworking": @YES };
    }
    return %orig;
}
%end

%hook AVCaptureVideoPreviewLayer
- (void)layoutSublayers {
    %orig;
    if (enabled) {
        self.opacity = 0.0;
        UIView *p = (UIView *)self.delegate;
        if ([p isKindOfClass:[UIView class]]) {
            UIImageView *v = [p viewWithTag:8888];
            if (!v) {
                v = [[UIImageView alloc] initWithFrame:p.bounds];
                v.tag = 8888;
                v.contentMode = UIViewContentModeScaleAspectFill;
                v.clipsToBounds = YES;
                v.backgroundColor = [UIColor blackColor];
                [p insertSubview:v atIndex:0];
            }
            if (globalNativeFrame) v.image = globalNativeFrame;
        }
    }
}
%end

%hook AVCapturePhoto
- (NSData *)fileDataRepresentation {
    if (enabled && globalNativeFrame) return UIImageJPEGRepresentation(globalNativeFrame, 0.9);
    return %orig;
}
%end

%hook CAMImageWell
- (void)setThumbnailImage:(UIImage *)image {
    if (enabled && globalNativeFrame) %orig(globalNativeFrame);
    else %orig(image);
}
%end

%hook PHImageManager
- (PHImageRequestID)requestImageForAsset:(PHAsset *)asset targetSize:(CGSize)size contentMode:(PHImageContentMode)mode options:(PHImageRequestOptions *)options resultHandler:(void (^)(UIImage *result, NSDictionary *info))handler {
    if (enabled && globalNativeFrame && asset.mediaType == PHAssetMediaTypeImage) {
        NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:asset.creationDate];
        if (diff < 60.0) {
            handler(globalNativeFrame, nil);
            return 0;
        }
    }
    return %orig(asset, size, mode, options, handler);
}
%end

%ctor {
    load_prefs();
    if (enabled) {
        fetcher = [[VCAMNativeFetcher alloc] init];
        [fetcher start];
    }
}
