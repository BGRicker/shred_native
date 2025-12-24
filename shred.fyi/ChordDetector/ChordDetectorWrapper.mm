#import "ChordDetectorWrapper.h"
#import "ChordDetector.h"
#import "Chromagram.h"

@interface ChordDetectorWrapper ()
@end

@implementation ChordDetectorWrapper {
    ChordDetector detector_;
    Chromagram *chromagram_;
    int frameSize_;
}

- (instancetype)initWithFrameSize:(NSInteger)frameSize sampleRate:(double)sampleRate {
    self = [super init];
    if (self) {
        frameSize_ = (int)frameSize;
        chromagram_ = new Chromagram(frameSize_, (int)sampleRate);
        chromagram_->setInputAudioFrameSize(frameSize_);
        chromagram_->setSamplingFrequency((int)sampleRate);
        chromagram_->setChromaCalculationInterval(frameSize_);
    }
    return self;
}

- (void)dealloc {
    delete chromagram_;
    chromagram_ = nullptr;
}

- (nullable NSDictionary<NSString *, NSNumber *> *)detectChordWithAudioFrame:(NSArray<NSNumber *> *)frame {
    if (!chromagram_) {
        return nil;
    }

    std::vector<double> audioFrame;
    audioFrame.reserve(frameSize_);
    double sumSquares = 0.0;
    for (NSNumber *value in frame) {
        double sample = value.doubleValue;
        audioFrame.push_back(sample);
        sumSquares += sample * sample;
    }
    if ((int)audioFrame.size() < frameSize_) {
        audioFrame.resize(frameSize_, 0.0);
    }

    double rms = sqrt(sumSquares / (double)frameSize_);
    if (rms < 0.01) {
        return nil;
    }

    chromagram_->processAudioFrame(audioFrame);
    if (!chromagram_->isReady()) {
        return nil;
    }

    std::vector<double> chroma = chromagram_->getChromagram();
    detector_.detectChord(chroma);

    double maxValue = 0.0;
    double sum = 0.0;
    for (double value : chroma) {
        if (value > maxValue) {
            maxValue = value;
        }
        sum += value;
    }
    if (sum <= 0.0) {
        return nil;
    }
    double confidence = maxValue / sum;
    double scaledConfidence = pow(confidence, 0.5);

    return @{
        @"rootNote": @(detector_.rootNote),
        @"quality": @(detector_.quality),
        @"intervals": @(detector_.intervals),
        @"confidence": @(scaledConfidence)
    };
}

@end
