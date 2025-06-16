//
//  AudioQueuePlay 2.h
//  ActualDenoiseDemo
//
//  Created by 赵英杰 on 2025/6/14.
//


#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "WebRtcDenoiser.h"

NS_ASSUME_NONNULL_BEGIN

@protocol AudioQueuePlayDelegate <NSObject>
- (void)playEndAndShowScore;
- (void)audioPlayCompleted;

@end

@interface AudioQueuePlay : NSObject

@property (nonatomic, assign) BOOL isPlaying;
@property(nonatomic, weak) id<AudioQueuePlayDelegate> delegate;
@property(nonatomic,assign) VRWebrtcDenoiseLevel denoiseLevel;
@property(nonatomic,assign) NSTimeInterval duration;

- (void)playAudio:(NSString *)path withNum:(NSInteger)num;
- (void)stopAudio;
- (void)pause;
//返回时长
- (NSInteger)audioLength;
/**
 是否正在播放
 */
- (Boolean)isAudioPlaying;
/**
 继续播放
 */
- (void)play;
// 设置播放速率
- (void)play:(float)rate;
- (void)playAudio:(NSString *)path withNum:(NSInteger)num rate:(float)rate;
/**
 跳转
 */
- (void)seekTime:(float)seekTime;
/**
 获取当前播放的时间
 */
- (float)currentPlayTime;
// 设置降噪类型
- (void)setDenoiseLevel:(VRWebrtcDenoiseLevel)level;





@end

NS_ASSUME_NONNULL_END
