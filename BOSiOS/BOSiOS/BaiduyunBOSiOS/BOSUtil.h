//
//  BOSUtil.h
//  BOS_ios_sdk
//
//  Created by zhouzhuo on 8/16/15.
//  Copyright (c) 2015 baiduyun.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@class BOSFederationToken;

@interface BOSUtil : NSObject

+ (NSString *)calBase64Sha1WithData:(NSString *)data withSecret:(NSString *)key;
+ (NSString *)calBase64WithData:(uint8_t *)data;
+ (NSString *)encodeURL:(NSString *)url;
+ (NSData *)constructHttpBodyFromPartInfos:(NSArray *)partInfos;
+ (NSData *)constructHttpBodyForCreateBucketWithLocation:(NSString *)location;
+ (BOOL)validateBucketName:(NSString *)bucketName;
+ (BOOL)validateObjectKey:(NSString *)objectKey;
+ (BOOL)isBOSOriginBucketHost:(NSString *)host;
+ (NSString *)getIpByHost:(NSString *)host;
+ (BOOL)isNetworkDelegateState;
+ (NSString *)dataMD5String:(NSData *)data;
+ (NSString *)fileMD5String:(NSString *)path;
+ (NSString*)base64ForData:(uint8_t *)input length:(int32_t)length;
+ (NSString *)base64Md5ForData:(NSData *)data;
+ (NSString *)base64Md5ForFilePath:(NSString *)filePath;
+ (NSString *)base64Md5ForFileURL:(NSURL *)fileURL;
+ (NSString *)sign:(NSString *)content withToken:(BOSFederationToken *)token;
+ (NSString *)getRelativePath:(NSString *)fullPath;
+ (NSString *)detemineMimeTypeForFilePath:(NSString *)filePath uploadName:(NSString *)uploadName;
+ (NSString *)sha256:(NSString *)key content:(NSString *)data;
+ (NSString *)urlEncodeExceptSlash:(NSString *)str;
+ (NSString *)urlEncode:(NSString *)str;
@end
