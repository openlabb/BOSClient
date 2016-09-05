//
//  BOSCompat.m
//  BOS_ios_sdk_new
//
//  Created by zhouzhuo on 9/10/15.
//  Copyright (c) 2015 baiduyun.com. All rights reserved.
//

#import "BOSDefine.h"
#import "BOSCompat.h"
#import "BOSBolts.h"
#import "BOSModel.h"


int64_t const BOSMultipartUploadDefaultBlockSize = 256 * 1024;

@implementation BOSClient (Compat)

- (BOSTaskHandler *)uploadData:(NSData *)data
               withContentType:(NSString *)contentType
                withObjectMeta:(NSDictionary *)meta
                  toBucketName:(NSString *)bucketName
                   toObjectKey:(NSString *)objectKey
                   onCompleted:(void(^)(BOOL, NSError *))onCompleted
                    onProgress:(void(^)(float progress))onProgress {

    BOSTaskHandler * bcts = [BOSCancellationTokenSource cancellationTokenSource];

    [[[BOSTask taskWithResult:nil] continueWithExecutor:self.BOSOperationExecutor withSuccessBlock:^id(BOSTask *task) {
        BOSPutObjectRequest * put = [BOSPutObjectRequest new];
        put.bucketName = bucketName;
        put.objectKey = objectKey;
        put.objectMeta = meta;
        put.uploadingData = data;
        put.contentType = contentType;

        put.uploadProgress = ^(int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
            if (totalBytesExpectedToSend) {
                onProgress((float)totalBytesSent / totalBytesExpectedToSend);
            }
        };

        [bcts.token registerCancellationObserverWithBlock:^{
            [put cancel];
        }];

        BOSTask * putTask = [self putObject:put];
        [putTask waitUntilFinished];
        onProgress(1.0f);
        return putTask;
    }] continueWithBlock:^id(BOSTask *task) {
        if (task.error) {
            onCompleted(NO, task.error);
        } else {
            onCompleted(YES, nil);
        }
        return nil;
    }];
    return bcts;
}

- (BOSTaskHandler *)downloadToDataFromBucket:(NSString *)bucketName
                                 objectKey:(NSString *)objectKey
                               onCompleted:(void (^)(NSData *, NSError *))onCompleted
                                onProgress:(void (^)(float))onProgress {

    BOSTaskHandler * bcts = [BOSCancellationTokenSource cancellationTokenSource];

    [[[BOSTask taskWithResult:nil] continueWithExecutor:self.BOSOperationExecutor withBlock:^id(BOSTask *task) {
        BOSGetObjectRequest * get = [BOSGetObjectRequest new];
        get.bucketName = bucketName;
        get.objectKey = objectKey;

        get.downloadProgress = ^(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
            if (totalBytesExpectedToWrite) {
                onProgress((float)totalBytesWritten / totalBytesExpectedToWrite);
            }
        };

        [bcts.token registerCancellationObserverWithBlock:^{
            [get cancel];
        }];

        BOSTask * getTask = [self getObject:get];
        [getTask waitUntilFinished];
        onProgress(1.0f);
        return getTask;
    }] continueWithBlock:^id(BOSTask *task) {
        if (task.error) {
            onCompleted(nil, task.error);
        } else {
            BOSGetObjectResult * result = task.result;
            onCompleted(result.downloadedData, nil);
        }
        return nil;
    }];

    return bcts;
}

