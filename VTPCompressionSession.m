#import "VTPCompressionSession.h"

#import "NSError+VTPError.h"


@interface VTPCompressionSession ()

@property (nonatomic, weak, readwrite) id<VTPCompressionSessionDelegate> delegate;
@property (nonatomic, strong, readwrite) dispatch_queue_t delegateQueue;

@property (nonatomic, assign) BOOL forceNextKeyframe;

@end


@implementation VTPCompressionSession

- (instancetype)initWithWidth:(NSInteger)width height:(NSInteger)height codec:(CMVideoCodecType)codec error:(NSError **)outError
{
	self = [super init];
	if(self != nil)
	{
		NSDictionary *encoderSpecification = @{ (__bridge NSString *)kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: @YES };

		OSStatus status = VTCompressionSessionCreate(NULL, (int32_t)width, (int32_t)height, codec, (__bridge CFDictionaryRef)encoderSpecification, NULL, NULL, VideoCompressonOutputCallback, (__bridge void *)self, &compressionSession);
		if(status != noErr)
		{
			NSError *error = [NSError videoToolboxErrorWithStatus:status];
			if(outError != nil)
			{
				*outError = error;
			}
			else
			{
				NSLog(@"%s:%d: %@", __FUNCTION__, __LINE__, error);
			}
			
			return nil;
		}
		
		self.forceNextKeyframe = YES;
	}
	return self;
}

- (void)dealloc
{
	if(compressionSession != NULL)
	{
		VTCompressionSessionInvalidate(compressionSession);
	}
}

- (void)setDelegate:(id<VTPCompressionSessionDelegate>)delegate queue:(dispatch_queue_t)queue
{
	if(queue == NULL)
	{
		queue = dispatch_get_main_queue();
	}
	
	self.delegate = delegate;
	self.delegateQueue = queue;
}

- (id)valueForProperty:(NSString *)property error:(NSError **)outError
{
	CFTypeRef value = NULL;
	OSStatus status = VTSessionCopyProperty(compressionSession, (__bridge CFStringRef)property, NULL, &value);
	if(status != noErr)
	{
		NSError *error = [NSError videoToolboxErrorWithStatus:status];
		if(outError != nil)
		{
			*outError = error;
		}
		else
		{
			NSLog(@"%s:%d: %@", __FUNCTION__, __LINE__, error);
		}
		
		return nil;
	}
	
	return CFBridgingRelease(value);
}

- (BOOL)setValue:(id)value forProperty:(NSString *)property error:(NSError **)outError
{
	OSStatus status = VTSessionSetProperty(compressionSession, (__bridge CFStringRef)property, (__bridge CFTypeRef)value);
	if(status != noErr)
	{
		NSError *error = [NSError videoToolboxErrorWithStatus:status];
		if(outError != nil)
		{
			*outError = error;
		}
		else
		{
			NSLog(@"%s:%d: %@", __FUNCTION__, __LINE__, error);
		}
		
		return NO;
	}

	return YES;
}

- (void)prepareToEncodeFrames
{
	VTCompressionSessionPrepareToEncodeFrames(compressionSession);

	self.forceNextKeyframe = YES;
}

- (BOOL)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer forceKeyframe:(BOOL)forceKeyframe
{
	CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	
	CMTime presentationTimeStamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
	CMTime duration = CMSampleBufferGetOutputDuration(sampleBuffer);
	
	return [self encodePixelBuffer:pixelBuffer presentationTimeStamp:presentationTimeStamp duration:duration forceKeyframe:forceKeyframe];
}

- (BOOL)encodePixelBuffer:(CVPixelBufferRef)pixelBuffer presentationTimeStamp:(CMTime)presentationTimeStamp duration:(CMTime)duration forceKeyframe:(BOOL)forceKeyframe
{
	NSDictionary *properties = nil;
	
	if(forceKeyframe || self.forceNextKeyframe)
	{
		properties = @{
			(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES
		};
		
		self.forceNextKeyframe = NO;
	}
	
	OSStatus status = VTCompressionSessionEncodeFrame(compressionSession, pixelBuffer, presentationTimeStamp, duration, (__bridge CFDictionaryRef)properties, pixelBuffer, NULL);
	
	return status == noErr;
}

- (void)encodePixelBufferCallbackWithSampleBuffer:(CMSampleBufferRef)sampleBuffer infoFlags:(VTEncodeInfoFlags)infoFlags
{
	id<VTPCompressionSessionDelegate> delegate = self.delegate;
	dispatch_queue_t delegateQueue = self.delegateQueue;
	
	if(infoFlags & kVTEncodeInfo_FrameDropped)
	{
		if([delegate respondsToSelector:@selector(compressionSession:didDropSampleBuffer:)])
		{
			CFRetain(sampleBuffer);
			dispatch_async(delegateQueue, ^{
				[delegate compressionSession:self didDropSampleBuffer:sampleBuffer];
				
				CFRelease(sampleBuffer);
			});
		}
	}
	else
	{
		if([delegate respondsToSelector:@selector(compressionSession:didEncodeSampleBuffer:)])
		{
			CFRetain(sampleBuffer);
			dispatch_async(delegateQueue, ^{
				[delegate compressionSession:self didEncodeSampleBuffer:sampleBuffer];
			
				CFRelease(sampleBuffer);
			});
		}
	}
}

static void VideoCompressonOutputCallback(void *VTref, void *VTFrameRef, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer)
{
	//	CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)VTFrameRef;
	//	CVPixelBufferRelease(pixelBuffer); // see encodeFrame:
	//	pixelBuffer = NULL;
	
	VTPCompressionSession *compressionSession = (__bridge VTPCompressionSession *)VTref;
	[compressionSession encodePixelBufferCallbackWithSampleBuffer:sampleBuffer infoFlags:infoFlags];
}

@end
