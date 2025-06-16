//
//  VoiceTool.h
//  ASRDemo
//
//  Created by majianghai on 2019/3/28.
//  Copyright © 2019 cmcm. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

enum nsLevel {
    kLow,
    kModerate,
    kHigh,
    kVeryHigh
};


@interface VoiceTool : NSObject


/// 降噪方法
+ (int)denoise:(NSString *)filePath;

@end

NS_ASSUME_NONNULL_END
