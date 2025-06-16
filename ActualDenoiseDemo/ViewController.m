//
//  ViewController.m
//  ActualDenoiseDemo
//
//  Created by 赵英杰 on 2025/6/14.
//

#import "ViewController.h"
#import "AudioQueuePlay.h"
#import <AVFoundation/AVFoundation.h>
#include "noise_suppression.h"
#import "VoiceTool.h"
#import "WebRtcDenoiser.h"

#define VR_SCREEN_WIDTH ([UIScreen mainScreen].bounds.size.width)
#define VR_SCREEN_HEIGHT ([UIScreen mainScreen].bounds.size.height)

@interface ViewController ()<AudioQueuePlayDelegate>
{
    FILE *_pcmFile;
    BOOL _fileEnded;
}

@property(nonatomic,strong) WebRtcDenoiser *webRtcDenoiser;
@property(nonatomic,strong) AudioQueuePlay *player;
@property(nonatomic,strong) dispatch_source_t sliderTimer;

@property(nonatomic,weak) UISlider *sliderV;
@property(nonatomic,assign) BOOL sliderSuspend;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.sliderSuspend = NO;
    self.view.backgroundColor = [UIColor whiteColor];
    // 在 startPlaying 方法开头添加
    NSError *error;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    [[AVAudioSession sharedInstance] setPreferredIOBufferDuration:0.02 error:&error]; // 20ms
    [[AVAudioSession sharedInstance] setActive:YES error:&error];

    
    self.player = [[AudioQueuePlay alloc] init];
//    self.player.delegate = self;
    [self initialUI];
    
    [self setSliderTimer];
}



- (void)initialUI{
    UIButton *playBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [playBtn setTitle:@"播放" forState:UIControlStateNormal];
    [playBtn setBackgroundColor:[UIColor redColor]];
    playBtn.frame = CGRectMake(100, 100, 50, 50);
    [playBtn addTarget:self action:@selector(play) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:playBtn];
    
    
    UIButton *pauseBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [pauseBtn setTitle:@"暂停" forState:UIControlStateNormal];
    [pauseBtn setBackgroundColor:[UIColor redColor]];
    pauseBtn.frame = CGRectMake(170, 100, 50, 50);
    [pauseBtn addTarget:self action:@selector(pause) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:pauseBtn];
    
    UIButton *resumeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [resumeBtn setTitle:@"恢复" forState:UIControlStateNormal];
    [resumeBtn setBackgroundColor:[UIColor redColor]];
    resumeBtn.frame = CGRectMake(170, 170, 50, 50);
    [resumeBtn addTarget:self action:@selector(resume) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:resumeBtn];
    
    
    UIButton *originBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [originBtn setTitle:@"原声" forState:UIControlStateNormal];
    [originBtn setBackgroundColor:[UIColor redColor]];
    originBtn.frame = CGRectMake(250, 100, 50, 50);
    [originBtn addTarget:self action:@selector(setOrigin) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:originBtn];
    
    
    UIButton *denoiseBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [denoiseBtn setTitle:@"降噪" forState:UIControlStateNormal];
    [denoiseBtn setBackgroundColor:[UIColor redColor]];
    denoiseBtn.frame = CGRectMake(320, 100, 50, 50);
    [denoiseBtn addTarget:self action:@selector(setDenoise) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:denoiseBtn];
    
    UISlider *sliderV = [[UISlider alloc] initWithFrame:CGRectMake(20, 300, VR_SCREEN_WIDTH-40, 30)];
    self.sliderV = sliderV;
    sliderV.continuous = NO;
    [sliderV setValue:0.0];
    [sliderV addTarget:self action:@selector(seekProcess:) forControlEvents:UIControlEventValueChanged];
    [sliderV addTarget:self action:@selector(seekTouch) forControlEvents:UIControlEventTouchDragInside];
    [self.view addSubview:sliderV];
}

- (void)setSliderTimer{
    dispatch_source_t sliderTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(0, 0));
    self.sliderTimer = sliderTimer;
    dispatch_source_set_timer(sliderTimer, DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC); // 允许0.1秒误差
    // 设置回调
    dispatch_source_set_event_handler(sliderTimer, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.sliderSuspend) {
                self.sliderV.value = [self.player currentPlayTime]/self.player.duration;
            }
        });
    });
    dispatch_resume(sliderTimer);
}

// 播放
- (void)play{
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"20250614_203038.pcm" ofType:nil];
    [self.player playAudio:filePath withNum:0];
}
// 暂停
- (void)pause{
    [self.player pause];
}
- (void)resume{
    [self.player play];
}
// 原声
- (void)setOrigin{
    [self.player setDenoiseLevel:VRWebrtcDenoiseLevelNone];
}
// 降噪
- (void)setDenoise{
    [self.player setDenoiseLevel:VRWebrtcDenoiseLevel2];
}
// 拖动进度条
- (void)seekProcess:(UISlider *)slider{
    float seekTimeInSeconds = slider.value * self.player.duration;
    [self.player seekTime:seekTimeInSeconds];
    self.sliderSuspend = NO;
}
- (void)seekTouch{
    self.sliderSuspend = YES;
}


- (void)audioNeedPaused{
    [self.player stopAudio];
}



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
