//
//  BOSCompat.h
//  BOS_ios_sdk_new
//
//  Created by zhouzhuo on 9/10/15.
//  Copyright (c) 2015 baiduyun.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BOSService.h"

@class BOSCancellationTokenSource;

typedef BOSCancellationTokenSource BOSTaskHandler;

@interface BOSClient (Compat)

/**
 兼容老版本用法的上传数据接口
 建议更换使用：putObject
 */
- (BOSTaskHandler *)uploadData:(NSData *)data
               withContentType:(NSString *)contentType
                withObjectMeta:(NSDictionary *)meta
                  toBucketName:(NSString *)bucketName
                   toObjectKey:(NSString *)objectKey
                   onCompleted:(void(^)(BOOL, NSError *))onCompleted
                    onProgress:(void(^)(float progress))onProgress;

/**
 兼容老版本用法的下载数据接口
 建议更换使用：getObject
 */
- (BOSTaskHandler *)downloadToDataFromBucket:(NSString *)bucketName
                   objectKey:(NSString *)objectKey
                 onCompleted:(void(^)(NSData *, NSError *))onCompleted
                  onProgress:(void(^)(float progress))onProgress;

/**
 兼容老版本用法的上传文件接口
 建议更换使用：putObject
 */
- (BOSTaskHandler *)uploadFile:(NSString *)filePath
                withContentType:(NSString *)contentType
                 withObjectMeta:(NSDictionary *)meta
                   toBucketName:(NSString *)bucketName
                    toObjectKey:(NSString *)objectKey
                    onCompleted:(void(^)(BOOL, NSError *))onCompleted
                     onProgress:(void(^)(float progress))onProgress;

/**
 兼容老版本用法的下载文件接口
 建议更换使用：getObject
 */
- (BOSTaskHandler *)downloadToFileFromBucket:(NSString *)bucketName
                  objectKey:(NSString *)objectKey
                     toFile:(NSString *)filePath
                onCompleted:(void(^)(BOOL, NSError *))onCompleted
                 onProgress:(void(^)(float progress))onProgress;


/**
 兼容老版本用法的断点上传文件接口
 建议更换使用：resumableUpload
 */
- (BOSTaskHandler *)resumableUploadFile:(NSString *)filePath
          withContentType:(NSString *)contentType
           withObjectMeta:(NSDictionary *)meta
             toBucketName:(NSString *)bucketName
              toObjectKey:(NSString *)objectKey
              onCompleted:(void(^)(BOOL, NSError *))onCompleted
               onProgress:(void(^)(float progress))onProgress;

/**
 兼容老版本用法的删除Object接口
 建议更换使用：deleteObject
 */
- (void)deleteObjectInBucket:(NSString *)bucketName
                   objectKey:(NSString *)objectKey
                 onCompleted:(void(^)(BOOL, NSError *))onCompleted;
@end