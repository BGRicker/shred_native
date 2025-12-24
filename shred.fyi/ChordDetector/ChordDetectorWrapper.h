#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ChordDetectorWrapper : NSObject

- (instancetype)initWithFrameSize:(NSInteger)frameSize sampleRate:(double)sampleRate;
- (nullable NSDictionary<NSString *, NSNumber *> *)detectChordWithAudioFrame:(NSArray<NSNumber *> *)frame;

@end

NS_ASSUME_NONNULL_END
