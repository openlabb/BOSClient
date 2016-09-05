//
//  BOSModel.m
//  BOS_ios_sdk
//
//  Created by zhouzhuo on 8/16/15.
//  Copyright (c) 2015 baiduyun.com. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "BOSDefine.h"
#import "BOSModel.h"
#import "BOSBolts.h"
#import "BOSUtil.h"
#import "BOSNetworking.h"
#import "BOSLog.h"
#import "BOSXMLDictionary.h"

@implementation NSString (BOS)

- (NSString *)BOS_stringByAppendingPathComponentForURL:(NSString *)aString {
    if ([self hasSuffix:@"/"]) {
        return [NSString stringWithFormat:@"%@%@", self, aString];
    } else {
        return [NSString stringWithFormat:@"%@/%@", self, aString];
    }
}

- (NSString *)BOS_trim {
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end

@implementation NSDictionary (BOS)

- (NSString *)base64JsonString {
    NSError * error;
    NSData * jsonData = [NSJSONSerialization dataWithJSONObject:self
                                                        options:0
                                                          error:&error];

    if (!jsonData) {
        return @"e30="; // base64("{}");
    } else {
        NSString * jsonStr = [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
        NSLog(@"callback json - %@", jsonStr);
        return [[jsonStr dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    }
}

@end

@implementation NSDate (BOS)

NSString * const serverReturnDateFormat = @"EEE, dd MMM yyyy HH:mm:ss z";

static NSTimeInterval _clockSkew = 0.0;

+ (void)BOS_setClockSkew:(NSTimeInterval)clockSkew {
    @synchronized(self) {
        _clockSkew = clockSkew;
    }
}

+ (NSDate *)BOS_clockSkewFixedDate {
    NSTimeInterval skew = 0.0;
    @synchronized(self) {
        skew = _clockSkew;
    }
    return [[NSDate date] dateByAddingTimeInterval:(-1 * skew)];
}

+ (NSDate *)BOS_dateFromString:(NSString *)string {
    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    dateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
    dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    dateFormatter.dateFormat = serverReturnDateFormat;

    return [dateFormatter dateFromString:string];
}

- (NSString *)BOS_asStringValue {
    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    dateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
    dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    dateFormatter.dateFormat = serverReturnDateFormat;

    return [dateFormatter stringFromDate:self];
}

@end

@implementation BOSSyncMutableDictionary

- (instancetype)init {
    if (self = [super init]) {
        _dictionary = [NSMutableDictionary new];
        _dispatchQueue = dispatch_queue_create("com.baiduyun.baiduyunsycmutabledictionary", DISPATCH_QUEUE_SERIAL);
    }

    return self;
}

- (NSArray *)allKeys {
    __block NSArray *allKeys = nil;
    dispatch_sync(self.dispatchQueue, ^{
        allKeys = [self.dictionary allKeys];
    });
    return allKeys;
}

- (id)objectForKey:(id)aKey {
    __block id returnObject = nil;

    dispatch_sync(self.dispatchQueue, ^{
        returnObject = [self.dictionary objectForKey:aKey];
    });

    return returnObject;
}

- (void)setObject:(id)anObject forKey:(id <NSCopying>)aKey {
    dispatch_sync(self.dispatchQueue, ^{
        [self.dictionary setObject:anObject forKey:aKey];
    });
}

- (void)removeObjectForKey:(id)aKey {
    dispatch_sync(self.dispatchQueue, ^{
        [self.dictionary removeObjectForKey:aKey];
    });
}

@end

@implementation BOSFederationToken
@end

@implementation BOSPlainTextAKSKPairCredentialProvider

- (instancetype)initWithPlainTextAccessKey:(NSString *)accessKey secretKey:(NSString *)secretKey {
    if (self = [super init]) {
        self.accessKey = [accessKey BOS_trim];
        self.secretKey = [secretKey BOS_trim];
    }
    return self;
}

- (NSString *)sign:(NSString *)content error:(NSError **)error {
    if (!self.accessKey || !self.secretKey) {
        *error = [NSError errorWithDomain:BOSClientErrorDomain
                                     code:BOSClientErrorCodeSignFailed
                                 userInfo:@{BOSErrorMessageTOKEN: @"accessKey or secretKey can't be null"}];
        return nil;
    }
    NSString * sign = [BOSUtil calBase64Sha1WithData:content withSecret:self.secretKey];
    return [NSString stringWithFormat:@"BOS %@:%@", self.accessKey, sign];
}

@end

@implementation BOSCustomSignerCredentialProvider

- (instancetype)initWithImplementedSigner:(BOSCustomSignContentBlock)signContent {
    if (self = [super init]) {
        self.signContent = signContent;
    }
    return self;
}

- (NSString *)sign:(NSString *)content error:(NSError **)error {
    NSString * signature = @"";
    @synchronized(self) {
        signature = self.signContent(content, error);
    }
    if (*error) {
        *error = [NSError errorWithDomain:BOSClientErrorDomain
                                     code:BOSClientErrorCodeSignFailed
                                 userInfo:[[NSDictionary alloc] initWithDictionary:[*error userInfo]]];
        return nil;
    }
    return signature;
}

@end

@implementation BOSFederationCredentialProvider

- (instancetype)initWithFederationTokenGetter:(BOSGetFederationTokenBlock)federationTokenGetter {
    if (self = [super init]) {
        self.federationTokenGetter = federationTokenGetter;
    }
    return self;
}

- (BOSFederationToken *)getToken:(NSError **)error {
    BOSFederationToken * validToken = nil;
    @synchronized(self) {
        if (self.cachedToken == nil) {

            self.cachedToken = self.federationTokenGetter();
        } else {
            if (self.cachedToken.expirationTimeInGMTFormat) {
                NSDateFormatter * fm = [NSDateFormatter new];
                [fm setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
                self.cachedToken.expirationTimeInMilliSecond = [[fm dateFromString:self.cachedToken.expirationTimeInGMTFormat] timeIntervalSince1970] * 1000;
                self.cachedToken.expirationTimeInGMTFormat = nil;
                BOSLogVerbose(@"Transform GMT date to expirationTimeInMilliSecond: %lld", self.cachedToken.expirationTimeInMilliSecond);
            }

            NSDate * expirationDate = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)(self.cachedToken.expirationTimeInMilliSecond / 1000)];
            NSTimeInterval interval = [expirationDate timeIntervalSinceDate:[NSDate BOS_clockSkewFixedDate]];
            // BOSLogVerbose(@"get federation token, after %lf second it would be expired", interval);
            /* if this token will be expired after less than 30s, we abort it in case of when request arrived BOS server,
               it's expired already. */
            if (interval < 30) {
                BOSLogDebug(@"get federation token, but after %lf second it would be expired", interval);
                self.cachedToken = self.federationTokenGetter();
            }
        }

        validToken = self.cachedToken;
    }
    if (!validToken) {
        *error = [NSError errorWithDomain:BOSClientErrorDomain
                                     code:BOSClientErrorCodeSignFailed
                                 userInfo:@{BOSErrorMessageTOKEN: @"Can't get a federation token"}];
        return nil;
    }
    return validToken;
}

@end

@implementation BOSStsTokenCredentialProvider

- (BOSFederationToken *)getToken {
    BOSFederationToken * token = [BOSFederationToken new];
    token.tAccessKey = self.accessKeyId;
    token.tSecretKey = self.secretKeyId;
    token.tToken = self.securityToken;
    token.expirationTimeInMilliSecond = NSIntegerMax;
    return token;
}

- (instancetype)initWithAccessKeyId:(NSString *)accessKeyId secretKeyId:(NSString *)secretKeyId securityToken:(NSString *)securityToken {
    if (self = [super init]) {
        self.accessKeyId = [accessKeyId BOS_trim];
        self.secretKeyId = [secretKeyId BOS_trim];
        self.securityToken = [securityToken BOS_trim];
    }
    return self;
}

- (NSString *)sign:(NSString *)content error:(NSError **)error {
    NSString * sign = [BOSUtil calBase64Sha1WithData:content withSecret:self.secretKeyId];
    return [NSString stringWithFormat:@"BOS %@:%@", self.accessKeyId, sign];
}

@end

NSString * const BACKGROUND_SESSION_IDENTIFIER = @"com.baiduyun.BOS.backgroundsession";

@implementation BOSClientConfiguration

- (instancetype)init {
    if (self = [super init]) {
        self.maxRetryCount = BOSDefaultRetryCount;
        self.maxConcurrentRequestCount = BOSDefaultMaxConcurrentNum;
        self.enableBackgroundTransmitService = NO;
        self.isHttpdnsEnable = NO;
        self.backgroundSesseionIdentifier = BACKGROUND_SESSION_IDENTIFIER;
        self.timeoutIntervalForRequest = BOSDefaultTimeoutForRequestInSecond;
        self.timeoutIntervalForResource = BOSDefaultTimeoutForResourceInSecond;
    }
    return self;
}

- (void)setCnameExcludeList:(NSArray *)cnameExcludeList {
    NSMutableArray * array = [NSMutableArray new];
    [cnameExcludeList enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString * host = [(NSString *)obj lowercaseString];
        if ([host containsString:@"://"]) {
            NSString * trimHost = [host substringFromIndex:[host rangeOfString:@"://"].location + 3];
            [array addObject:trimHost];
        } else {
            [array addObject:host];
        }
    }];
    _cnameExcludeList = array.copy;
}

@end

@implementation BOSSignerInterceptor

- (instancetype)initWithCredentialProvider:(id<BOSCredentialProvider>)credentialProvider {
    if (self = [super init]) {
        self.credentialProvider = credentialProvider;
    }
    return self;
}

- (BOSTask *)interceptRequestMessage:(BOSAllRequestNeededMessage *)requestMessage {
    BOSLogVerbose(@"signing intercepting - ");
    NSError * error = nil;

    /****************************************************************
    * define a constant array to contain all specified subresource */
    static NSArray * BOSSubResourceARRAY = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BOSSubResourceARRAY = @[@"acl", @"uploadId", @"partNumber", @"uploads", @"logging", @"website", @"location",
                                @"lifecycle", @"referer", @"cors", @"delete", @"append", @"position", @"security-token"];
    });
    /****************************************************************/

    /* initial each part of content to sign */
    NSString * method = requestMessage.httpMethod;
    NSString * date = requestMessage.date;
    NSString * xBOSHeader = @"";
    NSString * resource = @"";

    BOSFederationToken * federationToken = nil;

    /* if credential provider is a federation token provider, it need to specially handle */
    if ([self.credentialProvider isKindOfClass:[BOSFederationCredentialProvider class]]) {
        federationToken = [(BOSFederationCredentialProvider *)self.credentialProvider getToken:&error];
        if (error) {
            return [BOSTask taskWithError:error];
        }
//        [requestMessage.headerParams setObject:federationToken.tToken forKey:@"x-BOS-security-token"];
    } else if ([self.credentialProvider isKindOfClass:[BOSStsTokenCredentialProvider class]]) {
        federationToken = [(BOSStsTokenCredentialProvider *)self.credentialProvider getToken];
//        [requestMessage.headerParams setObject:federationToken.tToken forKey:@"x-BOS-security-token"];
    }

    /* construct CanonicalURL */
    resource = @"/";
    if (requestMessage.bucketName) {
        resource = [NSString stringWithFormat:@"/%@/", requestMessage.bucketName];
    }
    if (requestMessage.objectKey) {
        resource = [resource BOS_stringByAppendingPathComponentForURL:requestMessage.objectKey];
    }
    
    
    /* construct CanonicalQueryString */
    NSString* queryString = @"";
    if (requestMessage.querys) {
        NSMutableArray * querys = [[NSMutableArray alloc] init];
        NSArray * sortedKey = [[requestMessage.querys allKeys] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            return [obj1 compare:obj2];
        }];
        for (NSString * key in sortedKey) {
            NSString * value = [requestMessage.querys objectForKey:key];
            
            if (![BOSSubResourceARRAY containsObject:key]) { // notice it's based on content compare
                continue;
            }
            
            if ([value isEqualToString:@""]) {
                [querys addObject:[NSString stringWithFormat:@"%@", [BOSUtil urlEncode:key]]];
            } else {
                [querys addObject:[NSString stringWithFormat:@"%@=%@", [BOSUtil urlEncode:key], [BOSUtil urlEncode:value]]];
            }
        }
        if ([querys count]) {
            queryString = [queryString stringByAppendingString:[NSString stringWithFormat:@"?%@",[querys componentsJoinedByString:@"&"]]];
        }
    }
    NSString *canonicalURIStr = canonicalURIStr = [BOSUtil urlEncodeExceptSlash:resource];;
    
    
    /* construct CanonicalizedBOSHeaders */
    if (requestMessage.headerParams) {
        NSMutableArray * params = [[NSMutableArray alloc] init];
        NSArray * sortedKey = [[requestMessage.headerParams allKeys] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            return [obj1 compare:obj2];
        }];
        for (NSString * key in sortedKey) {
//            if ([key hasPrefix:@"x-BOS-"]) {
//                [params addObject:[NSString stringWithFormat:@"%@:%@", key, [requestMessage.headerParams objectForKey:key]]];
//            }
            
            [params addObject:[NSString stringWithFormat:@"%@:%@", [BOSUtil urlEncode:key], [BOSUtil urlEncode:[requestMessage.headerParams objectForKey:key]]]];

        }
        if ([params count]) {
            xBOSHeader = [NSString stringWithFormat:@"%@\n", [params componentsJoinedByString:@"\n"]];
        }
    }
    
    NSString *canonicalHeaders = xBOSHeader;

    //SigningKey
    NSString * authStringPrefix = [NSString stringWithFormat:@"bce-auth-v1/%@/%@/%@",federationToken.tAccessKey, date, @"3600"];
    BOSLogDebug(@"string to sign: %@", authStringPrefix);
    NSString *signingKey = [BOSUtil sha256:federationToken.tSecretKey content:authStringPrefix];
    
    //CanonicalRequest string
    NSString *canonicalRequestStr = [NSString stringWithFormat:@"%@\n%@\n%@\n%@",method,canonicalURIStr,queryString,canonicalHeaders];
    
    //signature
    NSString *signature = [BOSUtil sha256:signingKey content:canonicalRequestStr];
    NSString *authorizationString =  [NSString stringWithFormat:@"%@/%@/%@",authStringPrefix,@"host",signature];

    //auth string
    [requestMessage.headerParams setObject:authorizationString forKey:@"Authorization"];
    
    return [BOSTask taskWithResult:nil];
}

