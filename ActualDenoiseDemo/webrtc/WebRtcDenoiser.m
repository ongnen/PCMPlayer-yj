#import "WebRtcDenoiser.h"
#import "noise_suppression.h"

@interface WebRtcDenoiser () {
    NsHandle *_nsHandle;
    int _samplesPerFrame; // 320 for 16kHz & 20ms
}

@end

@implementation WebRtcDenoiser

- (instancetype)initWithSampleRate:(int)sampleRate {
    self = [super init];
    if (self) {
        _samplesPerFrame = sampleRate / 1000 * 20; // e.g. 16000/1000*20 = 320
        _nsHandle = WebRtcNs_Create();
        if (!_nsHandle) {
            NSLog(@"WebRtcNs_Create failed");
            return nil;
        }
        if (WebRtcNs_Init(_nsHandle, sampleRate) != 0) {
            NSLog(@"WebRtcNs_Init failed");
            return nil;
        }
        WebRtcNs_set_policy(_nsHandle, 2); // 0 Mild, 1 Medium, 2 Aggressive
    }
    return self;
}

- (void)setDenoiseLevel:(VRWebrtcDenoiseLevel)level{
    
    WebRtcNs_set_policy(_nsHandle, (int)level-1); // 0 Mild, 1 Medium, 2 Aggressive
}

- (nullable NSData *)processFrame:(NSData *)pcmFrame {
    if (!_nsHandle || pcmFrame.length != 320 * sizeof(int16_t)) { // 20ms frame @ 16kHz
        NSLog(@"帧数据不合法");
        return nil;
    }

    const int frameSize = 160; // 10ms @ 16kHz
    int16_t tempOut[320]; // 输出 buffer

    const int16_t *inputBuffer = (const int16_t *)pcmFrame.bytes;

    for (int i = 0; i < 2; i++) {
        int16_t tempIn[frameSize];
        memcpy(tempIn, inputBuffer + i * frameSize, frameSize * sizeof(int16_t));

        int16_t *nsIn[1] = { tempIn };
        int16_t *nsOut[1] = { tempOut + i * frameSize };

        WebRtcNs_Analyze(_nsHandle, nsIn[0]); // 必须每帧都 Analyze
        WebRtcNs_Process(_nsHandle, (const int16_t *const *)nsIn, 1, nsOut);
    }

    return [NSData dataWithBytes:tempOut length:320 * sizeof(int16_t)];
}


- (void)reset {
    if (_nsHandle) {
        WebRtcNs_Free(_nsHandle);
        _nsHandle = WebRtcNs_Create();
        WebRtcNs_Init(_nsHandle, 16000);
        WebRtcNs_set_policy(_nsHandle, 2);
    }
}

- (void)destroy {
    if (_nsHandle) {
        WebRtcNs_Free(_nsHandle);
        _nsHandle = NULL;
    }
}

- (void)dealloc {
    [self destroy];
}

@end
