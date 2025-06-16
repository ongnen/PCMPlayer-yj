//
//  AudioQueuePlay.h
//  ActualDenoiseDemo
//
//  Created by 赵英杰 on 2025/6/14.
//


#import "AudioQueuePlay.h"
#import "WebRtcDenoiser.h"

#define MIN_SIZE_PER_FRAME 8192  // 根据一帧音频的实际大小确定
#define QUEUE_BUFFER_SIZE 3      // 音频缓冲个数
#define CHECK_SIZE 640      // PCM单帧读取大小

@interface AudioQueuePlay() {
    
    AudioQueueRef audioQueue;                                 //音频播放队列
    AudioStreamBasicDescription _audioDescription;            //音频播放上下文
    AudioQueueBufferRef audioQueueBuffers[QUEUE_BUFFER_SIZE]; //音频缓存
    BOOL bufferCanByPlay[QUEUE_BUFFER_SIZE];                  //判断缓存的音频是否可以播放
    int pauseCount;
    SInt64 currentPacket;
}

@property(nonatomic,strong) NSString *filePath;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@property(nonatomic,strong) WebRtcDenoiser *webRtcDenoiser;

@property(nonatomic,assign) float currentRate;

@end

@implementation AudioQueuePlay

- (instancetype)init
{
    self = [super init];
    if (self) {
        // 播放PCM使用
        if (_audioDescription.mSampleRate <= 0) {
            //设置音频参数
            _audioDescription.mSampleRate = 16000;//采样率
            _audioDescription.mFormatID = kAudioFormatLinearPCM;
            // 下面这个是保存音频数据的方式的说明，如可以根据大端字节序或小端字节序，浮点数或整数以及不同体位去保存数据
            _audioDescription.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
            //1单声道 2双声道
            _audioDescription.mChannelsPerFrame = 1;
            //每一个packet一侦数据,每个数据包下的桢数，即每个数据包里面有多少桢
            _audioDescription.mFramesPerPacket = 1;
            //每个采样点16bit量化 语音每采样点占用位数
            _audioDescription.mBitsPerChannel = 16;
            _audioDescription.mBytesPerFrame = (_audioDescription.mBitsPerChannel / 8) * _audioDescription.mChannelsPerFrame;
            //每个数据包的bytes总数，每桢的bytes数*每个数据包的桢数
            _audioDescription.mBytesPerPacket = _audioDescription.mBytesPerFrame * _audioDescription.mFramesPerPacket;
        }
        
        // 使用player的内部线程播放 新建输出
        // 注册时保留 self
        void *context = (__bridge_retained void *)self;
        AudioQueueNewOutput(&_audioDescription, AudioQueueBufferDone, context, NULL, 0, 0, &audioQueue);
        // 2. 设置播放速率（范围通常为 0.5 ~ 2.0）
        Float32 playbackRate = 1.0f; // 1.5倍速
        OSStatus status = AudioQueueSetParameter(
            audioQueue,
            kAudioQueueParam_PlayRate, // 正确的参数标识符
            playbackRate
        );
        UInt32 enableTimePitch = 1; // 1=启用
        AudioQueueSetProperty(
            audioQueue,
            kAudioQueueProperty_EnableTimePitch,
            &enableTimePitch,
            sizeof(enableTimePitch)
        );
        UInt32 algorithm = kAudioQueueTimePitchAlgorithm_Spectral; // 高质量
        AudioQueueSetProperty(
            audioQueue,
            kAudioQueueProperty_TimePitchAlgorithm,
            &algorithm,
            sizeof(algorithm)
        );

        if (status != noErr) {
            NSLog(@"设置播放速率失败: %d", (int)status);
        }

        // 设置音量
//        AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1.0);
        
        // 初始化需要的缓冲区及使用标记
        OSStatus osState;
        for (int i = 0; i < QUEUE_BUFFER_SIZE; i++) {
            // 创建buffer
            osState = AudioQueueAllocateBuffer(audioQueue, MIN_SIZE_PER_FRAME, &audioQueueBuffers[i]);
            // 此时未填充数据，标记为不能播放
            bufferCanByPlay[i] = NO;
            printf("第 %d 个AudioQueueAllocateBuffer 初始化结果 %d (0表示成功)\n", i + 1, osState);
        }
        [self initialConfig];
    }
    return self;
}

// ************************** 回调 **********************************