@end

@implementation BOSUASettingInterceptor

- (NSString *)getUserAgent {
    static NSString * _userAgent = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *systemName = [[[UIDevice currentDevice] systemName] stringByReplacingOccurrencesOfString:@" " withString:@"-"];
        NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
        NSString *localeIdentifier = [[NSLocale currentLocale] localeIdentifier];
        _userAgent = [NSString stringWithFormat:@"%@/%@/%@/%@/%@", BOSUAPrefix, BOSSDKVersion, systemName, systemVersion, localeIdentifier];
    });
    return _userAgent;
}

- (BOSTask *)interceptRequestMessage:(BOSAllRequestNeededMessage *)request {
    NSString * userAgent = [self getUserAgent];
    [request.headerParams setObject:userAgent forKey:@"User-Agent"];
    return [BOSTask taskWithResult:nil];
}

@end

@implementation BOSTimeSkewedFixingInterceptor

- (BOSTask *)interceptRequestMessage:(BOSAllRequestNeededMessage *)request {
    request.date = [[NSDate BOS_clockSkewFixedDate] BOS_asStringValue];
    return [BOSTask taskWithResult:nil];
}

@end

@implementation BOSRange

- (instancetype)initWithStart:(int64_t)start withEnd:(int64_t)end {
    if (self = [super init]) {
        self.startPosition = start;
        self.endPosition = end;
    }
    return self;
}

