//
//  AudioPlayer.m
//  VoiceRecorder
//
//  Created by 赵英杰 on 2025/6/13.
//

#import "AudioPCMPlayer.h"
//#import "FfmpegNoiseTool.h"


void audioQueueOutputCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer);

@implementation AudioPCMPlayer

- (instancetype)initWithPCMFilePath:(NSString *)filePath {
    self = [super init];
    if (self) {
        // 设置音频格式
        memset(&audioFormat, 0, sizeof(audioFormat));
        audioFormat.mFormatID = kAudioFormatLinearPCM;
        audioFormat.mSampleRate = 16000;  // 假设采样率为 16000
        audioFormat.mChannelsPerFrame = 1;
        audioFormat.mBitsPerChannel = 16;
        audioFormat.mBytesPerFrame = 2;
        audioFormat.mFramesPerPacket = 1;
        audioFormat.mBytesPerPacket = 2;
        audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        
        bufferSize = 320;  // 缓冲区大小
        numBuffers = 3;     // 使用 3 个缓冲区
        
        // 打开 PCM 文件
        pcmFile = fopen([filePath UTF8String], "rb");
        if (pcmFile == NULL) {
            NSLog(@"Error opening PCM file.");
            return nil;
        }
        
        sampleRate = 16000;  // 假设为 44100 Hz
    }
    return self;
}

- (void)startPlaying {
    // 创建音频队列
    OSStatus status = AudioQueueNewOutput(&audioFormat, audioQueueOutputCallback, (__bridge void *)self, NULL, NULL, 0, &audioQueue);
    // 禁用采样率转换
    // 启用精确时间控制（防止系统自动变速）
//    UInt32 enableTimePitch = 1;
//    AudioQueueSetProperty(audioQueue,
//                         kAudioQueueProperty_EnableTimePitch,
//                         &enableTimePitch,
//                         sizeof(enableTimePitch));
//
//    // 设置时间伸缩算法质量（iOS 8+）
//    UInt32 timePitchAlgorithm = kAudioQueueTimePitchAlgorithm_Spectral;
//    AudioQueueSetProperty(audioQueue,
//                         kAudioQueueProperty_TimePitchAlgorithm,
//                         &timePitchAlgorithm,
//                         sizeof(timePitchAlgorithm));
//    
    if (status != noErr) {
        NSLog(@"Error creating AudioQueue: %d", (int)status);
        return;
    }
    
    // 为音频队列分配缓冲区
    for (int i = 0; i < numBuffers; i++) {
        status = AudioQueueAllocateBuffer(audioQueue, bufferSize, &audioQueueBuffer);
        if (status != noErr) {
            NSLog(@"Error allocating AudioQueueBuffer: %d", (int)status);
            return;
        }
        
        // 填充缓冲区并排队
        [self fillBuffer:audioQueueBuffer];
        status = AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffer, 0, NULL);
        if (status != noErr) {
            NSLog(@"Error enqueueing AudioQueueBuffer: %d", (int)status);
            return;
        }
    }
    
    // 开始播放
    status = AudioQueueStart(audioQueue, NULL);
    if (status != noErr) {
        NSLog(@"Error starting AudioQueue: %d", (int)status);
        return;
    }
}

