//
//  ErizoClientIOS
//
//  Copyright (c) 2015 Alvaro Gil (zevarito@gmail.com).
//
//  MIT License, see LICENSE file for details.
//

#import "ECRoom.h"
#import "ECStream.h"
#import "ECCLient.h"
#import "ECClient+Internal.h"
#import "ECSignalingChannel.h"

#import "RTCAVFoundationVideoSource.h"
#import "RTCMediaConstraints.h"
#import "RTCMediaStream.h"

#import "Logger.h"

@implementation ECRoom {
    ECSignalingChannel *signalingChannel;
    ECClient *publishClient;
}

- (instancetype)init {
    if (self = [super init]) {
        _recordEnabled = NO;
    }
    return self;
}

- (instancetype)initWithDelegate:(id<ECRoomDelegate>)roomDelegate {
    if (self = [self init]) {
        _delegate = roomDelegate;
    }
    return self;
}

- (instancetype)initWithEncodedToken:(NSString*)encodedToken delegate:(id<ECRoomDelegate>)roomDelegate {
    if (self = [self initWithDelegate:roomDelegate]) {
        [self createSignalingChannelWithEncodedToken:encodedToken];
    }
    return self;
}

- (void)createSignalingChannelWithEncodedToken:(NSString *)encodedToken {
    signalingChannel = [[ECSignalingChannel alloc] initWithEncodedToken:encodedToken
                                                           roomDelegate:self];
    [signalingChannel connect];
}

- (void)publish:(ECStream *)stream withOptions:(NSDictionary *)options {
    // Create a ECClient instance to handle peer connection for this publishing.
    // It is very important to use the same factory.
    publishClient = [[ECClient alloc] initWithDelegate:self
                                           andPeerFactory:stream.peerFactory];
    
    // Keep track of the stream that this room will be publishing
    _publishStream = stream;
    
    // Publishing options
    int videoCount = _publishStream.mediaStream.videoTracks.count;
    int audioCount = _publishStream.mediaStream.audioTracks.count;
    
    NSDictionary *opts = @{
                           @"video": videoCount > 0 ? @"true" : @"false",
                           @"audio": audioCount > 0 ? @"true" : @"false",
                           @"data": [options objectForKey:@"data"],
                           };
    
    // Ask for publish
    [signalingChannel publish:opts signalingChannelDelegate:publishClient];
}

- (void)subscribe:(NSString *)streamId {
    // Create a ECClient instance to handle peer connection for this publishing.
    ECClient *subscribeClient = [[ECClient alloc] initWithDelegate:self];
    
    // Ask for subscribing
    [signalingChannel subscribe:streamId signalingChannelDelegate:subscribeClient];
}

- (void)unsubscribe:(NSString *)streamId {
    [signalingChannel unsubscribe:streamId];
}

#
# pragma mark - ECSignalingChannelRoomDelegate
#

- (void)signalingChannel:(ECSignalingChannel *)channel didError:(NSString *)reason {
    [_delegate room:self didError:ECRoomConnectionError reason:reason];
}

- (void)signalingChannel:(ECSignalingChannel *)channel didConnectToRoom:(NSDictionary *)roomMeta {
    NSString *roomId = [roomMeta objectForKey:@"id"];
    NSArray *streamIds = [roomMeta objectForKey:@"streams"];
    
    _roomId = roomId;
    
    [_delegate room:self didConnect:roomMeta];
    [_delegate room:self didReceiveStreamsList:streamIds];
}

- (void)signalingChannel:(ECSignalingChannel *)channel didReceiveStreamIdReadyToPublish:(NSString *)streamId {
    L_DEBUG(@"Room: didReceiveStreamIdReadyToPublish streamId: %@", streamId);
    _publishStreamId = streamId;
}

- (void)signalingChannel:(ECSignalingChannel *)channel didStartRecordingStreamId:(NSString *)streamId
                                                                 withRecordingId:(NSString *)recordingId {
    [_delegate room:self didStartRecordingStreamId:streamId withRecordingId:recordingId];
}

- (void)signalingChannel:(ECSignalingChannel *)channel didStreamAddedWithId:(NSString *)streamId {
    if ([_publishStreamId isEqualToString:streamId]) {
        [_delegate room:self didPublishStreamId:streamId];
        if (_recordEnabled) {
            [signalingChannel startRecording:_publishStreamId];
        }
    } else {
        [_delegate room:self didAddedStreamId:streamId];
    }
}

- (void)signalingChannel:(ECSignalingChannel *)channel didStreamRemovedWithId:(NSString *)streamId {
    [_delegate room:self didRemovedStreamId:streamId];
}

- (void)signalingChannel:(ECSignalingChannel *)channel didUnsubscribeStreamWithId:(NSString *)streamId {
    [_delegate room:self didUnSubscribeStream:streamId];
}

#
# pragma mark - ECClientDelegate
#

- (void)appClient:(ECClient *)_client didChangeState:(ECClientState)state {
    L_INFO(@"Room: Client didChangeState: %@", clientStateToString(state));
}

- (void)appClient:(ECClient *)client didChangeConnectionState:(RTCICEConnectionState)state {
    L_DEBUG(@"Room: didChangeConnectionState: %i", state);
}

- (RTCMediaStream *)streamToPublishByAppClient:(ECClient *)client {
    return _publishStream.mediaStream;
}

- (void)appClient:(ECClient *)client didReceiveRemoteStream:(RTCMediaStream *)stream
                                               withStreamId:(NSString *)streamId {
    L_DEBUG(@"Room: didReceiveRemoteStream");
    
    if ([_publishStreamId isEqualToString:streamId]) {
        // Ignore stream since it is the local one.
    } else {
        ECStream *erizoStream =  [[ECStream alloc] initWithRTCMediaStream:stream
                                                             withStreamId:streamId];
        [_delegate room:self didSubscribeStream:erizoStream];
    }
}

- (void)appClient:(ECClient *)client
    didError:(NSError *)error {
    L_ERROR(@"Room: Client error: %@", error.userInfo);
}

@end