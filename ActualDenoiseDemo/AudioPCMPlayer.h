//
//  AudioPlayer.h
//  VoiceRecorder
//
//  Created by 赵英杰 on 2025/6/13.
//

#import <AudioToolbox/AudioToolbox.h>

@interface AudioPCMPlayer : NSObject {
    AudioQueueRef audioQueue;
    AudioQueueBufferRef audioQueueBuffer;
    AudioStreamBasicDescription audioFormat;
    int bufferSize;
    int numBuffers;
    FILE *pcmFile;
    NSData *pcmData;
    int sampleRate;
    BOOL _isManualPaused;
    NSInteger _currentFrame;
}

- (instancetype)initWithPCMFilePath:(NSString *)filePath;
- (void)pausePlaying;
- (void)startPlaying;
- (void)resume;
- (void)stopPlaying;

- (BOOL)isAudioQueuePlaying;

@end

