/*
 *  Copyright (c) 2014, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "BOSTask.h"

#import <libkern/OSAtomic.h>

#import "BOSBolts.h"

NS_ASSUME_NONNULL_BEGIN

__attribute__ ((noinline)) void warnBlockingOperationOnMainThread() {
    NSLog(@"Warning: A long-running operation is being executed on the main thread. \n"
          " Break on warnBlockingOperationOnMainThread() to debug.");
}

NSString *const BOSTaskErrorDomain = @"bolts";
NSInteger const kBFMultipleErrorsError = 80175001;
NSString *const BOSTaskMultipleExceptionsException = @"BOSMultipleExceptionsException";

NSString *const BOSTaskMultipleErrorsUserInfoKey = @"errors";
NSString *const BOSTaskMultipleExceptionsUserInfoKey = @"exceptions";

@interface BOSTask () {
    id _result;
    NSError *_error;
    NSException *_exception;
}

@property (nonatomic, assign, readwrite, getter=isCancelled) BOOL cancelled;
@property (nonatomic, assign, readwrite, getter=isFaulted) BOOL faulted;
@property (nonatomic, assign, readwrite, getter=isCompleted) BOOL completed;

@property (nonatomic, strong) NSObject *lock;
@property (nonatomic, strong) NSCondition *condition;
@property (nonatomic, strong) NSMutableArray *callbacks;

@end

@implementation BOSTask

#pragma mark - Initializer

- (instancetype)init {
    self = [super init];
    if (!self) return self;

    _lock = [[NSObject alloc] init];
    _condition = [[NSCondition alloc] init];
    _callbacks = [NSMutableArray array];

    return self;
}

- (instancetype)initWithResult:(id)result {
    self = [super init];
    if (!self) return self;

    [self trySetResult:result];

    return self;
}

- (instancetype)initWithError:(NSError *)error {
    self = [super init];
    if (!self) return self;

    [self trySetError:error];

    return self;
}

- (instancetype)initWithException:(NSException *)exception {
    self = [super init];
    if (!self) return self;

    [self trySetException:exception];

    return self;
}

- (instancetype)initCancelled {
    self = [super init];
    if (!self) return self;

    [self trySetCancelled];

    return self;
}

#pragma mark - Task Class methods

+ (instancetype)taskWithResult:(nullable id)result {
    return [[self alloc] initWithResult:result];
}

+ (instancetype)taskWithError:(NSError *)error {
    return [[self alloc] initWithError:error];
}

+ (instancetype)taskWithException:(NSException *)exception {
    return [[self alloc] initWithException:exception];
}

+ (instancetype)cancelledTask {
    return [[self alloc] initCancelled];
}

+ (instancetype)taskForCompletionOfAllTasks:(nullable NSArray<BOSTask *> *)tasks {
    __block int32_t total = (int32_t)tasks.count;
    if (total == 0) {
        return [self taskWithResult:nil];
    }

    __block int32_t cancelled = 0;
    NSObject *lock = [[NSObject alloc] init];
    NSMutableArray *errors = [NSMutableArray array];
    NSMutableArray *exceptions = [NSMutableArray array];

    BOSTaskCompletionSource *tcs = [BOSTaskCompletionSource taskCompletionSource];
    for (BOSTask *task in tasks) {
        [task continueWithBlock:^id(BOSTask *task) {
            if (task.exception) {
                @synchronized (lock) {
                    [exceptions addObject:task.exception];
                }
            } else if (task.error) {
                @synchronized (lock) {
                    [errors addObject:task.error];
                }
            } else if (task.cancelled) {
                OSAtomicIncrement32Barrier(&cancelled);
            }

            if (OSAtomicDecrement32Barrier(&total) == 0) {
                if (exceptions.count > 0) {
                    if (exceptions.count == 1) {
                        tcs.exception = [exceptions firstObject];
                    } else {
                        NSException *exception =
                        [NSException exceptionWithName:BOSTaskMultipleExceptionsException
                                                reason:@"There were multiple exceptions."
                                              userInfo:@{ BOSTaskMultipleExceptionsUserInfoKey: exceptions }];
                        tcs.exception = exception;
                    }
                } else if (errors.count > 0) {
                    if (errors.count == 1) {
                        tcs.error = [errors firstObject];
                    } else {
                        NSError *error = [NSError errorWithDomain:BOSTaskErrorDomain
                                                             code:kBFMultipleErrorsError
                                                         userInfo:@{ BOSTaskMultipleErrorsUserInfoKey: errors }];
                        tcs.error = error;
                    }
                } else if (cancelled > 0) {
                    [tcs cancel];
                } else {
                    tcs.result = nil;
                }
            }
            return nil;
        }];
    }
    return tcs.task;
}

+ (instancetype)taskForCompletionOfAllTasksWithResults:(nullable NSArray<BOSTask *> *)tasks {
    return [[self taskForCompletionOfAllTasks:tasks] continueWithSuccessBlock:^id(BOSTask *task) {
        return [tasks valueForKey:@"result"];
    }];
}

+ (instancetype)taskForCompletionOfAnyTask:(nullable NSArray<BOSTask *> *)tasks
{
    __block int32_t total = (int32_t)tasks.count;
    if (total == 0) {
        return [self taskWithResult:nil];
    }
    
    __block int completed = 0;
    __block int32_t cancelled = 0;
    
    NSObject *lock = [NSObject new];
    NSMutableArray<NSError *> *errors = [NSMutableArray new];
    NSMutableArray<NSException *> *exceptions = [NSMutableArray new];
    
    BOSTaskCompletionSource *source = [BOSTaskCompletionSource taskCompletionSource];
    for (BOSTask *task in tasks) {
        [task continueWithBlock:^id(BOSTask *task) {
            if (task.exception != nil) {
                @synchronized(lock) {
                    [exceptions addObject:task.exception];
                }
            } else if (task.error != nil) {
                @synchronized(lock) {
                    [errors addObject:task.error];
                }
            } else if (task.cancelled) {
                OSAtomicIncrement32Barrier(&cancelled);
            } else {
                if(OSAtomicCompareAndSwap32Barrier(0, 1, &completed)) {
                    [source setResult:task.result];
                }
            }
            
            if (OSAtomicDecrement32Barrier(&total) == 0 &&
                OSAtomicCompareAndSwap32Barrier(0, 1, &completed)) {
                if (cancelled > 0) {
                    [source cancel];
                } else if (exceptions.count > 0) {
                    if (exceptions.count == 1) {
                        source.exception = exceptions.firstObject;
                    } else {
                        NSException *exception =
                        [NSException exceptionWithName:BOSTaskMultipleExceptionsException
                                                reason:@"There were multiple exceptions."
                                              userInfo:@{ @"exceptions": exceptions }];
                        source.exception = exception;
                    }
                } else if (errors.count > 0) {
                    if (errors.count == 1) {
                        source.error = errors.firstObject;
                    } else {
                        NSError *error = [NSError errorWithDomain:BOSTaskErrorDomain
                                                             code:kBFMultipleErrorsError
                                                         userInfo:@{ @"errors": errors }];
                        source.error = error;
                    }
                }
            }
            // Abort execution of per tasks continuations
            return nil;
        }];
    }
    return source.task;
}


+ (instancetype)taskWithDelay:(int)millis {
    BOSTaskCompletionSource *tcs = [BOSTaskCompletionSource taskCompletionSource];
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, millis * NSEC_PER_MSEC);
    dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        tcs.result = nil;
    });
    return tcs.task;
}

+ (instancetype)taskWithDelay:(int)millis cancellationToken:(nullable BOSCancellationToken *)token {
    if (token.cancellationRequested) {
        return [BOSTask cancelledTask];
    }

    BOSTaskCompletionSource *tcs = [BOSTaskCompletionSource taskCompletionSource];
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, millis * NSEC_PER_MSEC);
    dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        if (token.cancellationRequested) {
            [tcs cancel];
            return;
        }
        tcs.result = nil;
    });
    return tcs.task;
}

+ (instancetype)taskFromExecutor:(BOSExecutor *)executor withBlock:(nullable id (^)())block {
    return [[self taskWithResult:nil] continueWithExecutor:executor withBlock:^id(BOSTask *task) {
        return block();
    }];
}

#pragma mark - Custom Setters/Getters

- (nullable id)result {
    @synchronized(self.lock) {
        return _result;
    }
}

- (BOOL)trySetResult:(nullable id)result {
    @synchronized(self.lock) {
        if (self.completed) {
            return NO;
        }
        self.completed = YES;
        _result = result;
        [self runContinuations];
        return YES;
    }
}

- (nullable NSError *)error {
    @synchronized(self.lock) {
        return _error;
    }
}

- (BOOL)trySetError:(NSError *)error {
    @synchronized(self.lock) {
        if (self.completed) {
            return NO;
        }
        self.completed = YES;
        self.faulted = YES;
        _error = error;
        [self runContinuations];
        return YES;
    }
}

- (nullable NSException *)exception {
    @synchronized(self.lock) {
        return _exception;
    }
}

- (BOOL)trySetException:(NSException *)exception {
    @synchronized(self.lock) {
        if (self.completed) {
            return NO;
        }
        self.completed = YES;
        self.faulted = YES;
        _exception = exception;
        [self runContinuations];
        return YES;
    }
}

- (BOOL)isCancelled {
    @synchronized(self.lock) {
        return _cancelled;
    }
}

- (BOOL)isFaulted {
    @synchronized(self.lock) {
        return _faulted;
    }
}

- (BOOL)trySetCancelled {
    @synchronized(self.lock) {
        if (self.completed) {
            return NO;
        }
        self.completed = YES;
        self.cancelled = YES;
        [self runContinuations];
        return YES;
    }
}

- (BOOL)isCompleted {
    @synchronized(self.lock) {
        return _completed;
    }
}

- (void)runContinuations {
    @synchronized(self.lock) {
        [self.condition lock];
        [self.condition broadcast];
        [self.condition unlock];
        for (void (^callback)() in self.callbacks) {
            callback();
        }
        [self.callbacks removeAllObjects];
    }
}

#pragma mark - Chaining methods

- (BOSTask *)continueWithExecutor:(BOSExecutor *)executor withBlock:(BOSContinuationBlock)block {
    return [self continueWithExecutor:executor block:block cancellationToken:nil];
}

- (BOSTask *)continueWithExecutor:(BOSExecutor *)executor
                           block:(BOSContinuationBlock)block
               cancellationToken:(nullable BOSCancellationToken *)cancellationToken {
    BOSTaskCompletionSource *tcs = [BOSTaskCompletionSource taskCompletionSource];

    // Capture all of the state that needs to used when the continuation is complete.
    dispatch_block_t executionBlock = ^{
        if (cancellationToken.cancellationRequested) {
            [tcs cancel];
            return;
        }

        id result = nil;
        @try {
            result = block(self);
        } @catch (NSException *exception) {
            tcs.exception = exception;
            return;
        }

        if ([result isKindOfClass:[BOSTask class]]) {

            id (^setupWithTask) (BOSTask *) = ^id(BOSTask *task) {
                if (cancellationToken.cancellationRequested || task.cancelled) {
                    [tcs cancel];
                } else if (task.exception) {
                    tcs.exception = task.exception;
                } else if (task.error) {
                    tcs.error = task.error;
                } else {
                    tcs.result = task.result;
                }
                return nil;
            };

            BOSTask *resultTask = (BOSTask *)result;

            if (resultTask.completed) {
                setupWithTask(resultTask);
            } else {
                [resultTask continueWithBlock:setupWithTask];
            }

        } else {
            tcs.result = result;
        }
    };

    BOOL completed;
    @synchronized(self.lock) {
        completed = self.completed;
        if (!completed) {
            [self.callbacks addObject:[^{
                [executor execute:executionBlock];
            } copy]];
        }
    }
    if (completed) {
        [executor execute:executionBlock];
    }

    return tcs.task;
}

- (BOSTask *)continueWithBlock:(BOSContinuationBlock)block {
    return [self continueWithExecutor:[BOSExecutor defaultExecutor] block:block cancellationToken:nil];
}

- (BOSTask *)continueWithBlock:(BOSContinuationBlock)block cancellationToken:(nullable BOSCancellationToken *)cancellationToken {
    return [self continueWithExecutor:[BOSExecutor defaultExecutor] block:block cancellationToken:cancellationToken];
}

- (BOSTask *)continueWithExecutor:(BOSExecutor *)executor
                withSuccessBlock:(BOSContinuationBlock)block {
    return [self continueWithExecutor:executor successBlock:block cancellationToken:nil];
}

- (BOSTask *)continueWithExecutor:(BOSExecutor *)executor
                    successBlock:(BOSContinuationBlock)block
               cancellationToken:(nullable BOSCancellationToken *)cancellationToken {
    if (cancellationToken.cancellationRequested) {
        return [BOSTask cancelledTask];
    }

    return [self continueWithExecutor:executor block:^id(BOSTask *task) {
        if (task.faulted || task.cancelled) {
            return task;
        } else {
            return block(task);
        }
    } cancellationToken:cancellationToken];
}

- (BOSTask *)continueWithSuccessBlock:(BOSContinuationBlock)block {
    return [self continueWithExecutor:[BOSExecutor defaultExecutor] successBlock:block cancellationToken:nil];
}

- (BOSTask *)continueWithSuccessBlock:(BOSContinuationBlock)block cancellationToken:(nullable BOSCancellationToken *)cancellationToken {
    return [self continueWithExecutor:[BOSExecutor defaultExecutor] successBlock:block cancellationToken:cancellationToken];
}

#pragma mark - Syncing Task (Avoid it)

- (void)warnOperationOnMainThread {
    warnBlockingOperationOnMainThread();
}

- (void)waitUntilFinished {
    if ([NSThread isMainThread]) {
        [self warnOperationOnMainThread];
    }

    @synchronized(self.lock) {
        if (self.completed) {
            return;
        }
        [self.condition lock];
    }
    while (!self.completed) {
        [self.condition wait];
    }
    [self.condition unlock];
}

#pragma mark - NSObject

- (NSString *)description {
    // Acquire the data from the locked properties
    BOOL completed;
    BOOL cancelled;
    BOOL faulted;
    NSString *resultDescription = nil;

    @synchronized(self.lock) {
        completed = self.completed;
        cancelled = self.cancelled;
        faulted = self.faulted;
        resultDescription = completed ? [NSString stringWithFormat:@" result = %@", self.result] : @"";
    }

    // Description string includes status information and, if available, the
    // result since in some ways this is what a promise actually "is".
    return [NSString stringWithFormat:@"<%@: %p; completed = %@; cancelled = %@; faulted = %@;%@>",
            NSStringFromClass([self class]),
            self,
            completed ? @"YES" : @"NO",
            cancelled ? @"YES" : @"NO",
            faulted ? @"YES" : @"NO",
            resultDescription];
}

@end

NS_ASSUME_NONNULL_END
