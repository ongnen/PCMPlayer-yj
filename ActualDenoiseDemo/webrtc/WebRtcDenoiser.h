//
//  WebRtcDenoiser.h
//  ActualDenoiseDemo
//
//  Created by 赵英杰 on 2025/6/15.
//


// WebRtcDenoiser.h
#import <Foundation/Foundation.h>
typedef enum : NSUInteger {
    VRWebrtcDenoiseLevelNone,
    VRWebrtcDenoiseLevel0,
    VRWebrtcDenoiseLevel1,
    VRWebrtcDenoiseLevel2,
} VRWebrtcDenoiseLevel;

NS_ASSUME_NONNULL_BEGIN

@interface WebRtcDenoiser : NSObject

- (instancetype)initWithSampleRate:(int)sampleRate;
- (nullable NSData *)processFrame:(NSData *)pcmFrame; // 每帧长度必须为 640 字节（16kHz、20ms、int16）
- (void)reset;
- (void)destroy;
- (void)setDenoiseLevel:(VRWebrtcDenoiseLevel)level;
@end

NS_ASSUME_NONNULL_END