- (void)fillBuffer:(AudioQueueBufferRef)buffer {
    // 从 PCM 文件中读取一帧数据
    size_t bytesRead = fread(buffer->mAudioData, 1, 320, pcmFile);
    
    // 如果文件结束，停止播放
    if (bytesRead == 0) {
        [self stopPlaying];
        return;
    }
    
    // 应用降噪处理
    NSData *pcmFrame = [NSData dataWithBytes:buffer->mAudioData length:bytesRead];
    [self applyDenoiseAlgorithm:pcmFrame compelete:^(id response) {
        NSData *denoisedData = response;
        // 将降噪后的数据复制到缓冲区
        memcpy(buffer->mAudioData, denoisedData.bytes, denoisedData.length);
        buffer->mAudioDataByteSize = (UInt32)denoisedData.length;
    }];
    
}
//- (void)fillBuffer:(AudioQueueBufferRef)buffer {
//    size_t bytesRead = fread(buffer->mAudioData, 1, bufferSize, pcmFile);
//    
//    if (bytesRead == 0) {
//        [self stopPlaying];
//        return;
//    }
//    
//    // 计算本缓冲区的持续时间（秒）
//    double duration = (double)bytesRead / (audioFormat.mBytesPerFrame * audioFormat.mSampleRate);
//    
//    // 显式设置时间戳
//    AudioTimeStamp timestamp;
//    memset(&timestamp, 0, sizeof(timestamp));
//    timestamp.mSampleTime = _currentFrame; // 当前帧位置
//    timestamp.mFlags = kAudioTimeStampSampleTimeValid;
//    
//    // 更新帧位置
//    _currentFrame += bytesRead / audioFormat.mBytesPerFrame;
//    
//    // 降噪处理（保持原逻辑）
//    NSData *pcmFrame = [NSData dataWithBytes:buffer->mAudioData length:bytesRead];
//    [self applyDenoiseAlgorithm:pcmFrame compelete:^(id response) {
//        NSData *denoisedData = response;
//        memcpy(buffer->mAudioData, denoisedData.bytes, denoisedData.length);
//        buffer->mAudioDataByteSize = (UInt32)denoisedData.length;
//        
//        // 带时间戳重新入队
//        AudioQueueEnqueueBufferWithParameters(self->audioQueue,
//                                            buffer,
//                                            0,
//                                            NULL,
//                                            0,
//                                            0,
//                                            0,
//                                            NULL,
//                                            &timestamp,
//                                            NULL);
//    }];
//}

- (void)applyDenoiseAlgorithm:(NSData *)pcmData compelete:(void(^)(id response))compelete{
    // 在这里实现你的降噪算法
    // 返回降噪后的 PCM 数据
    compelete(pcmData);
//    DLog(@"降噪");
//    [FfmpegNoiseTool denoisePCMData:pcmData compelete:^(id  _Nonnull response) {
//        DLog(@"降噪完成");
//        compelete(response);
//    }];
}


- (void)pausePlaying {
    OSStatus status = AudioQueuePause(audioQueue);
    _isManualPaused = YES; // 记录手动暂停
}
- (void)resume {
    AudioQueueStart(audioQueue, NULL);
    _isManualPaused = NO; // 清除暂停标志
}

- (void)stopPlaying {
    OSStatus status = AudioQueueStop(audioQueue, true);
    if (status != noErr) {
        NSLog(@"Error stopping AudioQueue: %d", (int)status);
    }
    
    status = AudioQueueDispose(audioQueue, true);
    if (status != noErr) {
        NSLog(@"Error disposing AudioQueue: %d", (int)status);
    }
    
    fclose(pcmFile);  // 关闭 PCM 文件
}
- (BOOL)isAudioQueuePlaying {
    if (audioQueue == NULL) return NO;
    
    // 1. 检查队列是否在运行状态
    UInt32 isRunning = 0;
    UInt32 size = sizeof(isRunning);
    AudioQueueGetProperty(audioQueue,
                        kAudioQueueProperty_IsRunning,
                        &isRunning,
                        &size);
    
    // 2. 结合手动暂停标志
    return (isRunning && !_isManualPaused);
}
@end

void audioQueueOutputCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer) {
    AudioPCMPlayer *player = (__bridge AudioPCMPlayer *)inUserData;
    
    // 填充新的数据并排队
    [player fillBuffer:inBuffer];
    
    OSStatus status = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    if (status != noErr) {
        NSLog(@"Error re-enqueueing AudioQueueBuffer: %d", (int)status);
    }
    
    // 1. 填充640字节数据（对应20ms）
//        size_t bytesRead = fread(inBuffer->mAudioData, 1, 640, player->pcmFile);
//        inBuffer->mAudioDataByteSize = (UInt32)bytesRead;
//        
//        // 2. 计算时间戳（从第0帧开始递增）
//        AudioTimeStamp timestamp = {0};
//        timestamp.mSampleTime = player->_currentFrame; // 当前帧位置
//        timestamp.mFlags = kAudioTimeStampSampleTimeValid;
//        player->_currentFrame += 320; // 每帧320样本
//        
//        // 3. 带时间戳入队
//        AudioQueueEnqueueBufferWithParameters(inAQ,
//                                           inBuffer,
//                                           0,
//                                           NULL,
//                                           0,
//                                           0,
//                                           0,
//                                           NULL,
//                                           &timestamp,
//                                           NULL);
}


