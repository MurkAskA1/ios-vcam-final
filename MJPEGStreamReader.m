// MJPEGStreamReader.m
#import "MJPEGStreamReader.h"

@interface MJPEGStreamReader ()
@property (nonatomic, strong, readwrite) NSURL *streamURL;
@property (nonatomic, assign, readwrite) BOOL isConnecting;
@property (nonatomic, assign, readwrite) NSUInteger frameCount;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableData *buffer;
@end

@implementation MJPEGStreamReader

- (instancetype)initWithURL:(NSURL *)url {
    if (self = [super init]) {
        _streamURL = url;
        _buffer = [NSMutableData data];
    }
    return self;
}

- (void)startStreaming {
    [self stopStreaming];
    self.isConnecting = YES;
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    [[self.session dataTaskWithURL:self.streamURL] resume];
}

- (void)stopStreaming {
    self.isConnecting = NO;
    [self.session invalidateAndCancel];
    self.session = nil;
    self.buffer.length = 0;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [self.buffer appendData:data];
    const unsigned char startMarker[] = {0xff, 0xd8};
    const unsigned char endMarker[] = {0xff, 0xd9};
    NSData *startData = [NSData dataWithBytes:startMarker length:2];
    NSData *endData = [NSData dataWithBytes:endMarker length:2];
    
    NSRange startRange = [self.buffer rangeOfData:startData options:NSDataSearchBackwards range:NSMakeRange(0, self.buffer.length)];
    if (startRange.location != NSNotFound) {
        NSRange endRange = [self.buffer rangeOfData:endData options:0 range:NSMakeRange(startRange.location, self.buffer.length - startRange.location)];
        if (endRange.location != NSNotFound) {
            NSRange imgRange = NSMakeRange(startRange.location, endRange.location - startRange.location + 2);
            NSData *jpgData = [self.buffer subdataWithRange:imgRange];
            UIImage *img = [UIImage imageWithData:jpgData];
            if (img) {
                self.frameCount++;
                if (self.frameCallback) self.frameCallback(img);
            }
            [self.buffer replaceBytesInRange:NSMakeRange(0, endRange.location + 2) withBytes:NULL length:0];
        }
    }
    if (self.buffer.length > 1024 * 1024 * 5) self.buffer.length = 0;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error && self.errorCallback) self.errorCallback(error);
    if (self.isConnecting) [self performSelector:@selector(startStreaming) withObject:nil afterDelay:2.0];
}

@end