- (NSString *)toHeaderString {

    NSString * rangeString = nil;

    if (self.startPosition < 0 && self.endPosition < 0) {
        rangeString = [NSString stringWithFormat:@"bytes=%lld-%lld", self.startPosition, self.endPosition];
    } else if (self.startPosition < 0) {
        rangeString = [NSString stringWithFormat:@"bytes=-%lld", self.endPosition];
    } else if (self.endPosition < 0) {
        rangeString = [NSString stringWithFormat:@"bytes=%lld-", self.startPosition];
    } else {
        rangeString = [NSString stringWithFormat:@"bytes=%lld-%lld", self.startPosition, self.endPosition];
    }

    return rangeString;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Range: %@", [self toHeaderString]];
}

@end

#pragma mark request and result objects

@interface BOSRequest ()
@property (nonatomic, strong) BOSNetworkingRequestDelegate * requestDelegate;
@end

@implementation BOSRequest

- (instancetype)init {
    if (self = [super init]) {
        self.requestDelegate = [BOSNetworkingRequestDelegate new];
        self.isAuthenticationRequired = YES;
    }
    return self;
}

- (void)cancel {
    if (self.requestDelegate) {
        [self.requestDelegate cancel];
    }
}

@end

@implementation BOSResult
@end

@implementation BOSGetServiceRequest

