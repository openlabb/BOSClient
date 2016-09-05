/*
 *  Copyright (c) 2014, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "BOSCancellationToken.h"
#import "BOSCancellationTokenRegistration.h"

NS_ASSUME_NONNULL_BEGIN

@interface BOSCancellationToken ()

@property (nullable, nonatomic, strong) NSMutableArray *registrations;
@property (nonatomic, strong) NSObject *lock;
@property (nonatomic) BOOL disposed;

@end

@interface BOSCancellationTokenRegistration (BOSCancellationToken)

+ (instancetype)registrationWithToken:(BOSCancellationToken *)token delegate:(BOSCancellationBlock)delegate;

- (void)notifyDelegate;

@end

@implementation BOSCancellationToken

@synthesize cancellationRequested = _cancellationRequested;

#pragma mark - Initializer

- (instancetype)init {
    self = [super init];
    if (!self) return self;

    _registrations = [NSMutableArray array];
    _lock = [NSObject new];

    return self;
}

#pragma mark - Custom Setters/Getters

- (BOOL)isCancellationRequested {
    @synchronized(self.lock) {
        [self throwIfDisposed];
        return _cancellationRequested;
    }
}

- (void)cancel {
    NSArray *registrations;
    @synchronized(self.lock) {
        [self throwIfDisposed];
        if (_cancellationRequested) {
            return;
        }
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(cancelPrivate) object:nil];
        _cancellationRequested = YES;
        registrations = [self.registrations copy];
    }

    [self notifyCancellation:registrations];
}

- (void)notifyCancellation:(NSArray *)registrations {
    for (BOSCancellationTokenRegistration *registration in registrations) {
        [registration notifyDelegate];
    }
}

- (BOSCancellationTokenRegistration *)registerCancellationObserverWithBlock:(BOSCancellationBlock)block {
    @synchronized(self.lock) {
        BOSCancellationTokenRegistration *registration = [BOSCancellationTokenRegistration registrationWithToken:self delegate:[block copy]];
        [self.registrations addObject:registration];

        return registration;
    }
}

- (void)unregisterRegistration:(BOSCancellationTokenRegistration *)registration {
    @synchronized(self.lock) {
        [self throwIfDisposed];
        [self.registrations removeObject:registration];
    }
}

// Delay on a non-public method to prevent interference with a user calling performSelector or
// cancelPreviousPerformRequestsWithTarget on the public method
- (void)cancelPrivate {
    [self cancel];
}

- (void)cancelAfterDelay:(int)millis {
    [self throwIfDisposed];
    if (millis < -1) {
        [NSException raise:NSInvalidArgumentException format:@"Delay must be >= -1"];
    }

    if (millis == 0) {
        [self cancel];
        return;
    }

    @synchronized(self.lock) {
        [self throwIfDisposed];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(cancelPrivate) object:nil];
        if (self.cancellationRequested) {
            return;
        }

        if (millis != -1) {
            double delay = (double)millis / 1000;
            [self performSelector:@selector(cancelPrivate) withObject:nil afterDelay:delay];
        }
    }
}

- (void)dispose {
    @synchronized(self.lock) {
        if (self.disposed) {
            return;
        }
        [self.registrations makeObjectsPerformSelector:@selector(dispose)];
        self.registrations = nil;
        self.disposed = YES;
    }
}

- (void)throwIfDisposed {
    if (self.disposed) {
        [NSException raise:NSInternalInconsistencyException format:@"Object already disposed"];
    }
}

@end

NS_ASSUME_NONNULL_END
