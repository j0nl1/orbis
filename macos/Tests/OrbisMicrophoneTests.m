/* SPDX-License-Identifier: MIT */
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <freerdp/freerdp.h>
#include <assert.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static AVAuthorizationStatus authorization;
static NSUInteger permissionRequests, authorizationQueries;
static NSUInteger queueCreations, queueStarts, queueStops, queueDisposals;

@interface OrbisMicrophoneAuthorizationFixture : NSObject
+ (AVAuthorizationStatus)authorizationStatusForMediaType:(AVMediaType)type;
+ (void)requestAccessForMediaType:(AVMediaType)type completionHandler:(void (^)(BOOL))handler;
@end

@implementation OrbisMicrophoneAuthorizationFixture
+ (AVAuthorizationStatus)authorizationStatusForMediaType:(AVMediaType)type
{
	(void)type;
	authorizationQueries++;
	return authorization;
}
+ (void)requestAccessForMediaType:(AVMediaType)type completionHandler:(void (^)(BOOL))handler
{
	(void)type;
	(void)handler;
	permissionRequests++;
}
@end

typedef struct
{
	AudioQueueInputCallback callback;
	void *context;
	AudioQueueBufferRef buffers[100];
	size_t count;
} MicrophoneQueueFixture;

static OSStatus FixtureQueueNewInput(const AudioStreamBasicDescription *format,
    AudioQueueInputCallback callback, void *context, CFRunLoopRef loop,
    CFStringRef mode, UInt32 flags, AudioQueueRef *result)
{
	(void)format; (void)loop; (void)mode; (void)flags;
	MicrophoneQueueFixture *queue = calloc(1, sizeof(*queue));
	assert(queue);
	queue->callback = callback;
	queue->context = context;
	*result = (AudioQueueRef)queue;
	queueCreations++;
	return noErr;
}

static OSStatus FixtureQueueAllocateBuffer(AudioQueueRef audioQueue, UInt32 size,
    AudioQueueBufferRef *result)
{
	MicrophoneQueueFixture *queue = (MicrophoneQueueFixture *)audioQueue;
	assert(queue->count < 100);
	AudioQueueBuffer buffer = { .mAudioDataBytesCapacity = size, .mAudioData = calloc(1, size) };
	*result = malloc(sizeof(buffer));
	assert(*result && buffer.mAudioData);
	memcpy(*result, &buffer, sizeof(buffer));
	queue->buffers[queue->count++] = *result;
	return noErr;
}

static OSStatus FixtureQueueEnqueueBuffer(AudioQueueRef queue, AudioQueueBufferRef buffer,
    UInt32 count, const AudioStreamPacketDescription *descriptions)
{
	(void)queue; (void)buffer; (void)count; (void)descriptions;
	return noErr;
}

static OSStatus FixtureQueueStart(AudioQueueRef queue, const AudioTimeStamp *time)
{
	(void)queue; (void)time;
	queueStarts++;
	return noErr;
}

static void DeliverSamples(AudioQueueRef audioQueue)
{
	MicrophoneQueueFixture *queue = (MicrophoneQueueFixture *)audioQueue;
	AudioQueueBufferRef buffer = queue->buffers[0];
	buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
	memset(buffer->mAudioData, 0x33, buffer->mAudioDataByteSize);
	AudioTimeStamp time = { 0 };
	queue->callback(queue->context, audioQueue, buffer, &time, 0, NULL);
}

static OSStatus FixtureQueueStop(AudioQueueRef queue, Boolean immediate)
{
	assert(immediate);
	/* Draining a pending callback must neither deadlock nor forward captured samples. */
	DeliverSamples(queue);
	queueStops++;
	return noErr;
}

static OSStatus FixtureQueueDispose(AudioQueueRef audioQueue, Boolean immediate)
{
	assert(immediate);
	MicrophoneQueueFixture *queue = (MicrophoneQueueFixture *)audioQueue;
	for (size_t i = 0; i < queue->count; i++)
	{
		free(queue->buffers[i]->mAudioData);
		free(queue->buffers[i]);
	}
	free(queue);
	queueDisposals++;
	return noErr;
}

