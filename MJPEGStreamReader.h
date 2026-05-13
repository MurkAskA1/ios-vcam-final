// MJPEGStreamReader.h
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MJPEGFrameCallback)(UIImage *frame);
typedef void (^MJPEGErrorCallback)(NSError *error);

@interface MJPEGStreamReader : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong, readonly) NSURL *streamURL;
@property (nonatomic, assign, readonly) BOOL isConnecting;
@property (nonatomic, assign, readonly) NSUInteger frameCount;
@property (nonatomic, copy, nullable) MJPEGFrameCallback frameCallback;
@property (nonatomic, copy, nullable) MJPEGErrorCallback errorCallback;

- (instancetype)initWithURL:(NSURL *)url;
- (void)startStreaming;
- (void)stopStreaming;
@end

NS_ASSUME_NONNULL_END
