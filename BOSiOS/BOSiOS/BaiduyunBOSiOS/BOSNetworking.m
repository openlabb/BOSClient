//
//  BOSNetworking.m
//  BOS_ios_sdk
//
//  Created by zhouzhuo on 8/16/15.
//  Copyright (c) 2015 baiduyun.com. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "BOSDefine.h"
#import "BOSNetworking.h"
#import "BOSBolts.h"
#import "BOSModel.h"
#import "BOSUtil.h"
#import "BOSLog.h"
#import "BOSXMLDictionary.h"


@implementation BOSURLRequestRetryHandler

- (BOSNetworkingRetryType)shouldRetry:(uint32_t)currentRetryCount
                      requestDelegate:(BOSNetworkingRequestDelegate *)delegate
                             response:(NSHTTPURLResponse *)response
                                error:(NSError *)error {

    if (currentRetryCount >= self.maxRetryCount) {
        return BOSNetworkingRetryTypeShouldNotRetry;
    }
    
    /**
     设置onRecieveData回调时，在回调处理数据时无法获知重试事件
     出错时，禁止重试
     */
    if (delegate.onRecieveData != nil) {
        return BOSNetworkingRetryTypeShouldNotRetry;
    }
    
    if ([error.domain isEqualToString:BOSClientErrorDomain]) {
        if (error.code == BOSClientErrorCodeTaskCancelled) {
            return BOSNetworkingRetryTypeShouldNotRetry;
        } else {
            return BOSNetworkingRetryTypeShouldRetry;
        }
    }

    switch (response.statusCode) {
        case 403:
            if ([[[error userInfo] objectForKey:@"Code"] isEqualToString:@"RequestTimeTooSkewed"]) {
                return BOSNetworkingRetryTypeShouldCorrectClockSkewAndRetry;
            }
            break;

        default:
            break;
    }

    return BOSNetworkingRetryTypeShouldNotRetry;
}

- (NSTimeInterval)timeIntervalForRetry:(uint32_t)currentRetryCount retryType:(BOSNetworkingRetryType)retryType {
    switch (retryType) {
        case BOSNetworkingRetryTypeShouldCorrectClockSkewAndRetry:
        case BOSNetworkingRetryTypeShouldRefreshCredentialsAndRetry:
            return 0;

        default:
            return pow(2, currentRetryCount) * 200 / 1000;
    }
}

+ (instancetype)defaultRetryHandler {
    BOSURLRequestRetryHandler * retryHandler = [BOSURLRequestRetryHandler new];
    retryHandler.maxRetryCount = BOSDefaultRetryCount;
    return retryHandler;
}

@end

@implementation BOSNetworkingConfiguration
@end

@implementation BOSNetworkingRequestDelegate

- (instancetype)init {
    if (self = [super init]) {
        self.retryHandler = [BOSURLRequestRetryHandler defaultRetryHandler];
        self.interceptors = [[NSMutableArray alloc] init];
        self.isHttpdnsEnable = YES;
    }
    return self;
}

- (void)reset {
    self.isHttpRequestNotSuccessResponse = NO;
    self.error = nil;
    self.payloadTotalBytesWritten = 0;
    self.isRequestCancelled = NO;
    [self.responseParser reset];
}

- (void)cancel {
    self.isRequestCancelled = YES;
    if (self.currentSessionTask) {
        BOSLogDebug(@"this task is cancelled now!");
        [self.currentSessionTask cancel];
    }
}

- (BOSTask *)validateRequestParams {
    NSString * errorMessage = nil;

    if ((self.operType == BOSOperationTypeAppendObject || self.operType == BOSOperationTypePutObject || self.operType == BOSOperationTypeUploadPart)
        && !self.uploadingData && !self.uploadingFileURL) {
        errorMessage = @"This operation need data or file to upload but none is set";
    }

    if (self.uploadingFileURL && ![[NSFileManager defaultManager] fileExistsAtPath:[self.uploadingFileURL path]]) {
        errorMessage = @"File doesn't exist";
    }

    if (errorMessage) {
        return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                         code:BOSClientErrorCodeInvalidArgument
                                                     userInfo:@{BOSErrorMessageTOKEN: errorMessage}]];
    } else {
        return [self.allNeededMessage validateRequestParamsInOperationType:self.operType];
    }
}