- (NSDictionary *)getQueryDict {
    NSMutableDictionary * querys = [NSMutableDictionary new];
    if (self.prefix) {
        [querys setObject:self.prefix forKey:@"prefix"];
    }
    if (self.marker) {
        [querys setObject:self.marker forKey:@"marker"];
    }
    if (self.maxKeys) {
        [querys setObject:[@(self.maxKeys) stringValue] forKey:@"max-keys"];
    }
    return querys;
}

@end

@implementation BOSGetServiceResult
@end

@implementation BOSCreateBucketRequest
@end

@implementation BOSCreateBucketResult
@end

@implementation BOSDeleteBucketRequest
@end

@implementation BOSDeleteBucketResult
@end

@implementation BOSGetBucketRequest

- (NSDictionary *)getQueryDict {
    NSMutableDictionary * querys = [NSMutableDictionary new];
    if (self.delimiter) {
        [querys setObject:self.delimiter forKey:@"delimiter"];
    }
    if (self.prefix) {
        [querys setObject:self.prefix forKey:@"prefix"];
    }
    if (self.marker) {
        [querys setObject:self.marker forKey:@"marker"];
    }
    if (self.maxKeys) {
        [querys setObject:[@(self.maxKeys) stringValue] forKey:@"max-keys"];
    }
    return querys;
}

@end

@implementation BOSGetBucketResult
@end

@implementation BOSGetBucketACLRequest
@end

@implementation BOSGetBucketACLResult
@end

@implementation BOSHeadObjectRequest
@end

@implementation BOSHeadObjectResult
@end