/* Run the patched backend with deterministic permission and hardware adapters. */
#define AVCaptureDevice OrbisMicrophoneAuthorizationFixture
#define AudioQueueNewInput FixtureQueueNewInput
#define AudioQueueAllocateBuffer FixtureQueueAllocateBuffer
#define AudioQueueEnqueueBuffer FixtureQueueEnqueueBuffer
#define AudioQueueStart FixtureQueueStart
#define AudioQueueStop FixtureQueueStop
#define AudioQueueDispose FixtureQueueDispose
#include "audin_mac.m"
#undef AVCaptureDevice
#undef AudioQueueNewInput
#undef AudioQueueAllocateBuffer
#undef AudioQueueEnqueueBuffer
#undef AudioQueueStart
#undef AudioQueueStop
#undef AudioQueueDispose

static IAudinDevice *microphone;
static UINT RegisterMicrophone(IWTSPlugin *plugin, IAudinDevice *device)
{
	(void)plugin;
	microphone = device;
	return CHANNEL_RC_OK;
}

static IAudinDevice *CreateMicrophone(rdpContext *context)
{
	char name[] = "audin";
	char *argv[] = { name };
	ADDIN_ARGV args = { .argc = 1, .argv = argv };
	FREERDP_AUDIN_DEVICE_ENTRY_POINTS points = {
		.pRegisterAudinDevice = RegisterMicrophone, .args = &args, .rdpcontext = context
	};
	microphone = NULL;
	assert(mac_freerdp_audin_client_subsystem_entry(&points) == CHANNEL_RC_OK);
	assert(microphone);
	return microphone;
}

static AUDIO_FORMAT MicrophoneFormat(void)
{
	AUDIO_FORMAT format = { .wFormatTag = WAVE_FORMAT_PCM, .nChannels = 1,
		.nSamplesPerSec = 48000, .nAvgBytesPerSec = 96000,
		.nBlockAlign = 2, .wBitsPerSample = 16 };
	return format;
}

static UINT ReceiveSamples(const AUDIO_FORMAT *format, const BYTE *data, size_t size, void *userData)
{
	assert(format->nChannels == 1 && size > 0 && data[0] == 0x33);
	(*(NSUInteger *)userData)++;
	return CHANNEL_RC_OK;
}

static void CheckPermissionAndFormats(void)
{
	const AVAuthorizationStatus statuses[] = { AVAuthorizationStatusAuthorized,
		AVAuthorizationStatusDenied, AVAuthorizationStatusRestricted, AVAuthorizationStatusNotDetermined };
	for (size_t i = 0; i < sizeof(statuses) / sizeof(statuses[0]); i++)
	{
		authorization = statuses[i];
		rdpContext context = { 0 };
		IAudinDevice *device = CreateMicrophone(&context);
		NSUInteger queries = authorizationQueries, creations = queueCreations;
		AUDIO_FORMAT format = MicrophoneFormat();
		assert(device->FormatSupported(device, &format));
		assert(device->SetFormat(device, &format, 480) == CHANNEL_RC_OK);
		format.nChannels = 2;
		assert(device->FormatSupported(device, &format));
		assert(device->SetFormat(device, &format, 480) == CHANNEL_RC_OK);
		format.nChannels = 3;
		assert(!device->FormatSupported(device, &format));
		assert(device->SetFormat(device, &format, 480) != CHANNEL_RC_OK);
		format.nChannels = 1;
		format.wBitsPerSample = 8;
		assert(!device->FormatSupported(device, &format));
		format.wBitsPerSample = 16;
		format.nSamplesPerSec = 0;
		assert(!device->FormatSupported(device, &format));
		format = MicrophoneFormat();
		assert(device->SetFormat(device, &format, 0) != CHANNEL_RC_OK);
		assert(device->SetFormat(device, &format, UINT32_MAX) != CHANNEL_RC_OK);
		assert(!device->FormatSupported(device, NULL));
		assert(device->SetFormat(device, &format, 480) == CHANNEL_RC_OK);
		NSUInteger received = 0;
		assert(device->Open(device, ReceiveSamples, &received) == CHANNEL_RC_OK);
		assert(authorizationQueries == queries && queueCreations == creations && received == 0);
		assert(permissionRequests == 0);
		UINT result = orbis_audin_set_enabled(&context, TRUE);
		if (authorization == AVAuthorizationStatusAuthorized)
		{
			assert(result == CHANNEL_RC_OK && queueCreations == creations + 1);
			DeliverSamples(((AudinMacDevice *)device)->audioQueue);
			assert(received == 1);
		}
		else
			assert(result == ERROR_ACCESS_DENIED && queueCreations == creations);
		assert(orbis_audin_set_enabled(&context, FALSE) == CHANNEL_RC_OK);
		assert(received == (authorization == AVAuthorizationStatusAuthorized ? 1 : 0));
		assert(device->Close(device) == CHANNEL_RC_OK);
		assert(device->Free(device) == CHANNEL_RC_OK);
		orbis_audin_remove_context(&context);
	}
	assert(!audinControls);
}

