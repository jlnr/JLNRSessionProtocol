//
//  AppDelegate.m
//  JLNRURLProtocolTest
//
//  Created by Julian Raschke on 11.06.14.
//
//

#import "AppDelegate.h"
#import "JLNRSessionProtocol.h"
#import <AFNetworking/AFNetworking.h>

@interface AppDelegate () <JLNRSession>

@property (nonatomic) NSString *jsession;
@property (unsafe_unretained) IBOutlet NSTextView *logTextView;

@end


@implementation AppDelegate

#pragma mark - JLNRSession helpers

- (id)init
{
    if ((self = [super init])) {
        [NSHTTPCookieStorage sharedHTTPCookieStorage].cookieAcceptPolicy =
            NSHTTPCookieAcceptPolicyNever;
    }
    return self;
}

- (NSURLRequest *)loginRequest
{
    NSDictionary *parameters =
    @{ @"username": @"alice", @"password": @"secret" };
    
    NSURL *URL = [NSURL URLWithString:@"http://localhost:9292/login"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:parameters
                                                       options:0
                                                         error:NULL];
    return [request copy];
}

#pragma mark - JLNRSession protocol implementation

- (BOOL)sessionShouldHandleRequest:(NSURLRequest *)request
{
    return YES;
}

- (NSURLRequest *)sessionRequestBeforeRequest:(NSURLRequest *)request
{
    if (self.jsession == nil) {
        [self log:@"No session cookie so far, logging in…"];
        return [self loginRequest];
    }
    else {
        return nil;
    }
}

- (NSURLRequest *)sessionRequestAfterResponse:(NSURLResponse *)response
                                         data:(NSData *)data
{
    // Only care about HTTP responses.
    if (! [response isKindOfClass:[NSHTTPURLResponse class]]) {
        return nil;
    }
    
    NSHTTPURLResponse *HTTPResponse = (NSHTTPURLResponse *)response;
    
    BOOL wasUnauthorized = (HTTPResponse.statusCode == 401 ||
                            ! [HTTPResponse.MIMEType isEqual:@"application/json"]);
    
    if (wasUnauthorized) {
        [self log:@"Authorization failure, attempting to login…"];
    }
    
    return wasUnauthorized ? [self loginRequest] : nil;
}

- (BOOL)storeSessionFromResponse:(NSURLResponse *)response data:(NSData *)data
{
    if (! [response isKindOfClass:[NSHTTPURLResponse class]]) {
        return NO;
    }
    
    NSHTTPURLResponse *HTTPResponse = (NSHTTPURLResponse *)response;
    NSString *cookie = HTTPResponse.allHeaderFields[@"Set-Cookie"];
    
    BOOL success = (HTTPResponse.statusCode == 200 &&
                    [HTTPResponse.MIMEType isEqual:@"application/json"]);
    
    if (success) {
        self.jsession = [[cookie componentsSeparatedByString:@";"] firstObject];
        [self log:@"Got new session cookie"];
    }
    
    return success;
}

- (void)applySessionToRequest:(NSMutableURLRequest *)request
{
    [request setValue:self.jsession forHTTPHeaderField:@"Cookie"];
}

#pragma mark - Actions

- (IBAction)login:(id)sender
{
    [JLNRSessionProtocol registerSession:self];
    [self log:@"Registered JLNRSession"];
}

- (IBAction)logout:(id)sender
{
    self.jsession = nil;
    [JLNRSessionProtocol invalidateSession:self];
    [self log:@"Invalidated JLNRSession"];
}

- (IBAction)sendRequest:(id)sender
{
    NSURL *URL = [NSURL URLWithString:@"http://localhost:9292/api_call"];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:URL];
    
    AFJSONRequestOperation *operation =
        [AFJSONRequestOperation JSONRequestOperationWithRequest:request
                                                        success:^(NSURLRequest *request,
                                                                  NSHTTPURLResponse *response,
                                                                  id JSON) {
        [self log:[NSString stringWithFormat:@"Received JSON, status %@",
                   @(response.statusCode)]];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [self log:error.localizedDescription];
    }];
    
    [operation start];
}

#pragma mark - Logging

- (void)log:(id)object
{
    NSString *string = [[object description] stringByAppendingString:@"\n\n"];
    NSAttributedString* attributedString =
        [[NSAttributedString alloc] initWithString:string];
    
    [self.logTextView.textStorage appendAttributedString:attributedString];
    NSRange rangeAtEnd = NSMakeRange(self.logTextView.string.length, 0);
    [self.logTextView scrollRangeToVisible:rangeAtEnd];
}

@end