- (BOSTask *)buildInternalHttpRequest {

    BOSTask * validateParam = [self validateRequestParams];
    if (validateParam.error) {
        return validateParam;
    }

#define URLENCODE(a) [BOSUtil encodeURL:(a)]
    BOSLogDebug(@"start to build request");
    // build base url string
    NSString * urlString = self.allNeededMessage.endpoint;

    NSURL * endPointURL = [NSURL URLWithString:self.allNeededMessage.endpoint];
    if ([BOSUtil isBOSOriginBucketHost:endPointURL.host] && self.allNeededMessage.bucketName) {
        urlString = [NSString stringWithFormat:@"%@://%@.%@", endPointURL.scheme, self.allNeededMessage.bucketName, endPointURL.host];
    }

    endPointURL = [NSURL URLWithString:urlString];
    NSString * urlHost = endPointURL.host;
    if (!self.isAccessViaProxy && [BOSUtil isBOSOriginBucketHost:urlHost] && self.isHttpdnsEnable) {
        NSString * httpdnsResolvedResult = [BOSUtil getIpByHost:urlHost];
        urlString = [NSString stringWithFormat:@"%@://%@", endPointURL.scheme, httpdnsResolvedResult];
    }

    if (self.allNeededMessage.objectKey) {
        urlString = [urlString BOS_stringByAppendingPathComponentForURL:URLENCODE(self.allNeededMessage.objectKey)];
    }

    // join query string
    if (self.allNeededMessage.querys) {
        NSMutableArray * querys = [[NSMutableArray alloc] init];
        for (NSString * key in [self.allNeededMessage.querys allKeys]) {
            NSString * value = [self.allNeededMessage.querys objectForKey:key];
            if (value) {
                if ([value isEqualToString:@""]) {
                    [querys addObject:URLENCODE(key)];
                } else {
                    [querys addObject:[NSString stringWithFormat:@"%@=%@", URLENCODE(key), URLENCODE(value)]];
                }
            }
        }
        if (querys && [querys count]) {
            NSString * queryString = [querys componentsJoinedByString:@"&"];
            urlString = [NSString stringWithFormat:@"%@?%@", urlString, queryString];
        }
    }
    BOSLogDebug(@"built full url: %@", urlString);

    NSString * headerHost = urlHost;
    if (![BOSUtil isBOSOriginBucketHost:urlHost] && self.allNeededMessage.isHostInCnameExcludeList && self.allNeededMessage.bucketName) {
        headerHost = [NSString stringWithFormat:@"%@.%@", self.allNeededMessage.bucketName, urlHost];
    }

    // set header fields
    self.internalRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];

    // override default host
    [self.internalRequest setValue:headerHost forHTTPHeaderField:@"Host"];

    if (self.allNeededMessage.httpMethod) {
        [self.internalRequest setHTTPMethod:self.allNeededMessage.httpMethod];
    }
    if (self.allNeededMessage.contentType) {
        [self.internalRequest setValue:self.allNeededMessage.contentType forHTTPHeaderField:@"Content-Type"];
    }
    if (self.allNeededMessage.contentMd5) {
        [self.internalRequest setValue:self.allNeededMessage.contentMd5 forHTTPHeaderField:@"Content-MD5"];
    }
    if (self.allNeededMessage.date) {
        [self.internalRequest setValue:self.allNeededMessage.date forHTTPHeaderField:@"Date"];
    }
    if (self.allNeededMessage.range) {
        [self.internalRequest setValue:self.allNeededMessage.range forHTTPHeaderField:@"Range"];
    }
    if (self.allNeededMessage.headerParams) {
        for (NSString * key in [self.allNeededMessage.headerParams allKeys]) {
            [self.internalRequest setValue:[self.allNeededMessage.headerParams objectForKey:key] forHTTPHeaderField:key];
        }
    }
    BOSLogVerbose(@"buidlInternalHttpRequest -\nmethod: %@\nurl: %@\nheader: %@", self.internalRequest.HTTPMethod,
                  self.internalRequest.URL, self.internalRequest.allHTTPHeaderFields);

#undef URLENCODE//(a)
    return [BOSTask taskWithResult:nil];
}
@end

@implementation BOSAllRequestNeededMessage