- (BOSTaskHandler *)downloadToFileFromBucket:(NSString *)bucketName
                                 objectKey:(NSString *)objectKey
                                    toFile:(NSString *)filePath
                               onCompleted:(void (^)(BOOL, NSError *))onCompleted
                                onProgress:(void (^)(float))onProgress {

    BOSTaskHandler * bcts = [BOSCancellationTokenSource cancellationTokenSource];

    [[[BOSTask taskWithResult:nil] continueWithExecutor:self.BOSOperationExecutor withBlock:^id(BOSTask *task) {
        BOSGetObjectRequest * get = [BOSGetObjectRequest new];
        get.bucketName = bucketName;
        get.objectKey = objectKey;
        get.downloadToFileURL = [NSURL fileURLWithPath:filePath];

        get.downloadProgress = ^(int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
            if (totalBytesExpectedToWrite) {
                onProgress((float)totalBytesWritten / totalBytesExpectedToWrite);
            }
        };

        [bcts.token registerCancellationObserverWithBlock:^{
            [get cancel];
        }];

        BOSTask * getTask = [self getObject:get];
        [getTask waitUntilFinished];
        onProgress(1.0f);
        return getTask;
    }] continueWithBlock:^id(BOSTask *task) {
        if (task.error) {
            onCompleted(NO, task.error);
        } else {
            onCompleted(YES, nil);
        }
        return nil;
    }];
    
    return bcts;
}

- (void)deleteObjectInBucket:(NSString *)bucketName
                   objectKey:(NSString *)objectKey
                 onCompleted:(void (^)(BOOL, NSError *))onCompleted {

    [[[BOSTask taskWithResult:nil] continueWithExecutor:self.BOSOperationExecutor withBlock:^id(BOSTask *task) {
        BOSDeleteObjectRequest * delete = [BOSDeleteObjectRequest new];
        delete.bucketName = bucketName;
        delete.objectKey = objectKey;

        BOSTask * deleteTask = [self deleteObject:delete];
        [deleteTask waitUntilFinished];
        return deleteTask;
    }] continueWithBlock:^id(BOSTask *task) {
        if (task.error) {
            onCompleted(NO, task.error);
        } else {
            onCompleted(YES, nil);
        }
        return nil;
    }];
}

- (BOSTaskHandler *)uploadFile:(NSString *)filePath
               withContentType:(NSString *)contentType
                withObjectMeta:(NSDictionary *)meta
                  toBucketName:(NSString *)bucketName
                   toObjectKey:(NSString *)objectKey
                   onCompleted:(void (^)(BOOL, NSError *))onCompleted
                    onProgress:(void (^)(float))onProgress {

    BOSTaskHandler * bcts = [BOSCancellationTokenSource cancellationTokenSource];

    [[[BOSTask taskWithResult:nil] continueWithExecutor:self.BOSOperationExecutor withSuccessBlock:^id(BOSTask *task) {
        BOSPutObjectRequest * put = [BOSPutObjectRequest new];
        put.bucketName = bucketName;
        put.objectKey = objectKey;
        put.objectMeta = meta;
        put.uploadingFileURL = [NSURL fileURLWithPath:filePath];
        put.contentType = contentType;

        put.uploadProgress = ^(int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
            if (totalBytesExpectedToSend) {
                onProgress((float)totalBytesSent / totalBytesExpectedToSend);
            }
        };

        [bcts.token registerCancellationObserverWithBlock:^{
            [put cancel];
        }];

        BOSTask * putTask = [self putObject:put];
        [putTask waitUntilFinished];
        onProgress(1.0f);
        return putTask;
    }] continueWithBlock:^id(BOSTask *task) {
        if (task.error) {
            onCompleted(NO, task.error);
        } else {
            onCompleted(YES, nil);
        }
        return nil;
    }];
    return bcts;
}

