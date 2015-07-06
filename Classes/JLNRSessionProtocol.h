//
//  JLNRSessionProtocol.h
//  JLNRSessionProtocolTest
//
//  Created by Julian Raschke on 11.06.14.
//
//


#import <Foundation/Foundation.h>


@protocol JLNRSession;


@interface JLNRSessionProtocol : NSURLProtocol

+ (void)registerSession:(id<JLNRSession>)session;
+ (void)invalidateSession:(id<JLNRSession>)session;

@end


@protocol JLNRSession

@required

- (BOOL)sessionShouldHandleRequest:(NSURLRequest *)request;

- (NSURLRequest *)sessionRequestBeforeRequest:(NSURLRequest *)request;

- (NSURLRequest *)sessionRequestAfterResponse:(NSURLResponse *)response data:(NSData *)data;

- (void)applySessionToRequest:(NSMutableURLRequest *)request;

- (BOOL)storeSessionFromResponse:(NSURLResponse *)response data:(NSData *)data;

@end