static void CheckLiveToggleAndContextIsolation(void)
{
	authorization = AVAuthorizationStatusAuthorized;
	rdpContext contexts[2] = { 0 };
	assert(orbis_audin_set_enabled(&contexts[0], TRUE) == CHANNEL_RC_OK);
	IAudinDevice *devices[] = { CreateMicrophone(&contexts[0]), CreateMicrophone(&contexts[1]) };
	NSUInteger received[2] = { 0 };
	AUDIO_FORMAT format = MicrophoneFormat();
	for (size_t i = 0; i < 2; i++)
	{
		assert(devices[i]->SetFormat(devices[i], &format, 480) == CHANNEL_RC_OK);
		assert(devices[i]->Open(devices[i], ReceiveSamples, &received[i]) == CHANNEL_RC_OK);
	}
	assert(((AudinMacDevice *)devices[0])->isOpen && !((AudinMacDevice *)devices[1])->isOpen);
	DeliverSamples(((AudinMacDevice *)devices[0])->audioQueue);
	assert(orbis_audin_set_enabled(&contexts[1], TRUE) == CHANNEL_RC_OK);
	DeliverSamples(((AudinMacDevice *)devices[1])->audioQueue);
	assert(received[0] == 1 && received[1] == 1);
	assert(orbis_audin_set_enabled(&contexts[0], FALSE) == CHANNEL_RC_OK);
	assert(!((AudinMacDevice *)devices[0])->isOpen && ((AudinMacDevice *)devices[1])->isOpen);
	assert(received[0] == 1);
	assert(orbis_audin_set_enabled(&contexts[0], TRUE) == CHANNEL_RC_OK);
	DeliverSamples(((AudinMacDevice *)devices[0])->audioQueue);
	assert(received[0] == 2);
	assert(orbis_audin_set_enabled(&contexts[0], FALSE) == CHANNEL_RC_OK);
	authorization = AVAuthorizationStatusDenied;
	assert(orbis_audin_set_enabled(&contexts[0], TRUE) == ERROR_ACCESS_DENIED);
	assert(!((AudinMacDevice *)devices[0])->isOpen);
	assert(orbis_audin_set_enabled(&contexts[1], FALSE) == CHANNEL_RC_OK);
	assert(received[1] == 1);
	for (size_t i = 0; i < 2; i++)
	{
		assert(devices[i]->Free(devices[i]) == CHANNEL_RC_OK);
		orbis_audin_remove_context(&contexts[i]);
	}
	assert(!audinControls);
	assert(queueStarts == queueStops && queueCreations == queueDisposals);
}

static void CheckRemovalBeforeBackendFree(void)
{
	authorization = AVAuthorizationStatusAuthorized;
	rdpContext context = { 0 };
	assert(orbis_audin_set_enabled(&context, TRUE) == CHANNEL_RC_OK);
	IAudinDevice *device = CreateMicrophone(&context);
	AUDIO_FORMAT format = MicrophoneFormat();
	NSUInteger received = 0;
	assert(device->SetFormat(device, &format, 480) == CHANNEL_RC_OK);
	assert(device->Open(device, ReceiveSamples, &received) == CHANNEL_RC_OK);
	orbis_audin_remove_context(&context);
	assert(!audinControls && !((AudinMacDevice *)device)->isOpen && received == 0);
	assert(device->Free(device) == CHANNEL_RC_OK);
	orbis_audin_remove_context(&context);
	assert(!audinControls);
}

static pthread_mutex_t fixtureLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t fixtureCondition = PTHREAD_COND_INITIALIZER;
static BOOL callbackEntered, releaseCallback, disableReturned, freeReturned;
static NSUInteger concurrentSamples;

static UINT ReceiveBlocking(const AUDIO_FORMAT *format, const BYTE *data, size_t size, void *userData)
{
	(void)format; (void)data; (void)size; (void)userData;
	pthread_mutex_lock(&fixtureLock);
	concurrentSamples++;
	callbackEntered = YES;
	pthread_cond_broadcast(&fixtureCondition);
	while (!releaseCallback)
		pthread_cond_wait(&fixtureCondition, &fixtureLock);
	pthread_mutex_unlock(&fixtureLock);
	return CHANNEL_RC_OK;
}