// 回调回来把buffer状态设为未使用
static void AudioQueueBufferDone(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer) {
    AudioQueuePlay *player = (__bridge AudioQueuePlay *)inUserData;
    [player resetAudioQueueBuffer:inAQ and:inBuffer];
}

// 重置播放完毕的buffer
- (void)resetAudioQueueBuffer:(AudioQueueRef)audioQueueRef and:(AudioQueueBufferRef)audioQueueBufferRef {
    // 查找当前播放完毕的buffer位置
    int oldIndex = -1;
    for (int i = 0; i < QUEUE_BUFFER_SIZE; i++) {
        if (audioQueueBuffers[i] == audioQueueBufferRef) {
            oldIndex = i;
            break;
        }
    }
    // 获取新数据
    NSData *data = [self getAudioData];
    if (data == nil) {
        // 新数据获取失败，将buffer标记为不能播放
        bufferCanByPlay[oldIndex] = NO;
        // 已暂停buffer数量+1
        pauseCount += 1;
        // 如已暂停buffer数量达到缓冲大小，此时通知用户暂停播放
        if (pauseCount > QUEUE_BUFFER_SIZE-1) {
            [self.delegate playEndAndShowScore];
        }
        return;
    }
    // 获取新数据成功
    NSMutableData *tempData = [NSMutableData new];
    [tempData appendData: data];
    // 将新数据更新到播放完毕的buffer中
    NSUInteger len = tempData.length;
    Byte *bytes = (Byte*)malloc(len);
    [tempData getBytes:bytes length: len];
    bufferCanByPlay[oldIndex] = YES;
    audioQueueBuffers[oldIndex] -> mAudioDataByteSize = (unsigned int)len;
    memcpy(audioQueueBuffers[oldIndex] -> mAudioData, bytes, len);
    free(bytes);
    AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffers[oldIndex], 0, NULL);
    NSLog(@"已更新音频数据：%d", oldIndex);
}
/*
 启动音频播放机
 注意：音频播放之前，请保持充足的音频缓存，在暂停之前不能重复调用start
 */
- (void)start{
    // 将暂停数量标记为0，暂停数量表示
    pauseCount = 0;
    // 填充已创建的buffer，并压入播放队列
    for (int i = 0; i < QUEUE_BUFFER_SIZE; i++) {
        NSData *data = [self getAudioData];
        if (data == nil) {
            break;
        }
        NSMutableData *tempData = [NSMutableData new];
        [tempData appendData: data];
        // 得到数据
        NSUInteger len = tempData.length;
        Byte *bytes = (Byte*)malloc(len);
        [tempData getBytes:bytes length: len];
        bufferCanByPlay[i] = YES; // 标记为使用
        audioQueueBuffers[i] -> mAudioDataByteSize = (unsigned int)len;
        memcpy(audioQueueBuffers[i] -> mAudioData, bytes, len);
        free(bytes);
        AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffers[i], 0, NULL);
    }
    // 启动播放队列
    OSStatus osState = AudioQueueStart(audioQueue, NULL);
    if (osState != noErr) {
        printf("AudioQueueStart Error");
    }
}


- (void)stop {
    [self stopAudio];
    // 若要将内存处理的更干净，可以继续处理 audioQueueBuffers中的data，我这里最大只有24k的数据量，必要性不强
}


- (void)clearAudioQueueBuffers {
    for (int i = 0; i < QUEUE_BUFFER_SIZE; i++) {
        AudioQueueFreeBuffer(audioQueue, audioQueueBuffers[i]); // 清空缓存
        audioQueueBuffers[i] = NULL; // 清空指针
    }
}

- (void)initialConfig{
    self.isPlaying = NO;
    self.currentRate = 1.0;
    self.webRtcDenoiser = [[WebRtcDenoiser alloc] initWithSampleRate:16000];
}

#pragma mark ———————————————————————播放控制-接口适配
- (void)playAudio:(NSString *)path withNum:(NSInteger)num{
    [self playAudio:path rate:1.0];
}
- (void)playAudio:(NSString *)path withNum:(NSInteger)num rate:(float)rate{
    [self playAudio:path rate:rate];
}
// 从头开始播放
- (void)playAudio:(NSString *)path rate:(float)rate{
    // 初始化资源，句柄,文件时长
    self.filePath = path;
    self.duration = [self getPCMDurationWithPath:self.filePath];
    self.fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.filePath];
    
    // 清理上下文
    [self stop];
    // 开始播放
    [self play];
}
// 结束播放
- (void)stopAudio{
    self.isPlaying = NO;
    AudioQueueReset(audioQueue);
    bufferCanByPlay[0] = NO;
    bufferCanByPlay[1] = NO;
    bufferCanByPlay[2] = NO;
    printf("音频队列已重置\n");
}
// 暂停
- (void)pause{
    self.isPlaying = NO;
    AudioQueuePause(audioQueue);
}
// 返回时长
- (NSInteger)audioLength{
    return (NSInteger)self.duration;
}
/**
 是否正在播放
 */