@implementation BOSGetObjectRequest
@end

@implementation BOSGetObjectResult
@end

@implementation BOSPutObjectACLRequest
@end

@implementation BOSPutObjectACLResult
@end

@implementation BOSPutObjectRequest

- (instancetype)init {
    if (self = [super init]) {
        self.objectMeta = [NSDictionary new];
    }
    return self;
}

@end

@implementation BOSPutObjectResult
@end

@implementation BOSAppendObjectRequest

- (instancetype)init {
    if (self = [super init]) {
        self.objectMeta = [NSDictionary new];
    }
    return self;
}

@end

@implementation BOSAppendObjectResult
@end

@implementation BOSDeleteObjectRequest
@end

@implementation BOSDeleteObjectResult
@end

@implementation BOSCopyObjectRequest

- (instancetype)init {
    if (self = [super init]) {
        self.objectMeta = [NSDictionary new];
    }
    return self;
}

@end

@implementation BOSCopyObjectResult
@end

@implementation BOSInitMultipartUploadRequest

- (instancetype)init {
    if (self = [super init]) {
        self.objectMeta = [NSDictionary new];
    }
    return self;
}

@end

@implementation BOSInitMultipartUploadResult
@end

@implementation BOSUploadPartRequest
@end

@implementation BOSUploadPartResult
@end

@implementation BOSPartInfo

+ (instancetype)partInfoWithPartNum:(int32_t)partNum
                               eTag:(NSString *)eTag
                               size:(int64_t)size {
    BOSPartInfo * instance = [BOSPartInfo new];
    instance.partNum = partNum;
    instance.eTag = eTag;
    instance.size = size;
    return instance;
}

@end

@implementation BOSCompleteMultipartUploadRequest
@end

@implementation BOSCompleteMultipartUploadResult
@end

@implementation BOSAbortMultipartUploadRequest
@end

@implementation BOSAbortMultipartUploadResult
@end

@implementation BOSListPartsRequest
@end

@implementation BOSListPartsResult
@end

@implementation BOSResumableUploadRequest

- (instancetype)init {
    if (self = [super init]) {
        self.partSize = 256 * 1024;
    }
    return self;
}

- (void)cancel {
    self.isCancelled = YES;
}

@end

@implementation BOSResumableUploadResult
@end

#pragma mark response parser


@implementation BOSHttpResponseParser {

    BOSOperationType _operationTypeForThisParser;

    NSFileHandle * _fileHandle;
    NSMutableData * _collectingData;
    NSHTTPURLResponse * _response;
}

- (void)reset {
    _collectingData = nil;
    _fileHandle = nil;
    _response = nil;
}

- (instancetype)initForOperationType:(BOSOperationType)operationType {
    if (self = [super init]) {
        _operationTypeForThisParser = operationType;
    }
    return self;
}

- (void)consumeHttpResponse:(NSHTTPURLResponse *)response {
    _response = response;
}

- (BOSTask *)consumeHttpResponseBody:(NSData *)data {

    if (self.onRecieveBlock) {
        self.onRecieveBlock(data);
        return [BOSTask taskWithResult:nil];
    }

    NSError * error;
    if (self.downloadingFileURL) {
        if (!_fileHandle) {
            NSFileManager * fm = [NSFileManager defaultManager];
            NSString * dirName = [[self.downloadingFileURL path] stringByDeletingLastPathComponent];
            if (![fm fileExistsAtPath:dirName]) {
                [fm createDirectoryAtPath:dirName withIntermediateDirectories:YES attributes:nil error:&error];
            }
            if (![fm fileExistsAtPath:dirName] || error) {
                return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                                 code:BOSClientErrorCodeFileCantWrite
                                                             userInfo:@{BOSErrorMessageTOKEN: [NSString stringWithFormat:@"Can't create dir at %@", dirName]}]];
            }
            [fm createFileAtPath:[self.downloadingFileURL path] contents:nil attributes:nil];
            if (![fm fileExistsAtPath:[self.downloadingFileURL path]]) {
                return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                                 code:BOSClientErrorCodeFileCantWrite
                                                             userInfo:@{BOSErrorMessageTOKEN: [NSString stringWithFormat:@"Can't create file at %@", [self.downloadingFileURL path]]}]];
            }
            _fileHandle = [NSFileHandle fileHandleForWritingToURL:self.downloadingFileURL error:&error];
            if (error) {
                return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                                 code:BOSClientErrorCodeFileCantWrite
                                                             userInfo:[error userInfo]]];
            }
            [_fileHandle writeData:data];
        } else {
            @try {
                [_fileHandle writeData:data];
            }
            @catch (NSException *exception) {
                return [BOSTask taskWithError:[NSError errorWithDomain:BOSServerErrorDomain
                                                                 code:BOSClientErrorCodeFileCantWrite
                                                             userInfo:@{BOSErrorMessageTOKEN: [exception description]}]];
            }
        }
    } else {
        if (!_collectingData) {
            _collectingData = [[NSMutableData alloc] initWithData:data];
        } else {
            [_collectingData appendData:data];
        }
    }
    return [BOSTask taskWithResult:nil];
}