static void *CallbackThread(void *queue)
{
	DeliverSamples((AudioQueueRef)queue);
	return NULL;
}

static void *DisableThread(void *context)
{
	assert(orbis_audin_set_enabled(context, FALSE) == CHANNEL_RC_OK);
	pthread_mutex_lock(&fixtureLock);
	disableReturned = YES;
	pthread_mutex_unlock(&fixtureLock);
	return NULL;
}

static void *FreeThread(void *device)
{
	assert(((IAudinDevice *)device)->Free(device) == CHANNEL_RC_OK);
	pthread_mutex_lock(&fixtureLock);
	freeReturned = YES;
	pthread_mutex_unlock(&fixtureLock);
	return NULL;
}

static void CheckConcurrentDisableAndFree(void)
{
	authorization = AVAuthorizationStatusAuthorized;
	rdpContext context = { 0 };
	assert(orbis_audin_set_enabled(&context, TRUE) == CHANNEL_RC_OK);
	IAudinDevice *device = CreateMicrophone(&context);
	AudinMacDevice *mac = (AudinMacDevice *)device;
	AUDIO_FORMAT format = MicrophoneFormat();
	assert(device->SetFormat(device, &format, 480) == CHANNEL_RC_OK);
	assert(device->Open(device, ReceiveBlocking, NULL) == CHANNEL_RC_OK);
	pthread_t callback, disable, cleanup;
	assert(pthread_create(&callback, NULL, CallbackThread, mac->audioQueue) == 0);
	pthread_mutex_lock(&fixtureLock);
	struct timespec deadline;
	clock_gettime(CLOCK_REALTIME, &deadline);
	deadline.tv_sec += 5;
	while (!callbackEntered)
		assert(pthread_cond_timedwait(&fixtureCondition, &fixtureLock, &deadline) == 0);
	pthread_mutex_unlock(&fixtureLock);
	assert(pthread_create(&disable, NULL, DisableThread, &context) == 0);

	/* Observe the live operation's lease and lifecycle lock while forwarding is blocked. */
	BOOL pending = NO;
	for (NSUInteger attempt = 0; attempt < 1000 && !pending; attempt++)
	{
		pthread_mutex_lock(&audinControlLock);
		BOOL leased = mac->controlRefs > 0;
		pthread_mutex_unlock(&audinControlLock);
		if (leased)
		{
			int result = pthread_mutex_trylock(&mac->captureLock);
			pending = result == EBUSY;
			if (result == 0) pthread_mutex_unlock(&mac->captureLock);
		}
		if (!pending) { struct timespec delay = { .tv_nsec = 1000000 }; nanosleep(&delay, NULL); }
	}
	assert(pending);
	pthread_mutex_lock(&fixtureLock);
	assert(!disableReturned);
	pthread_mutex_unlock(&fixtureLock);
	assert(pthread_create(&cleanup, NULL, FreeThread, device) == 0);
	BOOL detached = NO;
	for (NSUInteger attempt = 0; attempt < 1000 && !detached; attempt++)
	{
		pthread_mutex_lock(&audinControlLock);
		AudinMacControl *control = audin_mac_control(&context, FALSE);
		detached = control && !control->device;
		pthread_mutex_unlock(&audinControlLock);
		if (!detached) { struct timespec delay = { .tv_nsec = 1000000 }; nanosleep(&delay, NULL); }
	}
	assert(detached);
	pthread_mutex_lock(&fixtureLock);
	assert(!freeReturned);
	releaseCallback = YES;
	pthread_cond_broadcast(&fixtureCondition);
	pthread_mutex_unlock(&fixtureLock);
	assert(pthread_join(callback, NULL) == 0);
	assert(pthread_join(disable, NULL) == 0);
	assert(pthread_join(cleanup, NULL) == 0);
	assert(disableReturned && freeReturned && concurrentSamples == 1);
	orbis_audin_remove_context(&context);
	assert(!audinControls);
	assert(queueStarts == queueStops && queueCreations == queueDisposals);
}

int main(void)
{
	@autoreleasepool
	{
		CheckPermissionAndFormats();
		CheckLiveToggleAndContextIsolation();
		CheckRemovalBeforeBackendFree();
		CheckConcurrentDisableAndFree();
		puts("PASS: default-off negotiation, live microphone toggling, permission, formats, and concurrent cleanup");
	}
	return 0;
}
