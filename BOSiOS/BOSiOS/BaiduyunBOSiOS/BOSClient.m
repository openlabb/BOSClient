//
//  BOSClient.m
//  BOS_ios_sdk
//
//  Created by zhouzhuo on 8/16/15.
//  Copyright (c) 2015 baiduyun.com. All rights reserved.
//

#import "BOSClient.h"
#import "BOSDefine.h"
#import "BOSModel.h"
#import "BOSUtil.h"
#import "BOSLog.h"
#import "BOSBolts.h"
#import "BOSNetworking.h"
#import "BOSXMLDictionary.h"
#import "BOSReachabilityManager.h"

/**
 * extend BOSRequest to include the ref to networking request object
 */
@interface BOSRequest ()
@property (nonatomic, strong) BOSNetworkingRequestDelegate * requestDelegate;
@end



@implementation BOSClient

- (instancetype)initWithEndpoint:(NSString *)endpoint credentialProvider:(id<BOSCredentialProvider>)credentialProvider {
    return [self initWithEndpoint:endpoint credentialProvider:credentialProvider clientConfiguration:[BOSClientConfiguration new]];
}

- (instancetype)initWithEndpoint:(NSString *)endpoint
              credentialProvider:(id<BOSCredentialProvider>)credentialProvider
             clientConfiguration:(BOSClientConfiguration *)conf {
    if (self = [super init]) {

        // 监听网络，网络类型变化时，重新判定ipv6情况
        [BOSReachabilityManager shareInstance];

        NSOperationQueue * queue = [NSOperationQueue new];
        // using for resumable upload and compat old interface
        queue.maxConcurrentOperationCount = 3;
        _BOSOperationExecutor = [BOSExecutor executorWithOperationQueue:queue];
        if ([endpoint rangeOfString:@"://"].location == NSNotFound) {
            endpoint = [@"http://" stringByAppendingString:endpoint];
        }
        self.endpoint = [endpoint BOS_trim];
        self.credentialProvider = credentialProvider;
        self.clientConfiguration = conf;

        BOSNetworkingConfiguration * netConf = [BOSNetworkingConfiguration new];
        if (conf) {
            netConf.maxRetryCount = conf.maxRetryCount;
            netConf.timeoutIntervalForRequest = conf.timeoutIntervalForRequest;
            netConf.timeoutIntervalForResource = conf.timeoutIntervalForResource;
            netConf.enableBackgroundTransmitService = conf.enableBackgroundTransmitService;
            netConf.backgroundSessionIdentifier = conf.backgroundSesseionIdentifier;
            netConf.proxyHost = conf.proxyHost;
            netConf.proxyPort = conf.proxyPort;
            netConf.maxConcurrentRequestCount = conf.maxConcurrentRequestCount;
        }
        self.networking = [[BOSNetworking alloc] initWithConfiguration:netConf];
    }
    return self;
}

