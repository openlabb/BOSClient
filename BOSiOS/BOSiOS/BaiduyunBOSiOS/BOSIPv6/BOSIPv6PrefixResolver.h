//
//  BOSIPv6PrefixResolver.h
//
//  Created by lingkun on 16/5/16.
//  Edit by zhouzhuo on 16/5/22
//  Copyright © 2016年 Ali. All rights reserved.
//

#ifndef AlicloudIPv6PrefixResolver_h
#define AlicloudIPv6PrefixResolver_h
#import <Foundation/Foundation.h>

@interface BOSIPv6PrefixResolver : NSObject

+ (instancetype)getInstance;

- (void)updateIPv6Prefix;

- (NSString *)convertIPv4toIPv6:(NSString *)ipv4;

@end

#endif /* BOSIPv6PrefixResolver_h */