- (Boolean)isAudioPlaying{
    return YES;
}
- (void)play{
    self.isPlaying = YES;
    if (bufferCanByPlay[0] == NO && bufferCanByPlay[1] == NO && bufferCanByPlay[2] == NO) {
        [self start];
    }else {
        AudioQueueStart(audioQueue, NULL);
    }
}
// 设置播放速率
- (void)play:(float)rate{
    // 2. 设置播放速率（范围通常为 0.5 ~ 2.0）
    Float32 playbackRate = rate; // 1.5倍速
    OSStatus status = AudioQueueSetParameter(
        audioQueue,
        kAudioQueueParam_PlayRate, // 正确的参数标识符
        playbackRate
    );
}
/**
 跳转
 */
- (void)seekTime:(float)seekTime{
    long long byteOffset = (int)seekTime * 16000 * 1 * (16 / 8);
    [_fileHandle seekToFileOffset:byteOffset]; // 跳转文件位置
    if (self.isPlaying) {
        [self stop];
        [self play];
    } else {
        [self stop];
    }
}
/**
 获取当前播放的时间
 */
- (float)currentPlayTime{
    unsigned long long currentOffset = [_fileHandle offsetInFile];
    const UInt32 sampleRate = 16000;
    const UInt32 bitsPerChannel = 16;
    const UInt32 channels = 1;
    
    NSTimeInterval offsetTime = (double)currentOffset / (sampleRate * (bitsPerChannel / 8) * channels);
    return offsetTime;
}

// 设置降噪类型
- (void)setDenoiseLevel:(VRWebrtcDenoiseLevel)level{
    _denoiseLevel = level;
    [self.webRtcDenoiser setDenoiseLevel:level];
}



#pragma mark ———————————————————————降噪相关入口
- (NSData *)getAudioData {
    if (!self.fileHandle) return nil;
    
    @try {
        // 从当前偏移量读取指定大小的数据
        NSData *chunk = [self.fileHandle readDataOfLength:CHECK_SIZE];
        
        // 如果读取到空数据，说明已到文件末尾
        if (chunk.length == 0) {
            [self.fileHandle closeFile];
            self.fileHandle = nil;
            return nil;
        }
        if (self.denoiseLevel == VRWebrtcDenoiseLevelNone) {
            return chunk;
        } else {
            [self.webRtcDenoiser setDenoiseLevel:self.denoiseLevel];
            NSData *denoiseData = [self.webRtcDenoiser processFrame:chunk];
            return denoiseData;
        }
    } @catch (NSException *exception) {
        NSLog(@"读取音频数据失败: %@", exception);
        [self.fileHandle closeFile];
        self.fileHandle = nil;
        return nil;
    }
}




#pragma mark ———————————————————————其他工具函数
/**
 * 获取 PCM 文件时长（固定格式：16kHz 16位 单声道）
 * @param filePath PCM 文件路径
 * @return 音频时长（秒），失败返回 -1.0
 */
- (NSTimeInterval)getPCMDurationWithPath:(NSString *)filePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // 1. 检查文件是否存在
    if (![fileManager fileExistsAtPath:filePath]) {
        NSLog(@"PCM 文件不存在");
        return -1.0;
    }
    
    // 2. 获取文件大小（字节）
    NSError *error = nil;
    NSDictionary *fileAttrs = [fileManager attributesOfItemAtPath:filePath error:&error];
    if (error) {
        NSLog(@"获取文件大小失败: %@", error.localizedDescription);
        return -1.0;
    }
    
    UInt64 fileSize = [fileAttrs[NSFileSize] unsignedLongLongValue];
    
    // 3. 计算时长（固定格式：16kHz 16位 单声道）
    const UInt32 sampleRate = 16000;
    const UInt32 bitsPerChannel = 16;
    const UInt32 channels = 1;
    
    NSTimeInterval duration = (double)fileSize / (sampleRate * (bitsPerChannel / 8) * channels);
    
    return duration;
}

@end