- (BOSTask *)invokeRequest:(BOSNetworkingRequestDelegate *)request requireAuthentication:(BOOL)requireAuthentication {
    /* if content-type haven't been set, we set one */
    if ((!request.allNeededMessage.contentType
         || [[request.allNeededMessage.contentType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                                                                                                        isEqualToString:@""])
        && ([request.allNeededMessage.httpMethod isEqualToString:@"POST"] || [request.allNeededMessage.httpMethod isEqualToString:@"PUT"])) {

        request.allNeededMessage.contentType = [BOSUtil detemineMimeTypeForFilePath:request.uploadingFileURL.path
                                                                         uploadName:request.allNeededMessage.objectKey];
    }

//    // 检查endpoint是否在cname排除列表中
//    if ([self.clientConfiguration.cnameExcludeList count] > 0) {
//        [self.clientConfiguration.cnameExcludeList enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
//            NSString * exclude = obj;
//            if ([self.endpoint hasSuffix:exclude]) {
//                request.allNeededMessage.isHostInCnameExcludeList = true;
//                *stop = true;
//            }
//        }];
//    }
//
//    id<BOSRequestInterceptor> uaSetting = [BOSUASettingInterceptor new];
//    [request.interceptors addObject:uaSetting];

    /* check if the authentication is required */
    if (requireAuthentication) {
        id<BOSRequestInterceptor> signer = [[BOSSignerInterceptor alloc] initWithCredentialProvider:self.credentialProvider];
        [request.interceptors addObject:signer];
    }

    request.isHttpdnsEnable = self.clientConfiguration.isHttpdnsEnable;

    return [_networking sendRequest:request];
}

#pragma implement restful apis

- (BOSTask *)getService:(BOSGetServiceRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;

    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeGetService];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"GET"
                                                bucketName:nil
                                                 objectKey:nil
                                                      type:nil
                                                       md5:nil
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:nil
                                                    querys:[request getQueryDict]];
    requestDelegate.operType = BOSOperationTypeGetService;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)createBucket:(BOSCreateBucketRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;
    NSMutableDictionary * headerParams = nil;
    if (request.xBOSACL) {
        headerParams = [NSMutableDictionary dictionaryWithObjectsAndKeys:request.xBOSACL, @"x-BOS-acl", nil];
    }
    if (request.location) {
        requestDelegate.uploadingData = [BOSUtil constructHttpBodyForCreateBucketWithLocation:request.location];
    }

    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeCreateBucket];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"PUT"
                                                bucketName:request.bucketName
                                                 objectKey:nil
                                                      type:nil
                                                       md5:nil
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:headerParams
                                                    querys:nil];
    requestDelegate.operType = BOSOperationTypeCreateBucket;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)deleteBucket:(BOSDeleteObjectRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;

    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeDeleteBucket];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"DELETE"
                                                bucketName:request.bucketName
                                                 objectKey:nil
                                                      type:nil
                                                       md5:nil
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:nil
                                                    querys:nil];
    requestDelegate.operType = BOSOperationTypeDeleteBucket;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)getBucket:(BOSGetBucketRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;

    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeGetBucket];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"GET"
                                                bucketName:request.bucketName
                                                 objectKey:nil
                                                      type:nil
                                                       md5:nil
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:nil
                                                    querys:[request getQueryDict]];
    requestDelegate.operType = BOSOperationTypeGetBucket;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)getBucketACL:(BOSGetBucketACLRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;

    NSMutableDictionary * query = [NSMutableDictionary dictionaryWithObject:@"" forKey:@"acl"];
    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeGetBucketACL];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"GET"
                                                bucketName:request.bucketName
                                                 objectKey:nil
                                                      type:nil
                                                       md5:nil
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:nil
                                                    querys:query];
    requestDelegate.operType = BOSOperationTypeGetBucketACL;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)headObject:(BOSHeadObjectRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;

    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeHeadObject];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"HEAD"
                                                bucketName:request.bucketName
                                                 objectKey:request.objectKey
                                                      type:nil
                                                       md5:nil
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:nil
                                                    querys:nil];
    requestDelegate.operType = BOSOperationTypeHeadObject;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)getObject:(BOSGetObjectRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;

    NSString * rangeString = nil;
    if (request.range) {
        rangeString = [request.range toHeaderString];
    }
    if (request.downloadProgress) {
        requestDelegate.downloadProgress = request.downloadProgress;
    }
    if (request.onRecieveData) {
        requestDelegate.onRecieveData = request.onRecieveData;
    }
    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeGetObject];
    requestDelegate.responseParser.downloadingFileURL = request.downloadToFileURL;
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"GET"
                                                bucketName:request.bucketName
                                                 objectKey:request.objectKey
                                                      type:nil
                                                       md5:nil
                                                     range:rangeString
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:nil
                                                    querys:nil];
    requestDelegate.operType = BOSOperationTypeGetObject;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)putObject:(BOSPutObjectRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;
    NSMutableDictionary * headerParams = [NSMutableDictionary dictionaryWithDictionary:request.objectMeta];

    if (request.uploadingData) {
        requestDelegate.uploadingData = request.uploadingData;
    }
    if (request.uploadingFileURL) {
        requestDelegate.uploadingFileURL = request.uploadingFileURL;
    }
//    if (request.callbackParam) {
//        [headerParams setObject:[request.callbackParam base64JsonString] forKey:BOSHttpHeaderXBOSCallback];
//    }
//    if (request.callbackVar) {
//        [headerParams setObject:[request.callbackVar base64JsonString] forKey:BOSHttpHeaderXBOSCallbackVar];
//    }
    if (request.uploadProgress) {
        requestDelegate.uploadProgress = request.uploadProgress;
    }
//    if (request.contentDisposition) {
//        [headerParams setObject:request.contentDisposition forKey:BOSHttpHeaderContentDisposition];
//    }
//    if (request.contentEncoding) {
//        [headerParams setObject:request.contentEncoding forKey:BOSHttpHeaderContentEncoding];
//    }
//    if (request.expires) {
//        [headerParams setObject:request.expires forKey:BOSHttpHeaderExpires];
//    }
//    if (request.cacheControl) {
//        [headerParams setObject:request.cacheControl forKey:BOSHttpHeaderCacheControl];
//    }
    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypePutObject];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"PUT"
                                                bucketName:request.bucketName
                                                 objectKey:request.objectKey
                                                      type:request.contentType
                                                       md5:request.contentMd5
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:headerParams
                                                    querys:nil];
    requestDelegate.operType = BOSOperationTypePutObject;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)putObjectACL:(BOSPutObjectACLRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;
    NSMutableDictionary * headerParams = [NSMutableDictionary dictionary];
    if (request.acl) {
        headerParams[@"x-BOS-object-acl"] = request.acl;
    } else {
        headerParams[@"x-BOS-object-acl"] = @"default";
    }

    NSMutableDictionary * querys = [NSMutableDictionary dictionaryWithObject:@"" forKey:@"acl"];

    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypePutObjectACL];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"PUT"
                                                bucketName:request.bucketName
                                                 objectKey:request.objectKey
                                                      type:nil
                                                       md5:nil
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:headerParams
                                                    querys:querys];
    requestDelegate.operType = BOSOperationTypePutObjectACL;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)appendObject:(BOSAppendObjectRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;
    NSMutableDictionary * headerParams = [NSMutableDictionary dictionaryWithDictionary:request.objectMeta];

    if (request.uploadingData) {
        requestDelegate.uploadingData = request.uploadingData;
    }
    if (request.uploadingFileURL) {
        requestDelegate.uploadingFileURL = request.uploadingFileURL;
    }
    if (request.uploadProgress) {
        requestDelegate.uploadProgress = request.uploadProgress;
    }
    if (request.contentDisposition) {
        [headerParams setObject:request.contentDisposition forKey:BOSHttpHeaderContentDisposition];
    }
    if (request.contentEncoding) {
        [headerParams setObject:request.contentEncoding forKey:BOSHttpHeaderContentEncoding];
    }
    if (request.expires) {
        [headerParams setObject:request.expires forKey:BOSHttpHeaderExpires];
    }
    if (request.cacheControl) {
        [headerParams setObject:request.cacheControl forKey:BOSHttpHeaderCacheControl];
    }
    NSMutableDictionary * querys = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"", @"append",
                                    [@(request.appendPosition) stringValue], @"position", nil];
    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeAppendObject];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"POST"
                                                bucketName:request.bucketName
                                                 objectKey:request.objectKey
                                                      type:request.contentType
                                                       md5:request.contentMd5
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:headerParams
                                                    querys:querys];
    requestDelegate.operType = BOSOperationTypeAppendObject;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)deleteObject:(BOSDeleteObjectRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;

    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypePutObject];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"DELETE"
                                                bucketName:request.bucketName
                                                 objectKey:request.objectKey
                                                      type:nil
                                                       md5:nil
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:nil
                                                    querys:nil];
    requestDelegate.operType = BOSOperationTypeDeleteObject;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)copyObject:(BOSCopyObjectRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;
    NSMutableDictionary * headerParams = [NSMutableDictionary dictionaryWithDictionary:request.objectMeta];

    if (request.sourceCopyFrom) {
        [headerParams setObject:request.sourceCopyFrom forKey:@"x-BOS-copy-source"];
    }
    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeCopyObject];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"PUT"
                                                bucketName:request.bucketName
                                                 objectKey:request.objectKey
                                                      type:request.contentType
                                                       md5:request.contentMd5
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:headerParams
                                                    querys:nil];
    requestDelegate.operType = BOSOperationTypeCopyObject;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)multipartUploadInit:(BOSInitMultipartUploadRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;
    NSMutableDictionary * headerParams = [NSMutableDictionary dictionaryWithDictionary:request.objectMeta];

    if (request.contentDisposition) {
        [headerParams setObject:request.contentDisposition forKey:BOSHttpHeaderContentDisposition];
    }
    if (request.contentEncoding) {
        [headerParams setObject:request.contentEncoding forKey:BOSHttpHeaderContentEncoding];
    }
    if (request.expires) {
        [headerParams setObject:request.expires forKey:BOSHttpHeaderExpires];
    }
    if (request.cacheControl) {
        [headerParams setObject:request.cacheControl forKey:BOSHttpHeaderCacheControl];
    }
    NSMutableDictionary * querys = [NSMutableDictionary dictionaryWithObject:@"" forKey:@"uploads"];
    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeInitMultipartUpload];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"POST"
                                                bucketName:request.bucketName
                                                 objectKey:request.objectKey
                                                      type:request.contentType
                                                       md5:nil
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:headerParams
                                                    querys:querys];
    requestDelegate.operType = BOSOperationTypeInitMultipartUpload;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)uploadPart:(BOSUploadPartRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;

    NSMutableDictionary * querys = [NSMutableDictionary dictionaryWithObjectsAndKeys:[@(request.partNumber) stringValue], @"partNumber",
                                    request.uploadId, @"uploadId", nil];
    if (request.uploadPartData) {
        requestDelegate.uploadingData = request.uploadPartData;
    }
    if (request.uploadPartFileURL) {
        requestDelegate.uploadingFileURL = request.uploadPartFileURL;
    }
    if (request.uploadPartProgress) {
        requestDelegate.uploadProgress = request.uploadPartProgress;
    }
    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeUploadPart];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"PUT"
                                                bucketName:request.bucketName
                                                 objectKey:request.objectkey
                                                      type:nil
                                                       md5:request.contentMd5
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:nil
                                                    querys:querys];
    requestDelegate.operType = BOSOperationTypeUploadPart;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)completeMultipartUpload:(BOSCompleteMultipartUploadRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;
    NSMutableDictionary * headerParams = [NSMutableDictionary dictionary];
    if (request.partInfos) {
        requestDelegate.uploadingData = [BOSUtil constructHttpBodyFromPartInfos:request.partInfos];
    }
    if (request.callbackParam) {
        [headerParams setObject:[request.callbackParam base64JsonString] forKey:BOSHttpHeaderXBOSCallback];
    }
    if (request.callbackVar) {
        [headerParams setObject:[request.callbackVar base64JsonString] forKey:BOSHttpHeaderXBOSCallbackVar];
    }
    if (request.completeMetaHeader) {
        [headerParams addEntriesFromDictionary:request.completeMetaHeader];
    }
    NSMutableDictionary * querys = [NSMutableDictionary dictionaryWithObjectsAndKeys:request.uploadId, @"uploadId", nil];
    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeCompleteMultipartUpload];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"POST"
                                                bucketName:request.bucketName
                                                 objectKey:request.objectKey
                                                      type:nil
                                                       md5:request.contentMd5
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:headerParams
                                                    querys:querys];
    requestDelegate.operType = BOSOperationTypeCompleteMultipartUpload;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)listParts:(BOSListPartsRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;

    NSMutableDictionary * querys = [NSMutableDictionary dictionaryWithObjectsAndKeys:request.uploadId, @"uploadId", nil];
    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeListMultipart];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"GET"
                                                bucketName:request.bucketName
                                                 objectKey:request.objectKey
                                                      type:nil
                                                       md5:nil
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:nil
                                                    querys:querys];
    requestDelegate.operType = BOSOperationTypeListMultipart;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)abortMultipartUpload:(BOSAbortMultipartUploadRequest *)request {
    BOSNetworkingRequestDelegate * requestDelegate = request.requestDelegate;

    NSMutableDictionary * querys = [NSMutableDictionary dictionaryWithObjectsAndKeys:request.uploadId, @"uploadId", nil];
    requestDelegate.responseParser = [[BOSHttpResponseParser alloc] initForOperationType:BOSOperationTypeAbortMultipartUpload];
    requestDelegate.allNeededMessage = [[BOSAllRequestNeededMessage alloc] initWithEndpoint:self.endpoint
                                                httpMethod:@"DELETE"
                                                bucketName:request.bucketName
                                                 objectKey:request.objectKey
                                                      type:nil
                                                       md5:nil
                                                     range:nil
                                                      date:[[NSDate BOS_clockSkewFixedDate] BOS_asStringValue]
                                              headerParams:nil
                                                    querys:querys];
    requestDelegate.operType = BOSOperationTypeAbortMultipartUpload;

    return [self invokeRequest:requestDelegate requireAuthentication:request.isAuthenticationRequired];
}

