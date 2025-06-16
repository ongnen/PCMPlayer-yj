//
//  VoiceTool.m
//  ASRDemo
//
//  Created by majianghai on 2019/3/28.
//  Copyright © 2019 cmcm. All rights reserved.
//

#import "VoiceTool.h"
#import <AVFoundation/AVFoundation.h>
#include "noise_suppression.h"

#define VOICE_RATE 16000
#define VOICE_RATE_UNIT 160

//#define VOICE_RATE 8000
//#define VOICE_RATE_UNIT 80


#ifndef nullptr
#define nullptr 0
#endif

@interface VoiceTool ()


@end

@implementation VoiceTool






+ (int)voiceLength:(NSString *)filePath {
    

    NSURL *url = [NSURL fileURLWithPath:filePath];
    
    NSData *data = [NSData dataWithContentsOfURL:url];

    AVAudioPlayer* player = [[AVAudioPlayer alloc] initWithData:data error:nil];
    
    float duration = player.duration;

    float lengMs = duration * 1000;

    int len = lengMs / 10 * VOICE_RATE_UNIT;
    
    return len;
}


+ (int)denoise:(NSString *)filePath{
    
    NSData *sourceData = [NSData dataWithContentsOfFile:filePath];
    int16_t *buffer = (int16_t *)[sourceData bytes];
    
    
    uint32_t sampleRate = VOICE_RATE;
    int samplesCount = [VoiceTool voiceLength:filePath];
    int level = kVeryHigh;
    
    if (buffer == nullptr){
        NSLog(@"buffer为空");
    }
    if (samplesCount == 0) {
        NSLog(@"samplesCount为空");
    }
    size_t samples = MIN(VOICE_RATE_UNIT, sampleRate / 100);
    if (samples == 0) {
        NSLog(@"samples为空");
    }
    uint32_t num_bands = 1;
    int16_t *input = buffer;
    size_t nTotal = (samplesCount / samples);
    NsHandle *nsHandle = WebRtcNs_Create();
    int status = WebRtcNs_Init(nsHandle, sampleRate);
    if (status != 0) {
        printf("WebRtcNs_Init fail\n");
        return -1;
    }
    status = WebRtcNs_set_policy(nsHandle, level);
    if (status != 0) {
        printf("WebRtcNs_set_policy fail\n");
        return -1;
    }
    for (int i = 0; i < nTotal; i++) {
        int16_t *nsIn[1] = {input};   //ns input[band][data]
        int16_t *nsOut[1] = {input};  //ns output[band][data]
        WebRtcNs_Analyze(nsHandle, nsIn[0]);
        WebRtcNs_Process(nsHandle, (const int16_t *const *) nsIn, num_bands, nsOut);
        input += samples;
    }
    WebRtcNs_Free(nsHandle);
    
    NSData *data = [NSData dataWithBytes:buffer length:[sourceData length]];
    BOOL isWrite = [data writeToFile:filePath atomically:YES];
    if (isWrite) {
        NSLog(@"----写入成功");
    }
    
    return 1;
}



@end
