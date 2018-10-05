//
//  JLNRSessionProtocol.h
//  JLNRSessionProtocolTest
//
//  Created by Julian Raschke on 11.06.14.
//  Copyright © 2014 Raschke & Ludwig GbR. All rights reserved.
//


#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

@protocol JLNRSession

@required

- (BOOL)shouldHandleRequest:(NSURLRequest *)request;

- (nullable NSURLRequest *)loginRequestBeforeRequest:(NSURLRequest *)request;

- (nullable NSURLRequest *)loginRequestAfterResponse:(NSHTTPURLResponse *)response data:(NSData *)data;

- (void)applySecretToRequest:(NSMutableURLRequest *)request;

- (BOOL)storeSecretFromResponse:(NSHTTPURLResponse *)response data:(NSData *)data;

@end


@interface JLNRSessionProtocol : NSURLProtocol

+ (void)registerSession:(id<JLNRSession>)session;
+ (void)invalidateSession:(id<JLNRSession>)session;

@end

NS_ASSUME_NONNULL_END