- (BOSTask *)presignConstrainURLWithBucketName:(NSString *)bucketName
                                 withObjectKey:(NSString *)objectKey
                        withExpirationInterval:(NSTimeInterval)interval {

    return [[BOSTask taskWithResult:nil] continueWithBlock:^id(BOSTask *task) {
        NSString * resource = [NSString stringWithFormat:@"/%@/%@", bucketName, objectKey];
        NSString * expires = [@((int64_t)[[NSDate BOS_clockSkewFixedDate] timeIntervalSince1970] + interval) stringValue];
        NSString * wholeSign = nil;
        BOSFederationToken * token = nil;
        NSError * error = nil;

        if ([self.credentialProvider isKindOfClass:[BOSFederationCredentialProvider class]]) {
            token = [(BOSFederationCredentialProvider *)self.credentialProvider getToken:&error];
            if (error) {
                return [BOSTask taskWithError:error];
            }
        } else if ([self.credentialProvider isKindOfClass:[BOSStsTokenCredentialProvider class]]) {
            token = [(BOSStsTokenCredentialProvider *)self.credentialProvider getToken];
        }

        if ([self.credentialProvider isKindOfClass:[BOSFederationCredentialProvider class]]
            || [self.credentialProvider isKindOfClass:[BOSStsTokenCredentialProvider class]]) {
            resource = [NSString stringWithFormat:@"%@?security-token=%@", resource, token.tToken];
            NSString * string2sign = [NSString stringWithFormat:@"GET\n\n\n%@\n%@", expires, resource];
            wholeSign = [BOSUtil sign:string2sign withToken:token];
        } else {
            NSString * string2sign = [NSString stringWithFormat:@"GET\n\n\n%@\n%@", expires, resource];
            wholeSign = [self.credentialProvider sign:string2sign error:&error];
            if (error) {
                return [BOSTask taskWithError:error];
            }
        }

        NSArray * splitResult = [wholeSign componentsSeparatedByString:@":"];
        if ([splitResult count] != 2
            || ![((NSString *)[splitResult objectAtIndex:0]) hasPrefix:@"BOS "]) {
            return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                             code:BOSClientErrorCodeSignFailed
                                                         userInfo:@{BOSErrorMessageTOKEN: @"the returned signature is invalid"}]];
        }
        NSString * accessKey = [(NSString *)[splitResult objectAtIndex:0] substringFromIndex:4];
        NSString * signature = [splitResult objectAtIndex:1];

        NSURL * endpointURL = [NSURL URLWithString:self.endpoint];
        NSString * host = endpointURL.host;
        if ([BOSUtil isBOSOriginBucketHost:host]) {
            host = [NSString stringWithFormat:@"%@.%@", bucketName, host];
        }
        NSString * stringURL = [NSString stringWithFormat:@"%@://%@/%@?BOSAccessKeyId=%@&Expires=%@&Signature=%@",
                                endpointURL.scheme,
                                host,
                                [BOSUtil encodeURL:objectKey],
                                [BOSUtil encodeURL:accessKey],
                                expires,
                                [BOSUtil encodeURL:signature]];

        if ([self.credentialProvider isKindOfClass:[BOSFederationCredentialProvider class]]
            || [self.credentialProvider isKindOfClass:[BOSStsTokenCredentialProvider class]]) {
            stringURL = [NSString stringWithFormat:@"%@&security-token=%@", stringURL, [BOSUtil encodeURL:token.tToken]];
        }
        return [BOSTask taskWithResult:stringURL];
    }];
}