- (instancetype)initWithEndpoint:(NSString *)endpoint
                      httpMethod:(NSString *)httpMethod
                      bucketName:(NSString *)bucketName
                       objectKey:(NSString *)objectKey
                            type:(NSString *)contentType
                             md5:(NSString *)contentMd5
                           range:(NSString *)range
                            date:(NSString *)date
                    headerParams:(NSMutableDictionary *)headerParams
                          querys:(NSMutableDictionary *)querys {

    if (self = [super init]) {
        _endpoint = endpoint;
        _httpMethod = httpMethod;
        _bucketName = bucketName;
        _objectKey = objectKey;
        _contentType = contentType;
        _contentMd5 = contentMd5;
        _range = range;
        _date = date;
        _headerParams = headerParams;
        if (!_headerParams) {
            _headerParams = [NSMutableDictionary new];
        }
        _querys = querys;
        if (!_querys) {
            _querys = [NSMutableDictionary new];
        }
    }
    return self;
}

- (BOSTask *)validateRequestParamsInOperationType:(BOSOperationType)operType {
    NSString * errorMessage = nil;

    if (!self.endpoint) {
        errorMessage = @"Endpoint should not be nil";
    }

    if (!self.bucketName && operType != BOSOperationTypeGetService) {
        errorMessage = @"Bucket name should not be nil";
    }

    if (self.bucketName && ![BOSUtil validateBucketName:self.bucketName]) {
        errorMessage = @"Bucket name invalid";
    }

    if (!self.objectKey &&
        (operType != BOSOperationTypeGetBucket && operType != BOSOperationTypeCreateBucket
         && operType != BOSOperationTypeDeleteBucket && operType != BOSOperationTypeGetService
         && operType != BOSOperationTypeGetBucketACL)) {
        errorMessage = @"Object key should not be nil";
    }

    if (self.objectKey && ![BOSUtil validateObjectKey:self.objectKey]) {
        errorMessage = @"Object key invalid";
    }

    if (errorMessage) {
        return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                         code:BOSClientErrorCodeInvalidArgument
                                                     userInfo:@{BOSErrorMessageTOKEN: errorMessage}]];
    } else {
        return [BOSTask taskWithResult:nil];
    }
}

@end

@implementation BOSNetworking

- (instancetype)initWithConfiguration:(BOSNetworkingConfiguration *)configuration {
    if (self = [super init]) {
        self.configuration = configuration;

        NSOperationQueue * operationQueue = [NSOperationQueue new];
        NSURLSessionConfiguration * dataSessionConfig = nil;
        NSURLSessionConfiguration * uploadSessionConfig = nil;

        if (configuration.enableBackgroundTransmitService) {
            if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
                uploadSessionConfig = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:self.configuration.backgroundSessionIdentifier];
            } else {
                uploadSessionConfig = [NSURLSessionConfiguration backgroundSessionConfiguration:self.configuration.backgroundSessionIdentifier];
            }
        } else {
            uploadSessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        }
        dataSessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];

        if (configuration.timeoutIntervalForRequest > 0) {
            uploadSessionConfig.timeoutIntervalForRequest = configuration.timeoutIntervalForRequest;
            dataSessionConfig.timeoutIntervalForRequest = configuration.timeoutIntervalForRequest;
        }
        if (configuration.timeoutIntervalForResource > 0) {
            uploadSessionConfig.timeoutIntervalForResource = configuration.timeoutIntervalForResource;
            dataSessionConfig.timeoutIntervalForResource = configuration.timeoutIntervalForResource;
        }
        dataSessionConfig.URLCache = nil;
        uploadSessionConfig.URLCache = nil;
        if (configuration.proxyHost && configuration.proxyPort) {
            // Create an NSURLSessionConfiguration that uses the proxy
            NSDictionary *proxyDict = @{
                                        @"HTTPEnable"  : [NSNumber numberWithInt:1],
                                        (NSString *)kCFStreamPropertyHTTPProxyHost  : configuration.proxyHost,
                                        (NSString *)kCFStreamPropertyHTTPProxyPort  : configuration.proxyPort,

                                        @"HTTPSEnable" : [NSNumber numberWithInt:1],
                                        (NSString *)kCFStreamPropertyHTTPSProxyHost : configuration.proxyHost,
                                        (NSString *)kCFStreamPropertyHTTPSProxyPort : configuration.proxyPort,
                                        };
            dataSessionConfig.connectionProxyDictionary = proxyDict;
            uploadSessionConfig.connectionProxyDictionary = proxyDict;
        }

        _dataSession = [NSURLSession sessionWithConfiguration:dataSessionConfig
                                                 delegate:self
                                            delegateQueue:operationQueue];
        _uploadFileSession = [NSURLSession sessionWithConfiguration:uploadSessionConfig
                                                       delegate:self
                                                  delegateQueue:operationQueue];

        self.isUsingBackgroundSession = configuration.enableBackgroundTransmitService;
        _sessionDelagateManager = [BOSSyncMutableDictionary new];

        NSOperationQueue * queue = [NSOperationQueue new];
        if (configuration.maxConcurrentRequestCount) {
            queue.maxConcurrentOperationCount = configuration.maxConcurrentRequestCount;
        }
        self.taskExecutor = [BOSExecutor executorWithOperationQueue:queue];
    }
    return self;
}

