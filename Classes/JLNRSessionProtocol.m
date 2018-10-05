//
//  JLNRSessionProtocol.m
//  JLNRSessionProtocolTest
//
//  Created by Julian Raschke on 11.06.14.
//  Copyright © 2014 Raschke & Ludwig GbR. All rights reserved.
//

#import "JLNRSessionProtocol.h"


#ifdef DEBUG
#define JLNRLog(...) NSLog(__VA_ARGS__)
#else
#define JLNRLog(...)
#endif


static NSPointerArray *sessions;


// Not prefixed, since it is only used internally.
typedef NS_ENUM(NSInteger, RequestState) {
    RequestStateBeforeRequest = 0,
    RequestStateFirstChance,
    RequestStateAfterResponse,
    RequestStateSecondChance,
    RequestStateFinished,
};


@interface JLNRSessionProtocol () <NSURLConnectionDataDelegate>

@property (nonatomic) RequestState state;
@property (nonatomic) NSURLConnection *connection;
@property (nonatomic) id<JLNRSession> session;

@property (nonatomic) NSURLResponse *currentResponse;
@property (nonatomic) NSMutableData *currentData;

@property (nonatomic) NSURLResponse *originalResponse;
@property (nonatomic, copy) NSData *originalData;

@end


@implementation JLNRSessionProtocol

#pragma mark - Thread-safe session management

+ (void)initialize
{
    sessions = [NSPointerArray weakObjectsPointerArray];
}

+ (void)registerSession:(id<JLNRSession>)session
{
    @synchronized(sessions) {
        [sessions compact];
        [sessions addPointer:(__bridge void *)session];
        if ([sessions count] == 1) {
            [NSURLProtocol registerClass:self.class];
            JLNRLog(@"Registered JLNRSessionProtocol");
        }
    }
}

+ (void)invalidateSession:(id<JLNRSession>)session
{
    @synchronized(sessions) {
        [sessions compact];
        NSUInteger previousSessionCount = sessions.count;
        for (NSInteger i = 0; i < previousSessionCount; ++i) {
            if ([sessions pointerAtIndex:i] == (__bridge void *)session) {
                [sessions replacePointerAtIndex:i withPointer:NULL];
                break;
            }
        }
        [sessions compact];
        if (previousSessionCount > 0 && sessions.count == 0) {
            [NSURLProtocol unregisterClass:self.class];
            JLNRLog(@"Unregistered JLNRSessionProtocol");
        }
    }
}

+ (nullable id<JLNRSession>)firstSessionInterestedInRequest:(NSURLRequest *)request
{
    NSArray *currentSessions;
    @synchronized(sessions) {
        [sessions compact];
        currentSessions = [sessions allObjects];
    }
    
    for (id<JLNRSession> session in currentSessions) {
        if ([session shouldHandleRequest:request]) {
            return session;
        }
    }
    
    return nil;
}

#pragma mark - NSURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    id internalRequestMarker = [NSURLProtocol propertyForKey:NSStringFromClass(self.class)
                                                   inRequest:request];
    // Do not pass internally created requests on to our registered sessions.
    return internalRequestMarker == nil && [self firstSessionInterestedInRequest:request] != nil;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (id)initWithRequest:(NSURLRequest *)request
       cachedResponse:(NSCachedURLResponse *)cachedResponse
               client:(id<NSURLProtocolClient>)client
{
    if ((self = [super initWithRequest:request
                        cachedResponse:cachedResponse
                                client:client])) {
        self.session = [self.class firstSessionInterestedInRequest:request];
    }
    return self;
}

- (void)startLoading
{
    [self sendNextRequestOrFinish];
}

- (void)stopLoading
{
    if (self.state != RequestStateFinished) {
        JLNRLog(@"Stopping request in state %@: %@", @(self.state), self.request);
    }

    [self.connection cancel];
    self.connection = nil;
}

#pragma mark - Actual state-advancing logic

- (void)sendNextRequestOrFinish
{
    NSMutableURLRequest *nextRequest = nil;
    
    JLNRLog(@"Advancing one step for request %@, state = %@", self.request.URL, @(self.state));
    
    if (self.state == RequestStateBeforeRequest) {
        nextRequest = [[self.session loginRequestBeforeRequest:self.request] mutableCopy];
        
        if (nextRequest == nil) {
            self.state = RequestStateFirstChance;
            JLNRLog(@"No need to log in before request: %@", self.request.URL);
        } else {
            JLNRLog(@"Logging in before request: %@", self.request.URL);
        }
    }
    
    if (self.state == RequestStateFirstChance ||
        self.state == RequestStateSecondChance) {
        
        JLNRLog(@"Will try to send request %@", self.request.URL);
        nextRequest = [self.request mutableCopy];
        [self.session applySecretToRequest:nextRequest];
    }
    
    if (self.state == RequestStateAfterResponse) {
        nextRequest =
            [[self.session loginRequestAfterResponse:(NSHTTPURLResponse *)self.currentResponse
                                                data:self.currentData] mutableCopy];
        
        if (nextRequest == nil) {
            self.state = RequestStateFinished;
            JLNRLog(@"No need to log in after request: %@", self.request.URL);
        } else {
            JLNRLog(@"Logging in after request: %@", self.request.URL);
        }
    }
    
    if (self.state == RequestStateFinished) {
        JLNRLog(@"Finished - passing response to outer request");
        [self finish];
    } else {
        // If we get here, we need to send a login request.
        NSAssert(nextRequest, @"we must have a request to send at this point");
        
        JLNRLog(@"Opening connection for %@", nextRequest.URL);
        
        // Mark this request as internal to JLNRSessionProtocol so we can ignore it later.
        [NSURLProtocol setProperty:@YES
                            forKey:NSStringFromClass(self.class)
                         inRequest:nextRequest];
        
        self.currentResponse = nil;
        self.currentData = nil;
        self.connection = [NSURLConnection connectionWithRequest:nextRequest delegate:self];
        [self.connection start];
    }
}

- (void)finish
{
    [self.client URLProtocol:self
          didReceiveResponse:self.originalResponse
          cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    
    [self.client URLProtocol:self
                 didLoadData:self.originalData];
    
    [self.client URLProtocolDidFinishLoading:self];
}

#pragma mark - NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    NSParameterAssert([response isKindOfClass:[NSHTTPURLResponse class]]);
    JLNRLog(@"connection: %@ didReceiveResponse: statusCode=%@",
            connection, @(((NSHTTPURLResponse *)response).statusCode));
    
    self.currentResponse = response;
    self.currentData = [NSMutableData data];
    
    if (self.state == RequestStateFirstChance || self.state == RequestStateSecondChance) {
        self.originalResponse = response;
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [self.currentData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    JLNRLog(@"connectionDidFinishLoading: %@", connection);
    
    if (self.state == RequestStateFirstChance || self.state == RequestStateSecondChance) {
        self.originalData = self.currentData;
    } else if (self.state == RequestStateBeforeRequest || self.state == RequestStateAfterResponse) {
        if (! [self.session storeSecretFromResponse:(NSHTTPURLResponse *)self.currentResponse
                                               data:self.currentData]) {
            
            NSError *error = [NSError errorWithDomain:NSStringFromClass(self.class)
                                                 code:0
                                             userInfo:@{}];
            
            [self.client URLProtocol:self didFailWithError:error];
            
            return;
        }
    }
    
    self.state++;
    
    self.connection = nil;

    [self sendNextRequestOrFinish];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    JLNRLog(@"connection:didFailWithError: %@", connection);

    [self.client URLProtocol:self didFailWithError:error];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return nil;
}

@end
