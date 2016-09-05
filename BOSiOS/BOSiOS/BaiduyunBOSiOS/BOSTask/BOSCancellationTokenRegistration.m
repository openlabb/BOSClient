/*
 *  Copyright (c) 2014, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "BOSCancellationTokenRegistration.h"

#import "BOSCancellationToken.h"

NS_ASSUME_NONNULL_BEGIN

@interface BOSCancellationTokenRegistration ()

@property (nonatomic, weak) BOSCancellationToken *token;
@property (nullable, nonatomic, strong) BOSCancellationBlock cancellationObserverBlock;
@property (nonatomic, strong) NSObject *lock;
@property (nonatomic) BOOL disposed;

@end

@interface BOSCancellationToken (BOSCancellationTokenRegistration)

- (void)unregisterRegistration:(BOSCancellationTokenRegistration *)registration;

@end

@implementation BOSCancellationTokenRegistration

+ (instancetype)registrationWithToken:(BOSCancellationToken *)token delegate:(BOSCancellationBlock)delegate {
    BOSCancellationTokenRegistration *registration = [BOSCancellationTokenRegistration new];
    registration.token = token;
    registration.cancellationObserverBlock = delegate;
    return registration;
}

- (instancetype)init {
    self = [super init];
    if (!self) return self;

    _lock = [NSObject new];
    
    return self;
}

- (void)dispose {
    @synchronized(self.lock) {
        if (self.disposed) {
            return;
        }
        self.disposed = YES;
    }

    BOSCancellationToken *token = self.token;
    if (token != nil) {
        [token unregisterRegistration:self];
        self.token = nil;
    }
    self.cancellationObserverBlock = nil;
}

- (void)notifyDelegate {
    @synchronized(self.lock) {
        [self throwIfDisposed];
        self.cancellationObserverBlock();
    }
}

- (void)throwIfDisposed {
    NSAssert(!self.disposed, @"Object already disposed");
}

@end

NS_ASSUME_NONNULL_END