- (BOSTask *)sendRequest:(BOSNetworkingRequestDelegate *)request {
    BOSLogVerbose(@"send request --------");
    if (self.configuration.proxyHost && self.configuration.proxyPort) {
        request.isAccessViaProxy = YES;
    }

    /* set maximum retry */
    request.retryHandler.maxRetryCount = self.configuration.maxRetryCount;

    BOSTaskCompletionSource * taskCompletionSource = [BOSTaskCompletionSource taskCompletionSource];

    __weak BOSNetworkingRequestDelegate * ref = request;
    request.completionHandler = ^(id responseObject, NSError * error) {

        [ref reset];
        if (!error) {
            [taskCompletionSource setResult:responseObject];
        } else {
            [taskCompletionSource setError:error];
        }
    };
    [self dataTaskWithDelegate:request];
    return taskCompletionSource.task;
}

- (void)dataTaskWithDelegate:(BOSNetworkingRequestDelegate *)requestDelegate {

    [[[[[BOSTask taskWithResult:nil] continueWithExecutor:self.taskExecutor withSuccessBlock:^id(BOSTask *task) {
        BOSLogVerbose(@"start to intercept request");
        for (id<BOSRequestInterceptor> interceptor in requestDelegate.interceptors) {
            task = [interceptor interceptRequestMessage:requestDelegate.allNeededMessage];
            if (task.error) {
                return task;
            }
        }
        return task;
    }] continueWithSuccessBlock:^id(BOSTask *task) {
        return [requestDelegate buildInternalHttpRequest];
    }] continueWithSuccessBlock:^id(BOSTask *task) {
        NSURLSessionDataTask * sessionTask = nil;
        if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0 && self.configuration.timeoutIntervalForRequest > 0) {
            requestDelegate.internalRequest.timeoutInterval = self.configuration.timeoutIntervalForRequest;
        }

        if (requestDelegate.uploadingData) {
            [requestDelegate.internalRequest setHTTPBody:requestDelegate.uploadingData];
            sessionTask = [_dataSession dataTaskWithRequest:requestDelegate.internalRequest];
        } else if (requestDelegate.uploadingFileURL) {
            sessionTask = [_uploadFileSession uploadTaskWithRequest:requestDelegate.internalRequest fromFile:requestDelegate.uploadingFileURL];

            if (self.isUsingBackgroundSession) {
                requestDelegate.isBackgroundUploadFileTask = YES;
            }
        } else { // not upload request
            sessionTask = [_dataSession dataTaskWithRequest:requestDelegate.internalRequest];
        }

        requestDelegate.currentSessionTask = sessionTask;
        requestDelegate.httpRequestNotSuccessResponseBody = [NSMutableData new];
        [self.sessionDelagateManager setObject:requestDelegate forKey:@(sessionTask.taskIdentifier)];
        if (requestDelegate.isRequestCancelled) {
            return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                              code:BOSClientErrorCodeTaskCancelled
                                                          userInfo:nil]];
        }
        [sessionTask resume];

        return task;
    }] continueWithBlock:^id(BOSTask *task) {

        // if error occurs before created sessionTask
        if (task.error) {
            requestDelegate.completionHandler(nil, task.error);
        } else if (task.isFaulted) {
            requestDelegate.completionHandler(nil, [NSError errorWithDomain:BOSClientErrorDomain
                                                                       code:BOSClientErrorCodeExcpetionCatched
                                                                   userInfo:@{BOSErrorMessageTOKEN: [NSString stringWithFormat:@"Catch exception - %@", task.exception]}]);
        }
        return nil;
    }];
}

