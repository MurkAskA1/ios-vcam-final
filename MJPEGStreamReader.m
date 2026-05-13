// MJPEGStreamReader.m - VirtualCamPro V271.2: Optimized for RTSP MJPEG
#import "MJPEGStreamReader.h"
#import <objc/runtime.h>
#import <objc/message.h>

static void VCamLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[MJPEGReader] %@\n", msg];
    NSLog(@"%@", line);
    @try {
        NSString *path = @"/tmp/vcam_mjpeg.log";
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
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
@property (nonatomic, assign) NSUInteger bytesReceived;
@property (nonatomic, strong) NSString *boundaryMarker;
@end

@implementation MJPEGStreamReader

- (instancetype)initWithURL:(NSURL *)url {
    if (self = [super init]) {
        _streamURL = url;
        _receiveBuffer = [[NSMutableData alloc] init];
        _parseQueue = dispatch_queue_create("com.vcam.mjpeg.parse", DISPATCH_QUEUE_SERIAL);
        _bytesReceived = 0;
        VCamLog(@"Initialized with URL: %@", url);
    }
    return self;
}

- (void)startStreaming {
    [self stopStreaming];
    self.isConnecting = YES;
    VCamLog(@"🚀 Starting MJPEG stream from: %@", self.streamURL);
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.timeoutIntervalForResource = 0; // Infinite stream
    config.timeoutIntervalForRequest = 30;
    config.HTTPMaximumConnectionsPerHost = 1;
    config.waitsForConnectivity = YES;
    config.HTTPShouldUsePipelining = NO;
    
    // Force ATS bypass
    @try {
        SEL sel = NSSelectorFromString(@"_setAllowsArbitraryLoads:");
        if ([config respondsToSelector:sel]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(config, sel, YES);
            VCamLog(@"ATS bypass applied to URLSessionConfiguration");
        }
    } @catch (NSException *e) {
        VCamLog(@"⚠️ ATS bypass failed: %@", e);
    }

    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    self.dataTask = [self.session dataTaskWithURL:self.streamURL];
    [self.dataTask resume];
    VCamLog(@"HTTP GET request initiated");
}

- (void)stopStreaming {
    self.isConnecting = NO;
    [self.dataTask cancel];
    [self.session invalidateAndCancel];
    self.session = nil;
    dispatch_async(self.parseQueue, ^{ [self.receiveBuffer setLength:0]; });
    VCamLog(@"⏹ Stream stopped");
}

// ===== NSURLSessionDataDelegate methods =====

- (void)URLSession:(NSURLSession *)session 
          dataTask:(NSURLSessionDataTask *)dataTask 
    didReceiveResponse:(NSURLResponse *)response 
     completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    NSString *contentType = [httpResponse valueForHTTPHeaderField:@"Content-Type"];
    
    VCamLog(@"📡 HTTP Response | Status: %ld | Content-Type: %@", 
        httpResponse.statusCode, contentType);
    
    if (httpResponse.statusCode != 200) {
        VCamLog(@"❌ HTTP Error: %ld", httpResponse.statusCode);
        completionHandler(NSURLSessionResponseCancel);
        return;
    }
    
    // Extract boundary marker if multipart/x-mixed-replace
    if ([contentType containsString:@"multipart"]) {
        NSRange boundaryRange = [contentType rangeOfString:@"boundary="];
        if (boundaryRange.location != NSNotFound) {
            NSString *boundary = [contentType substringFromIndex:boundaryRange.location + boundaryRange.length];
            boundary = [boundary stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            self.boundaryMarker = boundary;
            VCamLog(@"Boundary detected: %@", boundary);
        }
    }
    
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    dispatch_async(self.parseQueue, ^{
        [self.receiveBuffer appendData:data];
        self.bytesReceived += data.length;
        
        if (self.bytesReceived % 512000 == 0) { // Log every 500KB
            VCamLog(@"📊 Received %lu KB | Buffer: %lu KB", 
                self.bytesReceived / 1024, 
                self.receiveBuffer.length / 1024);
        }
        
        [self parseJPEGFrames];
    });
}

- (void)parseJPEGFrames {
    const uint8_t *bytes = (const uint8_t *)self.receiveBuffer.bytes;
    NSUInteger len = self.receiveBuffer.length;
    
    // Find JPEG Start of Image (SOI): 0xFF 0xD8
    NSInteger soi = -1;
    if (len > 2) {
        for (NSUInteger i = 0; i <= len - 2; i++) {
            if (bytes[i] == 0xFF && bytes[i+1] == 0xD8) { 
                soi = i; 
                break;
            }
        }
    }
    
    if (soi != -1) {
        // Find JPEG End of Image (EOI): 0xFF 0xD9
        NSInteger eoi = -1;
        if (len > soi + 2) {
            for (NSUInteger i = soi + 2; i <= len - 2; i++) {
                if (bytes[i] == 0xFF && bytes[i+1] == 0xD9) { 
                    eoi = i; 
                    break;
                }
            }
        }
        
        if (eoi != -1) {
            NSData *jpg = [self.receiveBuffer subdataWithRange:NSMakeRange(soi, eoi - soi + 2)];
            UIImage *img = [UIImage imageWithData:jpg];
            
            if (img) {
                self.frameCount++;
                self.lastFrameTime = CFAbsoluteTimeGetCurrent();
                
                if (self.frameCount % 15 == 0 || self.frameCount <= 3) {
                    VCamLog(@"✅ Frame #%lu decoded | Size: %@ | Data: %lu bytes", 
                        self.frameCount, 
                        NSStringFromCGSize(img.size), 
                        jpg.length);
                }
                
                if (self.frameCallback) {
                    dispatch_async(dispatch_get_main_queue(), ^{ 
                        self.frameCallback(img); 
                    });
                }
            } else {
                if (self.frameCount < 5) {
                    VCamLog(@"⚠️ Failed to decode JPEG | Size: %lu bytes | SOI: %ld | EOI: %ld", 
                        jpg.length, soi, eoi);
                }
            }
            
            // Remove processed data from buffer
            [self.receiveBuffer replaceBytesInRange:NSMakeRange(0, eoi + 2) withBytes:NULL length:0];
        }
    }
    
    // Prevent memory leak
    if (self.receiveBuffer.length > 1024 * 1024 * 32) { // 32 MB limit
        VCamLog(@"⚠️ Buffer overflow (%lu MB), clearing", self.receiveBuffer.length / (1024*1024));
        [self.receiveBuffer setLength:0];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error && self.isConnecting) {
        VCamLog(@"❌ Stream disconnected: %@ (Code: %ld)", error.localizedDescription, error.code);
        
        // Auto-reconnect after 3 seconds
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.isConnecting) {
                VCamLog(@"🔄 Auto-reconnecting...");
                [self startStreaming];
            }
        });
    } else if (!error) {
        VCamLog(@"Stream completed normally");
    }
}

@end