- (BOSTask *)presignPublicURLWithBucketName:(NSString *)bucketName
                             withObjectKey:(NSString *)objectKey {

    return [[BOSTask taskWithResult:nil] continueWithBlock:^id(BOSTask *task) {
        NSURL * endpointURL = [NSURL URLWithString:self.endpoint];
        NSString * host = endpointURL.host;
        if ([BOSUtil isBOSOriginBucketHost:host]) {
            host = [NSString stringWithFormat:@"%@.%@", bucketName, host];
        }
        NSString * stringURL = [NSString stringWithFormat:@"%@://%@/%@",
                                endpointURL.scheme,
                                host,
                                [BOSUtil encodeURL:objectKey]];
        return [BOSTask taskWithResult:stringURL];
    }];
}

- (BOSTask *)resumableUpload:(BOSResumableUploadRequest *)request {

    __block int64_t uploadedLength = 0;
    __block int64_t expectedUploadLength = 0;
    __block int partCount;

    return [[BOSTask taskWithResult:nil] continueWithExecutor:self.BOSOperationExecutor withBlock:^id(BOSTask *task) {
        if (!request.uploadId || !request.objectKey || !request.bucketName || !request.uploadingFileURL) {
            return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                             code:BOSClientErrorCodeInvalidArgument
                                                         userInfo:@{BOSErrorMessageTOKEN: @"ResumableUpload requires uploadId/bucketName/objectKey/uploadingFile."}]];
        }
        if (request.partSize < 100 * 1024) {
            return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                             code:BOSClientErrorCodeInvalidArgument
                                                         userInfo:@{BOSErrorMessageTOKEN: @"Part size must be set bigger than 100KB"}]];
        }

        static dispatch_once_t onceToken;
        static NSError * cancelError;
        dispatch_once(&onceToken, ^{
            cancelError = [NSError errorWithDomain:BOSClientErrorDomain
                                              code:BOSClientErrorCodeTaskCancelled
                                          userInfo:@{BOSErrorMessageTOKEN: @"This task is cancelled!"}];
        });

        NSFileManager * fm = [NSFileManager defaultManager];
        NSError * error = nil;;
        int64_t uploadFileSize = [[[fm attributesOfItemAtPath:[request.uploadingFileURL path] error:&error] objectForKey:NSFileSize] longLongValue];
        expectedUploadLength = uploadFileSize;
        if (error) {
            return [BOSTask taskWithError:error];
        }
        partCount = (int)(expectedUploadLength / request.partSize) + (expectedUploadLength % request.partSize != 0);
        NSArray * uploadedPart = nil;

        BOSListPartsRequest * listParts = [BOSListPartsRequest new];
        listParts.bucketName = request.bucketName;
        listParts.objectKey = request.objectKey;
        listParts.uploadId = request.uploadId;
        BOSTask * listPartsTask = [self listParts:listParts];
        [listPartsTask waitUntilFinished];

        if (listPartsTask.error) {
            if ([listPartsTask.error.domain isEqualToString: BOSServerErrorDomain] && listPartsTask.error.code == -1 * 404) {
                BOSLogVerbose(@"local record existes but the remote record is deleted");
                return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                                 code:BOSClientErrorCodeCannotResumeUpload
                                                             userInfo:@{BOSErrorMessageTOKEN: @"This uploadid is no long exist on server side, can not resume"}]];
            } else {
                return listPartsTask;
            }
        } else {
            BOSListPartsResult * result = listPartsTask.result;
            uploadedPart = result.parts;
            __block int64_t firstPartSize = -1;
            [uploadedPart enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSDictionary * part = obj;
                uploadedLength += [[part objectForKey:BOSSizeXMLTOKEN] longLongValue];
                if (idx == 0) {
                    firstPartSize = [[part objectForKey:BOSSizeXMLTOKEN] longLongValue];
                }
            }];
            if (expectedUploadLength < uploadedLength) {
                return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                                 code:BOSClientErrorCodeCannotResumeUpload
                                                             userInfo:@{BOSErrorMessageTOKEN: @"The uploading file is inconsistent with before"}]];
            } else if (firstPartSize != -1 && firstPartSize != request.partSize && expectedUploadLength != firstPartSize) {
                return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                                 code:BOSClientErrorCodeCannotResumeUpload
                                                             userInfo:@{BOSErrorMessageTOKEN: @"The part size setting is inconsistent with before"}]];
            }
        }

        if (request.isCancelled) {
            return [BOSTask taskWithError:cancelError];
        }

        NSMutableArray * alreadyUploadPart = [NSMutableArray new];
        NSMutableArray * alreadyUploadIndex = [NSMutableArray new];
        [uploadedPart enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary * part = obj;
            BOSPartInfo * partInfo = [BOSPartInfo partInfoWithPartNum:[[part objectForKey:BOSPartNumberXMLTOKEN] intValue]
                                                                 eTag:[part objectForKey:BOSETagXMLTOKEN]
                                                                 size:[[part objectForKey:BOSSizeXMLTOKEN] longLongValue]];
            [alreadyUploadPart addObject:partInfo];
            [alreadyUploadIndex addObject:@(partInfo.partNum)];
        }];

        NSFileHandle * handle = [NSFileHandle fileHandleForReadingAtPath:[request.uploadingFileURL path]];

        if (request.uploadProgress && expectedUploadLength) {
            request.uploadProgress(0, uploadedLength, expectedUploadLength);
        }

        for (int i = 1; i <= partCount; i++) {
            @autoreleasepool {
                if ([alreadyUploadIndex containsObject:@(i)]) {
                    continue;
                }

                [handle seekToFileOffset:uploadedLength];
                int64_t readLength = MIN(request.partSize, uploadFileSize - (request.partSize * (i-1)));

                BOSUploadPartRequest * uploadPart = [BOSUploadPartRequest new];
                NSData * uploadPartData = [handle readDataOfLength:(NSUInteger)readLength];
                uploadPart.bucketName = request.bucketName;
                uploadPart.objectkey = request.objectKey;
                uploadPart.partNumber = i;
                uploadPart.uploadId = request.uploadId;
                uploadPart.uploadPartData = uploadPartData;
                uploadPart.contentMd5 = [BOSUtil base64Md5ForData:uploadPartData];

                // 分块可能会重试，为了不扰乱进度，重试时进度不重置
                int64_t lastSuccessProgress = uploadedLength;
                uploadPart.uploadPartProgress = ^(int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
                    int64_t currentProgress = uploadedLength + totalBytesSent;
                    if (currentProgress > lastSuccessProgress) {
                        request.uploadProgress(bytesSent, currentProgress, expectedUploadLength);
                    }
                };
                BOSTask * uploadPartTask = [self uploadPart:uploadPart];
                [uploadPartTask waitUntilFinished];
                if (uploadPartTask.error) {
                    return uploadPartTask;
                } else {
                    BOSUploadPartResult * result = uploadPartTask.result;
                    BOSPartInfo * partInfo = [BOSPartInfo new];
                    partInfo.partNum = i;
                    partInfo.eTag = result.eTag;
                    [alreadyUploadPart addObject:partInfo];

                    uploadedLength += readLength;
                }

                if (request.isCancelled) {
                    [handle closeFile];
                    return [BOSTask taskWithError:cancelError];
                }
            }
        }

        [handle closeFile];
        BOSCompleteMultipartUploadRequest * complete = [BOSCompleteMultipartUploadRequest new];
        complete.bucketName = request.bucketName;
        complete.objectKey = request.objectKey;
        complete.uploadId = request.uploadId;
        complete.partInfos = alreadyUploadPart;
        if (request.callbackParam != nil) {
            complete.callbackParam = request.callbackParam;
        }
        if (request.callbackVar != nil) {
            complete.callbackVar = request.callbackVar;
        }
        if (request.completeMetaHeader != nil) {
            complete.completeMetaHeader = request.completeMetaHeader;
        }
        BOSTask * completeTask = [self completeMultipartUpload:complete];
        [completeTask waitUntilFinished];

        if (completeTask.error) {
            return completeTask;
        } else {
            BOSCompleteMultipartUploadResult * completeResult = completeTask.result;
            BOSResumableUploadResult * result = [BOSResumableUploadResult new];
            result.requestId = completeResult.requestId;
            result.httpResponseCode = completeResult.httpResponseCode;
            result.httpResponseHeaderFields = completeResult.httpResponseHeaderFields;
            result.serverReturnJsonString = completeResult.serverReturnJsonString;
            return [BOSTask taskWithResult:result];
        }
    }];
}

- (BOOL)doesObjectExistInBucket:(NSString *)bucketName
                      objectKey:(NSString *)objectKey
                          error:(const NSError **)error {

    BOSHeadObjectRequest * headRequest = [BOSHeadObjectRequest new];
    headRequest.bucketName = bucketName;
    headRequest.objectKey = objectKey;
    BOSTask * headTask = [self headObject:headRequest];
    [headTask waitUntilFinished];
    NSError * headError = headTask.error;
    if (!headError) {
        return YES;
    } else {
        if ([headError.domain isEqualToString: BOSServerErrorDomain] && headError.code == -404) {
            return NO;
        } else {
            *error = headError;
            return NO;
        }
    }
}
@end