- (void)parseResponseHeader:(NSHTTPURLResponse *)response toResultObject:(BOSResult *)result {
    result.httpResponseCode = [_response statusCode];
    result.httpResponseHeaderFields = [NSDictionary dictionaryWithDictionary:[_response allHeaderFields]];
    [[_response allHeaderFields] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString * keyString = (NSString *)key;
        if ([keyString isEqualToString:@"x-BOS-request-id"]) {
            result.requestId = obj;
        }
    }];
}

- (NSDictionary *)parseResponseHeaderToGetMeta:(NSHTTPURLResponse *)response {
    NSMutableDictionary * meta = [NSMutableDictionary new];

    /* define a constant array to contain all meta header name */
    static NSArray * BOSObjectMetaFieldNames = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BOSObjectMetaFieldNames = @[@"Content-Type", @"Content-Length", @"Etag", @"Last-Modified", @"x-BOS-request-id", @"x-BOS-object-type",
                                @"If-Modified-Since", @"If-Unmodified-Since", @"If-Match", @"If-None-Match"];
    });
    /****************************************************************/

    [[_response allHeaderFields] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString * keyString = (NSString *)key;
        if ([BOSObjectMetaFieldNames containsObject:keyString] || [keyString hasPrefix:@"x-BOS-meta"]) {
            [meta setObject:obj forKey:key];
        }
    }];
    return meta;
}

