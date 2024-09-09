#import "I420Converter.h"
#import "SampleBufferVideoCallView.h"
#import <WebRTC/WebRTC.h>
#import <Accelerate/Accelerate.h>


@interface SampleBufferVideoCallView ()

@property (nonatomic, retain) I420Converter *i420Converter;
@property (nonatomic, assign) CVPixelBufferPoolRef pixelBufferPool;
@end

@implementation SampleBufferVideoCallView

+ (Class)layerClass {
    return [AVSampleBufferDisplayLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layerFailedToDecode:) name:AVSampleBufferDisplayLayerFailedToDecodeNotification object:self.sampleBufferLayer];
        [self createPixelBufferPool];
    }
    return self;
}

- (void)layerFailedToDecode:(NSNotification*)note
{
    NSError *error = [[note userInfo] valueForKey:AVSampleBufferDisplayLayerFailedToDecodeNotificationErrorKey];
    NSLog(@"layerFailedToDecode, error: %@", [error localizedDescription]);
}

- (AVSampleBufferDisplayLayer *)sampleBufferLayer {
    return (AVSampleBufferDisplayLayer *)self.layer;
}

/** The size of the video frame. */
- (void)setSize : (CGSize)size{
    
}

- (void)createPixelBufferPool {
    NSDictionary *pixelBufferAttributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey: @(1000),
        (id)kCVPixelBufferHeightKey: @(1000),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    
    CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)pixelBufferAttributes, &_pixelBufferPool);
}

/** The frame to be displayed. */
- (void)renderFrame:(nullable RTC_OBJC_TYPE(RTCVideoFrame) *)frame {

    // Convert RTCVideoFrame to CMSampleBuffer
    CMSampleBufferRef sampleBuffer = [self sampleBufferFrom:frame];
    if (sampleBuffer == nil) {
        return;
    }

    // TODO: handle overflows
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.sampleBufferLayer.readyForMoreMediaData) {
            return;
        }

        // Display the CMSampleBuffer using AVSampleBufferDisplayLayer
        [self.sampleBufferLayer enqueueSampleBuffer:sampleBuffer];
        CFRelease(sampleBuffer);
    });
}

- (CMSampleBufferRef)sampleBufferFrom:(RTCVideoFrame *)rtcVideoFrame {
    // Convert RTCVideoFrame to CMSampleBuffer
    
    // Assuming your RTCVideoFrame contains pixelBuffer
    CVPixelBufferRef pixelBuffer = [self pixelBufferFrom:rtcVideoFrame];
    if (!pixelBuffer) {
        return nil;
    }
    
    // Create a CMVideoFormatDescription
    CMVideoFormatDescriptionRef formatDescription;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDescription);
    
    // Create CMSampleTimingInfo
    // Timescale is 90khz according to RTCVideoFrame.h
    CMSampleTimingInfo timingInfo;
    timingInfo.presentationTimeStamp = CMTimeMake(rtcVideoFrame.timeStamp, 90000);
    timingInfo.decodeTimeStamp = CMTimeMake(rtcVideoFrame.timeStamp, 90000);
    
    // TODO: handle rotations
    // Create CMSampleBuffer
    CMSampleBufferRef sampleBuffer;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, nil, nil, formatDescription, &timingInfo, &sampleBuffer);
    
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);

    CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    
    CVPixelBufferRelease(pixelBuffer); // Release the pixel buffer back to the pool
    
    return sampleBuffer;
}


-(CVPixelBufferRef)pixelBufferFrom:(RTCVideoFrame *)videoFrame {
    if ([videoFrame.buffer isKindOfClass:[RTCCVPixelBuffer class]]) {
        return [((RTCCVPixelBuffer *) videoFrame.buffer) pixelBuffer];
    } else {
        return [self pixelBufferFromI420:[videoFrame.buffer toI420]];
    }
}


-(CVPixelBufferRef)pixelBufferFromI420:(RTCI420Buffer *)i420Buffer {
    if (_i420Converter == nil) {
        I420Converter * converter = [[I420Converter alloc] init];
        vImage_Error err = [converter prepareForAccelerateConversion];
        
        if(err != kvImageNoError) {
            NSLog(@"Error when preparing i420Converter: %ld", err);
            return NULL;
        }
        
        _i420Converter = converter;
    }
    
    if (_pixelBufferPool == NULL) {
        [self createPixelBufferPool];
    }
    
    CVPixelBufferRef pixelBuffer;
    CVReturn status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pixelBufferPool, &pixelBuffer);
    
    if (status != kCVReturnSuccess) {
        NSLog(@"Error creating pixel buffer from pool: %d", status);
        return NULL;
    }
    
    CVPixelBufferRef convertedPixelBuffer = [_i420Converter convertI420ToPixelBuffer:i420Buffer];
    CVPixelBufferRelease(pixelBuffer); // Release the pixel buffer back to the pool
    
    return convertedPixelBuffer;
}

-(void)dealloc {
    [_i420Converter unprepareForAccelerateConversion];
}

@end