- (BOSTaskHandler *)resumableUploadFile:(NSString *)filePath
                        withContentType:(NSString *)contentType
                         withObjectMeta:(NSDictionary *)meta
                           toBucketName:(NSString *)bucketName
                            toObjectKey:(NSString *)objectKey
                            onCompleted:(void(^)(BOOL, NSError *))onComplete
                             onProgress:(void(^)(float progress))onProgress {

    __block NSString * recordKey;
    BOSTaskHandler * bcts = [BOSCancellationTokenSource cancellationTokenSource];

    [[[[[[BOSTask taskWithResult:nil] continueWithBlock:^id(BOSTask *task) {
        NSURL * fileURL = [NSURL fileURLWithPath:filePath];
        NSDate * lastModified;
        NSError * error;
        [fileURL getResourceValue:&lastModified forKey:NSURLContentModificationDateKey error:&error];
        if (error) {
            return [BOSTask taskWithError:error];
        }
        recordKey = [NSString stringWithFormat:@"%@-%@-%@-%@", bucketName, objectKey, [BOSUtil getRelativePath:filePath], lastModified];
        NSUserDefaults * userDefault = [NSUserDefaults standardUserDefaults];
        return [BOSTask taskWithResult:[userDefault objectForKey:recordKey]];
    }] continueWithSuccessBlock:^id(BOSTask *task) {
        if (!task.result) {
            // new upload task
            BOSInitMultipartUploadRequest * initMultipart = [BOSInitMultipartUploadRequest new];
            initMultipart.bucketName = bucketName;
            initMultipart.objectKey = objectKey;
            initMultipart.contentType = contentType;
            initMultipart.objectMeta = meta;
            return [self multipartUploadInit:initMultipart];
        }
        BOSLogVerbose(@"An resumable task for uploadid: %@", task.result);
        return task;
    }] continueWithSuccessBlock:^id(BOSTask *task) {
        NSString * uploadId = nil;

        if (bcts.token.isCancellationRequested || bcts.isCancellationRequested) {
            return [BOSTask cancelledTask];
        }

        if (task.error) {
            return task;
        }

        if ([task.result isKindOfClass:[BOSInitMultipartUploadResult class]]) {
            uploadId = ((BOSInitMultipartUploadResult *)task.result).uploadId;
        } else {
            uploadId = task.result;
        }

        if (!uploadId) {
            return [BOSTask taskWithError:[NSError errorWithDomain:BOSClientErrorDomain
                                                             code:BOSClientErrorCodeNilUploadid
                                                         userInfo:@{BOSErrorMessageTOKEN: @"Can't get an upload id"}]];
        }
        NSUserDefaults * userDefault = [NSUserDefaults standardUserDefaults];
        [userDefault setObject:uploadId forKey:recordKey];
        [userDefault synchronize];
        return [BOSTask taskWithResult:uploadId];
    }] continueWithSuccessBlock:^id(BOSTask *task) {
        BOSResumableUploadRequest * resumableUpload = [BOSResumableUploadRequest new];
        resumableUpload.bucketName = bucketName;
        resumableUpload.objectKey = objectKey;
        resumableUpload.uploadId = task.result;
        resumableUpload.uploadingFileURL = [NSURL fileURLWithPath:filePath];
        __weak BOSResumableUploadRequest * weakRef = resumableUpload;
        resumableUpload.uploadProgress = ^(int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
            onProgress((float)totalBytesSent/totalBytesExpectedToSend);
            if (bcts.token.isCancellationRequested || bcts.isCancellationRequested) {
                [weakRef cancel];
            }
            NSLog(@"%lld %lld %lld", bytesSent, totalBytesSent, totalBytesExpectedToSend);
        };
        return [self resumableUpload:resumableUpload];
    }] continueWithBlock:^id(BOSTask *task) {
        if (task.cancelled) {
            onComplete(NO, [NSError errorWithDomain:BOSClientErrorDomain
                                               code:BOSClientErrorCodeTaskCancelled
                                           userInfo:@{BOSErrorMessageTOKEN: @"This task is cancelled"}]);
        } else if (task.error) {
            onComplete(NO, task.error);
        } else if (task.faulted) {
            onComplete(NO, [NSError errorWithDomain:BOSClientErrorDomain
                                               code:BOSClientErrorCodeExcpetionCatched
                                           userInfo:@{BOSErrorMessageTOKEN: [NSString stringWithFormat:@"Catch exception - %@", task.exception]}]);
        } else {
            onComplete(YES, nil);
        }
        return nil;
    }];
    return bcts;
}

@end