- (id)constructResultObject {
    if (self.onRecieveBlock) {
        return nil;
    }

    switch (_operationTypeForThisParser) {

        case BOSOperationTypeGetService: {
            BOSGetServiceResult * getServiceResult = [BOSGetServiceResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:getServiceResult];
            }
            if (_collectingData) {
                NSDictionary * parseDict = [NSDictionary dictionaryWithXMLData:_collectingData];
                BOSLogVerbose(@"Get service dict: %@", parseDict);
                if (parseDict) {
                    getServiceResult.ownerId = [[parseDict objectForKey:BOSOwnerXMLTOKEN] objectForKey:BOSIDXMLTOKEN];
                    getServiceResult.ownerDispName = [[parseDict objectForKey:BOSOwnerXMLTOKEN] objectForKey:BOSDisplayNameXMLTOKEN];
                    getServiceResult.prefix = [parseDict objectForKey:BOSPrefixXMLTOKEN];
                    getServiceResult.marker = [parseDict objectForKey:BOSMarkerXMLTOKEN];
                    getServiceResult.maxKeys = [[parseDict objectForKey:BOSMaxKeysXMLTOKEN] intValue];
                    getServiceResult.isTruncated = [[parseDict objectForKey:BOSIsTruncatedXMLTOKEN] boolValue];

                    id bucketObject = [[parseDict objectForKey:BOSBucketsXMLTOKEN] objectForKey:BOSBucketXMLTOKEN];
                    if ([bucketObject isKindOfClass:[NSArray class]]) {
                        getServiceResult.buckets = bucketObject;
                    } else if ([bucketObject isKindOfClass:[NSDictionary class]]) {
                        NSArray * arr = [NSArray arrayWithObject:bucketObject];
                        getServiceResult.buckets = arr;
                    } else {
                        getServiceResult.buckets = nil;
                    }
                }
            }
            return getServiceResult;
        }

        case BOSOperationTypeCreateBucket: {
            BOSCreateBucketResult * createBucketResult = [BOSCreateBucketResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:createBucketResult];
                [_response.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    if ([((NSString *)key) isEqualToString:@"Location"]) {
                        createBucketResult.location = obj;
                        *stop = YES;
                    }
                }];
            }
            return createBucketResult;
        }

        case BOSOperationTypeGetBucketACL: {
            BOSGetBucketACLResult * getBucketACLResult = [BOSGetBucketACLResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:getBucketACLResult];
            }
            if (_collectingData) {
                NSDictionary * parseDict = [NSDictionary dictionaryWithXMLData:_collectingData];
                BOSLogVerbose(@"Get service dict: %@", parseDict);
                if (parseDict) {
                    getBucketACLResult.aclGranted = [[parseDict objectForKey:BOSAccessControlListXMLTOKEN] objectForKey:BOSGrantXMLTOKEN];
                }
            }
            return getBucketACLResult;
        }

        case BOSOperationTypeDeleteBucket: {
            BOSDeleteBucketResult * deleteBucketResult = [BOSDeleteBucketResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:deleteBucketResult];
            }
            return deleteBucketResult;
        }

        case BOSOperationTypeGetBucket: {
            BOSGetBucketResult * getBucketResult = [BOSGetBucketResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:getBucketResult];
            }
            if (_collectingData) {
                NSDictionary * parsedDict = [NSDictionary dictionaryWithXMLData:_collectingData];
                BOSLogVerbose(@"Get bucket dict: %@", parsedDict);

                if (parsedDict) {
                    getBucketResult.bucketName = [parsedDict objectForKey:BOSNameXMLTOKEN];
                    getBucketResult.prefix = [parsedDict objectForKey:BOSPrefixXMLTOKEN];
                    getBucketResult.marker = [parsedDict objectForKey:BOSMarkerXMLTOKEN];
                    getBucketResult.nextMarker = [parsedDict objectForKey:BOSNextMarkerXMLTOKEN];
                    getBucketResult.maxKeys = (int32_t)[[parsedDict objectForKey:BOSMaxKeysXMLTOKEN] integerValue];
                    getBucketResult.delimiter = [parsedDict objectForKey:BOSDelimiterXMLTOKEN];
                    getBucketResult.isTruncated = [[parsedDict objectForKey:BOSIsTruncatedXMLTOKEN] boolValue];

                    id contentObject = [parsedDict objectForKey:BOSContentsXMLTOKEN];
                    if ([contentObject isKindOfClass:[NSArray class]]) {
                        getBucketResult.contents = contentObject;
                    } else if ([contentObject isKindOfClass:[NSDictionary class]]) {
                        NSArray * arr = [NSArray arrayWithObject:contentObject];
                        getBucketResult.contents = arr;
                    } else {
                        getBucketResult.contents = nil;
                    }

                    NSMutableArray * commentPrefixesArr = [NSMutableArray new];
                    id commentPrefixes = [parsedDict objectForKey:BOSCommonPrefixesXMLTOKEN];
                    if ([commentPrefixes isKindOfClass:[NSArray class]]) {
                        for (NSDictionary * prefix in commentPrefixes) {
                            [commentPrefixesArr addObject:[prefix objectForKey:@"Prefix"]];
                        }
                    } else if ([commentPrefixes isKindOfClass:[NSDictionary class]]) {
                        [commentPrefixesArr addObject:[(NSDictionary *)commentPrefixes objectForKey:@"Prefix"]];
                    } else {
                        commentPrefixesArr = nil;
                    }

                    getBucketResult.commentPrefixes = commentPrefixesArr;
                }
            }
            return getBucketResult;
        }

        case BOSOperationTypeHeadObject: {
            BOSHeadObjectResult * headObjectResult = [BOSHeadObjectResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:headObjectResult];
                headObjectResult.objectMeta = [self parseResponseHeaderToGetMeta:_response];
            }
            return headObjectResult;
        }

        case BOSOperationTypeGetObject: {
            BOSGetObjectResult * getObejctResult = [BOSGetObjectResult new];
            BOSLogDebug(@"GetObjectResponse: %@", _response);
            if (_response) {
                [self parseResponseHeader:_response toResultObject:getObejctResult];
                getObejctResult.objectMeta = [self parseResponseHeaderToGetMeta:_response];
            }
            if (_fileHandle) {
                [_fileHandle closeFile];
            }
            if (_collectingData) {
                getObejctResult.downloadedData = _collectingData;
            }
            return getObejctResult;
        }

        case BOSOperationTypePutObject: {
            BOSPutObjectResult * putObjectResult = [BOSPutObjectResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:putObjectResult];
                [_response.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    if ([((NSString *)key) isEqualToString:@"Etag"]) {
                        putObjectResult.eTag = obj;
                        *stop = YES;
                    }
                }];
            }
            if (_collectingData) {
                putObjectResult.serverReturnJsonString = [[NSString alloc] initWithData:_collectingData encoding:NSUTF8StringEncoding];
            }
            return putObjectResult;
        }

        case BOSOperationTypeAppendObject: {
            BOSAppendObjectResult * appendObjectResult = [BOSAppendObjectResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:appendObjectResult];
                [_response.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    if ([((NSString *)key) isEqualToString:@"Etag"]) {
                        appendObjectResult.eTag = obj;
                    }
                    if ([((NSString *)key) isEqualToString:@"x-BOS-next-append-position"]) {
                        appendObjectResult.xBOSNextAppendPosition = [((NSString *)obj) longLongValue];
                    }
                }];
            }
            return appendObjectResult;
        }

        case BOSOperationTypeDeleteObject: {
            BOSDeleteObjectResult * deleteObjectResult = [BOSDeleteObjectResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:deleteObjectResult];
            }
            return deleteObjectResult;
        }

        case BOSOperationTypePutObjectACL: {
            BOSPutObjectACLResult * putObjectACLResult = [BOSPutObjectACLResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:putObjectACLResult];
            }
            return putObjectACLResult;
        }

        case BOSOperationTypeCopyObject: {
            BOSCopyObjectResult * copyObjectResult = [BOSCopyObjectResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:copyObjectResult];
            }
            if (_collectingData) {
                BOSLogVerbose(@"copy object dict: %@", [NSDictionary dictionaryWithXMLData:_collectingData]);
                NSDictionary * parsedDict = [NSDictionary dictionaryWithXMLData:_collectingData];
                if (parsedDict) {
                    copyObjectResult.lastModifed = [parsedDict objectForKey:BOSLastModifiedXMLTOKEN];
                    copyObjectResult.eTag = [parsedDict objectForKey:BOSETagXMLTOKEN];
                }
            }
            return copyObjectResult;
        }

        case BOSOperationTypeInitMultipartUpload: {
            BOSInitMultipartUploadResult * initMultipartUploadResult = [BOSInitMultipartUploadResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:initMultipartUploadResult];
            }
            if (_collectingData) {
                NSDictionary * parsedDict = [NSDictionary dictionaryWithXMLData:_collectingData];
                BOSLogVerbose(@"init multipart upload result: %@", parsedDict);
                if (parsedDict) {
                    initMultipartUploadResult.uploadId = [parsedDict objectForKey:BOSUploadIdXMLTOKEN];
                }
            }
            return initMultipartUploadResult;
        }

        case BOSOperationTypeUploadPart: {
            BOSUploadPartResult * uploadPartResult = [BOSUploadPartResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:uploadPartResult];
                [_response.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                    if ([((NSString *)key) isEqualToString:@"Etag"]) {
                        uploadPartResult.eTag = obj;
                        *stop = YES;
                    }
                }];
            }
            return uploadPartResult;
        }

        case BOSOperationTypeCompleteMultipartUpload: {
            BOSCompleteMultipartUploadResult * completeMultipartUploadResult = [BOSCompleteMultipartUploadResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:completeMultipartUploadResult];
            }
            if (_collectingData) {
                if ([[[_response.allHeaderFields objectForKey:BOSHttpHeaderContentType] description] isEqual:@"application/xml"]) {
                    BOSLogVerbose(@"complete multipart upload result: %@", [NSDictionary dictionaryWithXMLData:_collectingData]);
                    NSDictionary * parsedDict = [NSDictionary dictionaryWithXMLData:_collectingData];
                    if (parsedDict) {
                        completeMultipartUploadResult.location = [parsedDict objectForKey:BOSLocationXMLTOKEN];
                        completeMultipartUploadResult.eTag = [parsedDict objectForKey:BOSETagXMLTOKEN];
                    }
                } else {
                    completeMultipartUploadResult.serverReturnJsonString = [[NSString alloc] initWithData:_collectingData encoding:NSUTF8StringEncoding];
                }
            }
            return completeMultipartUploadResult;
        }

        case BOSOperationTypeListMultipart: {
            BOSListPartsResult * listPartsReuslt = [BOSListPartsResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:listPartsReuslt];
            }
            if (_collectingData) {
                NSDictionary * parsedDict = [NSDictionary dictionaryWithXMLData:_collectingData];
                BOSLogVerbose(@"list multipart upload result: %@", parsedDict);
                if (parsedDict) {
                    listPartsReuslt.nextPartNumberMarker = [[parsedDict objectForKey:BOSNextPartNumberMarkerXMLTOKEN] intValue];
                    listPartsReuslt.maxParts = [[parsedDict objectForKey:BOSMaxKeysXMLTOKEN] intValue];
                    listPartsReuslt.isTruncated = [[parsedDict objectForKey:BOSMaxKeysXMLTOKEN] boolValue];

                    id partsObject = [parsedDict objectForKey:BOSPartXMLTOKEN];
                    if ([partsObject isKindOfClass:[NSArray class]]) {
                        listPartsReuslt.parts = partsObject;
                    } else if ([partsObject isKindOfClass:[NSDictionary class]]) {
                        NSArray * arr = [NSArray arrayWithObject:partsObject];
                        listPartsReuslt.parts = arr;
                    } else {
                        listPartsReuslt.parts = nil;
                    }
                }
            }
            return listPartsReuslt;
        }

        case BOSOperationTypeAbortMultipartUpload: {
            BOSAbortMultipartUploadResult * abortMultipartUploadResult = [BOSAbortMultipartUploadResult new];
            if (_response) {
                [self parseResponseHeader:_response toResultObject:abortMultipartUploadResult];
            }
            return abortMultipartUploadResult;
        }

        default: {
            BOSLogError(@"unknown operation type");
            break;
        }
    }
    return nil;
}

@end
