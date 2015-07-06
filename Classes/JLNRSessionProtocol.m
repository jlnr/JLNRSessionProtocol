//
//  JLNRSessionProtocol.m
//  JLNRSessionProtocolTest
//
//  Created by Julian Raschke on 11.06.14.
//
//

#import "JLNRSessionProtocol.h"


#ifdef JLNR_SESSION_PROTOCOL_TEST
#define JLNRLog(...) NSLog(__VA_ARGS__)
#else
#define JLNRLog(...)
#endif


static NSPointerArray *sessions;


typedef NS_ENUM(NSInteger, JLNRSessionRequestState) {
    JLNRSessionRequestStateBeforeRequest = 0,
    JLNRSessionRequestStateFirstChance,
    JLNRSessionRequestStateAfterResponse,
    JLNRSessionRequestStateSecondChance,
    JLNRSessionRequestStateFinished,
};


@interface JLNRSessionProtocol () <NSURLConnectionDataDelegate>

@property (nonatomic) JLNRSessionRequestState state;
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
        NSUInteger lastSessionCount = [sessions count];
        
        [sessions addPointer:(__bridge void *)(session)];
        
        if (lastSessionCount == 0 && [sessions count] > 0) {
            [NSURLProtocol registerClass:self.class];
        }
    }
}

+ (void)invalidateSession:(id<JLNRSession>)session
{
    @synchronized(sessions) {
        NSUInteger lastSessionCount = [sessions count];

        for (NSInteger i = 0; i < lastSessionCount; ++i) {
            if ([sessions pointerAtIndex:i] == (__bridge void *)session) {
                [sessions replacePointerAtIndex:i withPointer:NULL];
            }
        }
        [sessions compact];
        
        if (lastSessionCount > 0 && [sessions count] == 0) {
            [NSURLProtocol unregisterClass:self.class];
        }
    }
}

+ (id<JLNRSession>)firstSessionInterestedInRequest:(NSURLRequest *)request
{
    NSArray *currentSessions = nil;
    @synchronized(sessions) {
        currentSessions = [sessions allObjects];
    }
    
    for (id<JLNRSession> session in currentSessions) {
        if ([session sessionShouldHandleRequest:request]) {
            return session;
        }
    }
    
    return nil;
}

#pragma mark - NSURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    BOOL isInternalRequest =
        [NSURLProtocol propertyForKey:NSStringFromClass(self.class)
                            inRequest:request] != nil;
    
    if (isInternalRequest) {
        return NO;
    }
    
    return [self firstSessionInterestedInRequest:request] != nil;
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
    if (self.state != JLNRSessionRequestStateFinished) {
        JLNRLog(@"Stopping request in state %@: %@", @(self.state), self.request);
    }

    [self.connection cancel];
    self.connection = nil;
}

#pragma mark - Actual state-advancing logic

- (void)sendNextRequestOrFinish
{
    NSMutableURLRequest *nextRequest = nil;
    
    if (self.state == JLNRSessionRequestStateBeforeRequest) {
        nextRequest = [[self.session sessionRequestBeforeRequest:self.request] mutableCopy];
        
        if (nextRequest == nil) {
            self.state = JLNRSessionRequestStateFirstChance;
        }
        else {
            JLNRLog(@"Opening session before request: %@", self.request);
        }
    }
    
    if (self.state == JLNRSessionRequestStateFirstChance ||
        self.state == JLNRSessionRequestStateSecondChance) {
        
        nextRequest = [self.request mutableCopy];
        
        [self.session applySessionToRequest:nextRequest];
    }
    
    if (self.state == JLNRSessionRequestStateAfterResponse) {
        
        nextRequest =
            [[self.session sessionRequestAfterResponse:self.currentResponse
                                                  data:self.currentData] mutableCopy];
        
        if (nextRequest == nil) {
            self.state = JLNRSessionRequestStateFinished;
        }
    }
    
    if (self.state == JLNRSessionRequestStateFinished) {
        [self finish];
    }
    else {
        [NSURLProtocol setProperty:@YES
                            forKey:NSStringFromClass(self.class)
                         inRequest:nextRequest];
        
        self.currentResponse = nil;
        self.currentData = nil;
        self.connection = [NSURLConnection connectionWithRequest:nextRequest
                                                        delegate:self];
        
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
    JLNRLog(@"connection: %@ didReceiveResponse: %@", connection, response);
    
    self.currentResponse = response;
    self.currentData = [NSMutableData data];
    
    if (self.state == JLNRSessionRequestStateFirstChance ||
        self.state == JLNRSessionRequestStateSecondChance) {
        
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
    
    if (self.state == JLNRSessionRequestStateFirstChance ||
        self.state == JLNRSessionRequestStateSecondChance) {
        
        self.originalData = self.currentData;
    }
    else if (self.state == JLNRSessionRequestStateBeforeRequest ||
             self.state == JLNRSessionRequestStateAfterResponse) {
        
        if (! [self.session storeSessionFromResponse:self.currentResponse
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

- (void)connection:(NSURLConnection *)connection
  didFailWithError:(NSError *)error
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