#pragma mark - delegate method

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)sessionTask didCompleteWithError:(NSError *)error {
    BOSNetworkingRequestDelegate * delegate = [self.sessionDelagateManager objectForKey:@(sessionTask.taskIdentifier)];
    [self.sessionDelagateManager removeObjectForKey:@(sessionTask.taskIdentifier)];

    NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *)sessionTask.response;
    if (delegate == nil) {
        BOSLogVerbose(@"delegate: %@", delegate);
        /* if the background transfer service is enable, may recieve the previous task complete callback */
        /* for now, we ignore it */
        return ;
    }

    /* background upload task will not call back didRecieveResponse */
    if (delegate.isBackgroundUploadFileTask) {
        BOSLogVerbose(@"backgroud upload task did recieve response: %@", httpResponse);
        if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 && httpResponse.statusCode != 203) {
            [delegate.responseParser consumeHttpResponse:httpResponse];
        } else {
            delegate.isHttpRequestNotSuccessResponse = YES;
        }
    }

    [[[[BOSTask taskWithResult:nil] continueWithSuccessBlock:^id(BOSTask * task) {
        if (!delegate.error) {
            delegate.error = error;
        }
        if (delegate.error) {
            BOSLogDebug(@"networking request completed with error: %@", error);
            if ([delegate.error.domain isEqualToString:NSURLErrorDomain] && delegate.error.code == NSURLErrorCancelled) {
                return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                                 code:BOSClientErrorCodeTaskCancelled
                                                             userInfo:[error userInfo]]];
            } else {
                NSMutableDictionary * userInfo = [NSMutableDictionary dictionaryWithDictionary:[error userInfo]];
                [userInfo setObject:[NSString stringWithFormat:@"%ld", (long)error.code] forKey:@"OriginErrorCode"];
                return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                                 code:BOSClientErrorCodeNetworkError
                                                             userInfo:userInfo]];
            }
        }
        return task;
    }] continueWithSuccessBlock:^id(BOSTask *task) {
        if (delegate.isHttpRequestNotSuccessResponse) {
            if (httpResponse.statusCode == 0) {
                return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                                 code:BOSClientErrorCodeNetworkingFailWithResponseCode0
                                                             userInfo:@{BOSErrorMessageTOKEN: @"Request failed, response code 0"}]];
            }
            NSString * notSuccessResponseBody = [[NSString alloc] initWithData:delegate.httpRequestNotSuccessResponseBody encoding:NSUTF8StringEncoding];
            BOSLogError(@"http error response: %@", notSuccessResponseBody);
            NSDictionary * dict = [NSDictionary dictionaryWithXMLString:notSuccessResponseBody];

            return [BOSTask taskWithError:[NSError errorWithDomain:BOSServerErrorDomain
                                                             code:(-1 * httpResponse.statusCode)
                                                         userInfo:dict]];
        }
        return task;
    }] continueWithBlock:^id(BOSTask *task) {
        if (task.error) {
            BOSNetworkingRetryType retryType = [delegate.retryHandler shouldRetry:delegate.currentRetryCount
                                                                  requestDelegate:delegate
                                                                         response:httpResponse
                                                                            error:task.error];
            BOSLogVerbose(@"current retry count: %u, retry type: %d", delegate.currentRetryCount, (int)retryType);

            switch (retryType) {

                case BOSNetworkingRetryTypeShouldNotRetry: {
                    delegate.completionHandler(nil, task.error);
                    return nil;
                }

                case BOSNetworkingRetryTypeShouldCorrectClockSkewAndRetry: {
                    /* correct clock skew */
                    NSString * dateStr = [[httpResponse allHeaderFields] objectForKey:@"Date"];
                    if ([dateStr length]) {
                        NSDate * serverTime = [NSDate BOS_dateFromString:dateStr];
                        NSDate * deviceTime = [NSDate date];
                        NSTimeInterval skewTime = [deviceTime timeIntervalSinceDate:serverTime];
                        [NSDate BOS_setClockSkew:skewTime];
                        [delegate.interceptors insertObject:[BOSTimeSkewedFixingInterceptor new] atIndex:0];
                    } else {
                        BOSLogError(@"date header does not exist, unable to fix the time skew");
                        delegate.completionHandler(nil, task.error);
                        return nil;
                    }
                }

                default:
                    break;
            }

            /* now, should retry */
            NSTimeInterval suspendTime = [delegate.retryHandler timeIntervalForRetry:delegate.currentRetryCount retryType:retryType];
            delegate.currentRetryCount++;
            [NSThread sleepForTimeInterval:suspendTime];

            /* retry recursively */
            [delegate reset];
            [self dataTaskWithDelegate:delegate];
        } else {
            delegate.completionHandler([delegate.responseParser constructResultObject], nil);
        }
        return nil;
    }];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    BOSNetworkingRequestDelegate * delegate = [self.sessionDelagateManager objectForKey:@(task.taskIdentifier)];
    if (delegate.uploadProgress) {
        delegate.uploadProgress(bytesSent, totalBytesSent, totalBytesExpectedToSend);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    BOSNetworkingRequestDelegate * delegate = [self.sessionDelagateManager objectForKey:@(dataTask.taskIdentifier)];

    /* background upload task will not call back didRecieveResponse */
    BOSLogVerbose(@"did receive response: %@", response);
    NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *)response;
    if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 && httpResponse.statusCode != 203) {
        [delegate.responseParser consumeHttpResponse:httpResponse];
    } else {
        delegate.isHttpRequestNotSuccessResponse = YES;
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    BOSNetworkingRequestDelegate * delegate = [self.sessionDelagateManager objectForKey:@(dataTask.taskIdentifier)];

    /* background upload task will not call back didRecieveResponse.
       so if we recieve response data after background uploading file,
       we consider it as error response message since a successful uploading request will not response any data */
    if (delegate.isHttpRequestNotSuccessResponse || delegate.isBackgroundUploadFileTask) {
        [delegate.httpRequestNotSuccessResponseBody appendData:data];
    } else {
        if (delegate.onRecieveData) {
            delegate.onRecieveData(data);
        } else {
            BOSTask * consumeTask = [delegate.responseParser consumeHttpResponseBody:data];
            if (consumeTask.error) {
                BOSLogError(@"consume data error: %@", consumeTask.error);
                delegate.error = consumeTask.error;
                [dataTask cancel];
            }
        }
    }

    if (!delegate.isHttpRequestNotSuccessResponse && delegate.downloadProgress) {
        int64_t bytesWritten = [data length];
        delegate.payloadTotalBytesWritten += bytesWritten;
        int64_t totalBytesExpectedToWrite = dataTask.response.expectedContentLength;
        delegate.downloadProgress(bytesWritten, delegate.payloadTotalBytesWritten, totalBytesExpectedToWrite);
    }
}

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(NSString *)domain {
    /*
     * 创建证书校验策略
     */
    NSMutableArray *policies = [NSMutableArray array];
    if (domain) {
        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
    } else {
        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
    }

    /*
     * 绑定校验策略到服务端的证书上
     */
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);


    /*
     * 评估当前serverTrust是否可信任，
     * 官方建议在result = kSecTrustResultUnspecified 或 kSecTrustResultProceed
     * 的情况下serverTrust可以被验证通过，https://developer.apple.com/library/ios/technotes/tn2232/_index.html
     * 关于SecTrustResultType的详细信息请参考SecTrust.h
     */
    SecTrustResultType result;
    SecTrustEvaluate(serverTrust, &result);

    return (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
}

/*
 * NSURLSession
 */
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * __nullable credential))completionHandler {
    if (!challenge) {
        return;
    }

    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    NSURLCredential *credential = nil;

    /*
     * 获取原始域名信息。
     */

    NSString * host = [[task.currentRequest allHTTPHeaderFields] objectForKey:@"Host"];
    if (!host) {
        host = task.currentRequest.URL.host;
    }

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([self evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:host]) {
            disposition = NSURLSessionAuthChallengeUseCredential;
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        }
    } else {
        disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    }
    // 对于其他的challenges直接使用默认的验证方案
    completionHandler(disposition,credential);
}
@end