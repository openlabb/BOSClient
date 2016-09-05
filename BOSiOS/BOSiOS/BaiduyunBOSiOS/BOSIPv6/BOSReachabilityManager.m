//
//  BOSReachabilityManager.m
//
//  Created by 亿刀 on 14-1-9.
//  Edited by junmo on 15-5-16
//  Edited by zhouzhuo on 2016/5/22
//  Copyright (c) 2014年 Twitter. All rights reserved.
//

#import "BOSReachabilityManager.h"
#import "BOSIPv6Adapter.h"
#import "BOSLog.h"

#import <arpa/inet.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <sys/socket.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <UIKit/UIDevice.h>

static char *const BOSReachabilityQueueIdentifier = "com.alibaba.BOS.network.ReachabilityQueue";
static dispatch_queue_t reachabilityQueue;
static NSString *const CHECK_HOSTNAME = @"www.baidu.com";

@implementation BOSReachabilityManager {
    SCNetworkReachabilityRef            _reachabilityRef;
}

+ (BOSReachabilityManager *)shareInstance
{
    static BOSReachabilityManager *s_SPDYNetworkStatusManager = nil;
    
    @synchronized([self class])
    {
        if (!s_SPDYNetworkStatusManager)
        {
            s_SPDYNetworkStatusManager = [[BOSReachabilityManager alloc] init];
        }
    }
    
    return s_SPDYNetworkStatusManager;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        _reachabilityRef =  SCNetworkReachabilityCreateWithName(NULL, [CHECK_HOSTNAME UTF8String]);

        //开始监控网络变化
        [self _startNotifier];
    }

    return self;
}

- (BOOL)_startNotifier
{
    if (!_reachabilityRef)
    {
        _reachabilityRef =  SCNetworkReachabilityCreateWithName(NULL, [CHECK_HOSTNAME UTF8String]);
    }

    if (_reachabilityRef)
    {
        SCNetworkReachabilityContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
        
        if(SCNetworkReachabilitySetCallback(_reachabilityRef, ReachabilityCallback, &context))
        {
            reachabilityQueue = dispatch_queue_create(BOSReachabilityQueueIdentifier, DISPATCH_QUEUE_SERIAL);
            SCNetworkReachabilitySetDispatchQueue(_reachabilityRef, reachabilityQueue);

            return YES;
        }
    }
    return NO;
}

//网络变化回调函数
static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info)
{
    if ([[BOSIPv6Adapter getInstance] isIPv6OnlyNetwork]) {
        BOSLogDebug(@"[AlicloudReachabilityManager]: Network changed, Pre network status is IPv6-Only.");
    } else {
        BOSLogDebug(@"[AlicloudReachabilityManager]: Network changed, Pre network status is not IPv6-Only.");
    }

    [[BOSIPv6Adapter getInstance] reResolveIPv6OnlyStatus];
}

@end