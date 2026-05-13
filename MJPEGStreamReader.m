// MJPEGStreamReader.m - VirtualCamPro V247.1
#import "MJPEGStreamReader.h"
#import <objc/runtime.h>
#import <objc/message.h> // Added missing header for objc_msgSend

static void VCamLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[VCam] %@\n", msg];
    NSLog(@"%@", line);
    @try {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/vcam_debug.log"];
        if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    } @catch (NSException *e) {}
}

@interface MJPEGStreamReader () <NSURLSessionDataDelegate>
@property (nonatomic, strong, readwrite) NSURL *streamURL;
@property (nonatomic, assign, readwrite) BOOL isConnecting;
@property (nonatomic, assign, readwrite) NSUInteger frameCount;
@property (nonatomic, assign, readwrite) CFAbsoluteTime lastFrameTime;
@property (nonatomic, strong, nullable) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *dataTask;
@property (nonatomic, strong) NSMutableData *receiveBuffer;
@property (nonatomic, strong) dispatch_queue_t parseQueue;
@end

@implementation MJPEGStreamReader

- (instancetype)initWithURL:(NSURL *)url {
    if (self = [super init]) {
        _streamURL = url;
        _receiveBuffer = [NSMutableData data];
        _parseQueue = dispatch_queue_create("com.vcam.mjpeg.parse", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)startStreaming {
    [self stopStreaming];
    self.isConnecting = YES;
    VCamLog(@"Starting session for %@", self.streamURL);
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.timeoutIntervalForResource = 0;
    
    // ATS Bypass on session level
    @try {
        SEL sel = NSSelectorFromString(@"_setAllowsArbitraryLoads:");
        if ([config respondsToSelector:sel]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(config, sel, YES);
        }
    } @catch (NSException *e) {}

    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    self.dataTask = [self.session dataTaskWithURL:self.streamURL];
    [self.dataTask resume];
}

- (void)stopStreaming {
    self.isConnecting = NO;
    [self.dataTask cancel];
    [self.session invalidateAndCancel];
    self.session = nil;
    VCamLog(@"Session stopped.");
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    dispatch_async(self.parseQueue, ^{
        [self.receiveBuffer appendData:data];
        const uint8_t *bytes = (const uint8_t *)self.receiveBuffer.bytes;
        NSUInteger len = self.receiveBuffer.length;
        
        NSInteger soi = -1;
        if (len > 2) {
            for (NSUInteger i = 0; i <= len - 2; i++) {
                if (bytes[i] == 0xFF && bytes[i+1] == 0xD8) { soi = i; break; }
            }
        }
        
        if (soi != -1) {
            NSInteger eoi = -1;
            if (len > soi + 2) {
                for (NSUInteger i = soi + 2; i <= len - 2; i++) {
                    if (bytes[i] == 0xFF && bytes[i+1] == 0xD9) { eoi = i; break; }
                }
            }
            
            if (eoi != -1) {
                NSData *jpg = [self.receiveBuffer subdataWithRange:NSMakeRange(soi, eoi - soi + 2)];
                UIImage *img = [UIImage imageWithData:jpg];
                if (img) {
                    self.frameCount++;
                    self.lastFrameTime = CFAbsoluteTimeGetCurrent();
                    if (self.frameCallback) {
                        dispatch_async(dispatch_get_main_queue(), ^{ self.frameCallback(img); });
                    }
                }
                [self.receiveBuffer replaceBytesInRange:NSMakeRange(0, eoi + 2) withBytes:NULL length:0];
            }
        }
        if (self.receiveBuffer.length > 1024 * 1024 * 8) [self.receiveBuffer setLength:0];
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) VCamLog(@"Session error: %@", error.localizedDescription);
    if (self.isConnecting) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startStreaming];
        });
    }
}

@end
