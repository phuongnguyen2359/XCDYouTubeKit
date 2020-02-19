//
//  XCDURLGetOperation.m
//  XCDYouTubeKit
//
//  Created by Soneé John on 2/18/20.
//  Copyright © 2020 Cédric Luthi. All rights reserved.
//

#import "XCDURLGetOperation.h"

@interface XCDURLGetOperation() <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
@property (atomic, assign) BOOL isExecuting;
@property (atomic, assign) BOOL isFinished;

@property (atomic, strong) NSURLSessionDataTask *dataTask;
@property (atomic, strong) NSURLSession *session;
@property (atomic, readonly) dispatch_semaphore_t operationStartSemaphore;

@property (atomic, readwrite, nullable) NSURLResponse *response;

@property (atomic, readwrite, nullable) NSError *error;

@end

@implementation XCDURLGetOperation

- (instancetype) initWithURL:(NSURL *)url info:(NSDictionary *)info cookes:(NSArray<NSHTTPCookie *> *)cookies
{
	if (!(self = [super init]))
		return nil;
	
	_url = url;
	_info = [info copy];
	_cookies = [cookies copy];
	
	_session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration] delegate:self delegateQueue:nil];
	
	for (NSHTTPCookie *cookie in _cookies) {
		[_session.configuration.HTTPCookieStorage setCookie:cookie];
	}
	
	_operationStartSemaphore = dispatch_semaphore_create(0);
	
	return self;
}

#pragma mark - NSOperation

+ (BOOL) automaticallyNotifiesObserversForKey:(NSString *)key
{
	SEL selector = NSSelectorFromString(key);
	return selector == @selector(isExecuting) || selector == @selector(isFinished) || [super automaticallyNotifiesObserversForKey:key];
}

- (BOOL) isAsynchronous
{
	return YES;
}

- (void) start
{
	dispatch_semaphore_signal(self.operationStartSemaphore);
	
	if (self.isCancelled)
		return;
	
	self.isExecuting = YES;
	
	[self startRequest];
}

- (void) cancel
{
	if (self.isCancelled || self.isFinished)
		return;
	
	[super cancel];
	
	[self.dataTask cancel];
	
	dispatch_semaphore_wait(self.operationStartSemaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(200 * NSEC_PER_MSEC)));
	
	[self finish];
}

#pragma mark -

- (void)finishWithError:(NSError *)error
{
	self.error = error;
	[self finish];
}

- (void)finish
{
	self.isExecuting = NO;
	self.isFinished = YES;
	[self.session invalidateAndCancel];
}

#pragma mark -

- (void)startRequest
{
	//Start request by downloading the first ~1MB of the file
	//This helps to catch errors such as the one in this issue here: https://github.com/0xced/XCDYouTubeKit/issues/456
	NSUInteger rangeStart = 0;
	NSUInteger rangeEnd = 1000000;
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.url];
	[request addValue:[NSString stringWithFormat:@"bytes=%@-%@", @(rangeStart), @(rangeEnd)] forHTTPHeaderField:@"Range"];

	self.dataTask = [self.session dataTaskWithRequest:request];
	
	[self.dataTask resume];
}

#pragma mark - NSURLSessionDataDelegate

- (void) URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
	
	NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
	self.response = response;
	
	if (httpResponse.statusCode != 200 && httpResponse.statusCode != 206)
	{
		//statusCode is not 200 and isn't 206
		//Bad server response
		[self finish];
		return;
	}
	
	if (httpResponse.statusCode != 206)
	{
		// Does not support partial content so we will simply finish the operation.
		// Continuing will cause us to download the entire file
		[self finish];
		return;
	}
	
	completionHandler(NSURLSessionResponseAllow);
}

- (void) URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
	self.response = dataTask.response;
}

#pragma mark - NSURLSessionTaskDelegate

- (void) URLSession:(NSURLSession *)session task:(NSURLSessionTask *)dataTask didCompleteWithError:(NSError *)error
{
	self.response = dataTask.response;
	if (self.isCancelled)
		return;
	
	[self finishWithError:error];
}

@end