//
//  LPActionManager.m
//  Leanplum
//
//  Created by Andrew First on 9/12/13.
//  Copyright (c) 2013 Leanplum, Inc. All rights reserved.
//
//  Licensed to the Apache Software Foundation (ASF) under one
//  or more contributor license agreements.  See the NOTICE file
//  distributed with this work for additional information
//  regarding copyright ownership.  The ASF licenses this file
//  to you under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the License is distributed on an
//  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
//  KIND, either express or implied.  See the License for the
//  specific language governing permissions and limitations
//  under the License.

#import "LPActionManager.h"

#import "Constants.h"
#import "JRSwizzle.h"
#import "LeanplumInternal.h"
#import "LeanplumRequest.h"
#import "LPFileManager.h"
#import "LPVarCache.h"
#import "LPUIAlert.h"
#import "LeanplumRequest.h"
#import "LPMessageTemplates.h"

#import <objc/runtime.h>
#import <objc/message.h>

LeanplumMessageMatchResult LeanplumMessageMatchResultMake(BOOL matchedTrigger, BOOL matchedUnlessTrigger, BOOL matchedLimit)
{
    LeanplumMessageMatchResult result;
    result.matchedTrigger = matchedTrigger;
    result.matchedUnlessTrigger = matchedUnlessTrigger;
    result.matchedLimit = matchedLimit;
    return result;
}

@implementation NSObject (LeanplumExtension)

- (NSString *)leanplum_createTokenKey
{
    return [NSString stringWithFormat:
            LEANPLUM_DEFAULTS_PUSH_TOKEN_KEY,
            LeanplumRequest.appId, LeanplumRequest.userId, LeanplumRequest.deviceId];
}

- (void)leanplum_disableAskToAsk
{
#if LP_NOT_TV
    Class userMessageTemplatesClass = NSClassFromString(@"LPMessageTemplates");
    if (userMessageTemplatesClass &&
        [[userMessageTemplatesClass sharedTemplates] respondsToSelector:@selector(disableAskToAsk)]) {
        [[userMessageTemplatesClass sharedTemplates] disableAskToAsk];
    } else {
        [[LPMessageTemplatesClass sharedTemplates] disableAskToAsk];
    }
#endif
}

- (void)leanplum_application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    LP_TRY
    if (![[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        // In pre-ios 8, didRegisterForRemoteNotificationsWithDeviceToken has combined semantics with
        // didRegisterUserNotificationSettings and the ask to push will have been triggered.
        [self leanplum_disableAskToAsk];
    }
    
    // Send push token on every launch. This is required because push token may not be sent if the
    // user force quit the app. This is due to how LPRequestStorage keeps the data in memory and
    // we don't support response block on batch.
    NSString *formattedToken = [deviceToken description];
    formattedToken = [[[formattedToken stringByReplacingOccurrencesOfString:@"<" withString:@""]
                       stringByReplacingOccurrencesOfString:@">" withString:@""]
                      stringByReplacingOccurrencesOfString:@" " withString:@""];
    [Leanplum onStartResponse:^(BOOL success) {
        LP_END_USER_CODE
        [[LeanplumRequest post:LP_METHOD_SET_DEVICE_ATTRIBUTES
                        params:@{LP_PARAM_DEVICE_PUSH_TOKEN: formattedToken}] send];
        LP_BEGIN_USER_CODE
    }];

    // Update push token if it's different.
    NSString *tokenKey = [self leanplum_createTokenKey];
    NSString *existingToken = [[NSUserDefaults standardUserDefaults] stringForKey:tokenKey];
    if (![existingToken isEqualToString: formattedToken]) {
        [[NSUserDefaults standardUserDefaults] setObject: formattedToken forKey:tokenKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    LP_END_TRY

    // Call overridden method.
    if ([LPActionManager sharedManager]->swizzledApplicationDidRegisterRemoteNotifications &&
        [self respondsToSelector:@selector(leanplum_application:didRegisterForRemoteNotificationsWithDeviceToken:)]) {
        [self performSelector:@selector(leanplum_application:didRegisterForRemoteNotificationsWithDeviceToken:)
                   withObject:application withObject:deviceToken];
    }
}

- (NSString *)leanplum_createUserNotificationSettingsKey
{
    return [NSString stringWithFormat:
            LEANPLUM_DEFAULTS_USER_NOTIFICATION_SETTINGS_KEY,
            LeanplumRequest.appId, LeanplumRequest.userId, LeanplumRequest.deviceId];
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000 && LP_NOT_TV

- (void)leanplum_application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
    LP_TRY
    [self leanplum_disableAskToAsk];

    [[LPActionManager sharedManager] sendUserNotificationSettingsIfChanged:notificationSettings];

    LP_END_TRY

    // Call overridden method.
    if ([LPActionManager sharedManager]->swizzledApplicationDidRegisterUserNotificationSettings &&
        [self respondsToSelector:@selector(leanplum_application:didRegisterUserNotificationSettings:)]) {
        [self performSelector:@selector(leanplum_application:didRegisterUserNotificationSettings:)
                   withObject:application withObject:notificationSettings];
    }
}

#endif

- (void)leanplum_application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    LP_TRY
    [self leanplum_disableAskToAsk];
    NSString *tokenKey = [self leanplum_createTokenKey];
    if ([[NSUserDefaults standardUserDefaults] stringForKey:tokenKey]) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:tokenKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    LP_END_TRY

    // Call overridden method.
    if ([LPActionManager sharedManager]->swizzledApplicationDidFailToRegisterForRemoteNotificationsWithError &&
        [self respondsToSelector:@selector(leanplum_application:didFailToRegisterForRemoteNotificationsWithError:)]) {
        [self performSelector:@selector(leanplum_application:didFailToRegisterForRemoteNotificationsWithError:)
                   withObject:application withObject:error];
    }
}

- (void)leanplum_application:(UIApplication *)application
didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    LP_TRY
    [[LPActionManager sharedManager] didReceiveRemoteNotification:userInfo
                                                       withAction:nil
                                           fetchCompletionHandler:nil];
    LP_END_TRY

    // Call overridden method.
    if ([LPActionManager sharedManager]->swizzledApplicationDidReceiveRemoteNotification &&
        [self respondsToSelector:@selector(leanplum_application:didReceiveRemoteNotification:)]) {
        [self performSelector:@selector(leanplum_application:didReceiveRemoteNotification:)
                   withObject:application withObject:userInfo];
    }
}

- (void)leanplum_application:(UIApplication *)application
didReceiveRemoteNotification:(NSDictionary *)userInfo
      fetchCompletionHandler:(LeanplumFetchCompletionBlock)completionHandler
{
    LPInternalState *state = [LPInternalState sharedState];
    state.calledHandleNotification = NO;
    LeanplumFetchCompletionBlock leanplumCompletionHandler;

    // Call overridden method.
    if ([LPActionManager sharedManager]->swizzledApplicationDidReceiveRemoteNotificationWithCompletionHandler &&
        [self respondsToSelector:@selector(leanplum_application:didReceiveRemoteNotification:fetchCompletionHandler:)]) {
        leanplumCompletionHandler = nil;
        [self leanplum_application:application didReceiveRemoteNotification:userInfo fetchCompletionHandler:completionHandler];
    } else {
        leanplumCompletionHandler = completionHandler;
    }

    // Prevents handling the notification twice if the original method calls handleNotification
    // explicitly.
    if (!state.calledHandleNotification) {
        LP_TRY
        [[LPActionManager sharedManager] didReceiveRemoteNotification:userInfo
                                                           withAction:nil
                                               fetchCompletionHandler:leanplumCompletionHandler];
        LP_END_TRY
    }
    state.calledHandleNotification = NO;
}

#if LP_NOT_TV
- (void)leanplum_userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
      withCompletionHandler:(void (^)())completionHandler
{
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    LPInternalState *state = [LPInternalState sharedState];
    state.calledHandleNotification = NO;
    LeanplumFetchCompletionBlock leanplumCompletionHandler =
        ^(LeanplumUIBackgroundFetchResult result) {
            completionHandler();
        };

    // Call overridden method.
    SEL selector = @selector(leanplum_userNotificationCenter:didReceiveNotificationResponse:
                             withCompletionHandler:);
    LPActionManager *manager = [LPActionManager sharedManager];
    if (manager->swizzledUserNotificationCenterDidReceiveNotificationResponseWithCompletionHandler
            && [self respondsToSelector:selector]) {
        leanplumCompletionHandler = nil;
        [self leanplum_userNotificationCenter:center
                didReceiveNotificationResponse:response
                       withCompletionHandler:completionHandler];
    }

    // Prevents handling the notification twice if the original method calls handleNotification
    // explicitly.
    if (!state.calledHandleNotification) {
        LP_TRY
        [[LPActionManager sharedManager] didReceiveRemoteNotification:userInfo
                                                           withAction:nil
                                               fetchCompletionHandler:leanplumCompletionHandler];
        LP_END_TRY
    }
    state.calledHandleNotification = NO;
}
#endif

#if LP_NOT_TV
- (void)leanplum_application:(UIApplication *)application
 didReceiveLocalNotification:(UILocalNotification *)localNotification
{
    NSDictionary *userInfo = [localNotification userInfo];

    LP_TRY
    [[LPActionManager sharedManager] didReceiveRemoteNotification:userInfo
                                                       withAction:nil
                                           fetchCompletionHandler:nil];
    LP_END_TRY

    // Call overridden method.
    if ([LPActionManager sharedManager]->swizzledApplicationDidReceiveLocalNotification &&
        [self respondsToSelector:@selector(leanplum_application:didReceiveLocalNotification:)]) {
        [self performSelector:@selector(leanplum_application:didReceiveLocalNotification:)
                   withObject:application withObject:localNotification];
    }
}
#endif

@end

@implementation LPContextualValues

@end

@implementation LPActionManager

static LPActionManager *leanplum_sharedActionManager = nil;
static dispatch_once_t leanplum_onceToken;

+ (LPActionManager *)sharedManager
{
    dispatch_once(&leanplum_onceToken, ^{
        leanplum_sharedActionManager = [[self alloc] init];
    });
    return leanplum_sharedActionManager;
}

// Used for unit testing.
+ (void)reset
{
    leanplum_sharedActionManager = nil;
    leanplum_onceToken = 0;
}

- (id)init
{
    if (self = [super init]) {
        [self listenForPushNotifications];
#if LP_NOT_TV
        [self listenForLocalNotifications];
#endif
        _sessionOccurrences = [NSMutableDictionary dictionary];
        _messageImpressionOccurrences = [NSMutableDictionary dictionary];
        _messageTriggerOccurrences = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - Push Notifications

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000 && LP_NOT_TV
- (void)sendUserNotificationSettingsIfChanged:(UIUserNotificationSettings *)notificationSettings
{
    // Send settings.
    NSString *settingsKey = [self leanplum_createUserNotificationSettingsKey];
    NSDictionary *existingSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:settingsKey];
    NSNumber *types = @([notificationSettings types]);
    NSMutableArray *categories = [NSMutableArray array];
    for (UIMutableUserNotificationCategory *category in [notificationSettings categories]) {
        if ([category identifier]) {
            // Skip categories that have no identifier.
            [categories addObject:[category identifier]];
        }
    }
    NSArray *sortedCategories = [categories sortedArrayUsingSelector:@selector(compare:)];
    NSDictionary *settings = @{LP_PARAM_DEVICE_USER_NOTIFICATION_TYPES: types,
                               LP_PARAM_DEVICE_USER_NOTIFICATION_CATEGORIES: sortedCategories};
    if (![existingSettings isEqualToDictionary:settings]) {
        [[NSUserDefaults standardUserDefaults] setObject:settings forKey:settingsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSString *tokenKey = [self leanplum_createTokenKey];
        NSString *existingToken = [[NSUserDefaults standardUserDefaults] stringForKey:tokenKey];
        NSMutableDictionary *params = [@{
                LP_PARAM_DEVICE_USER_NOTIFICATION_TYPES: types,
                LP_PARAM_DEVICE_USER_NOTIFICATION_CATEGORIES:
                      [LPJSON stringFromJSON:sortedCategories] ?: @""} mutableCopy];
        if (existingToken) {
            params[LP_PARAM_DEVICE_PUSH_TOKEN] = existingToken;
        }
        [Leanplum onStartResponse:^(BOOL success) {
            LP_END_USER_CODE
            [[LeanplumRequest post:LP_METHOD_SET_DEVICE_ATTRIBUTES params:params] send];
            LP_BEGIN_USER_CODE
        }];
    }
}
#endif

// Block to run to decide whether to show the notification
// when it is received while the app is running.
- (void)setShouldHandleNotification:(LeanplumShouldHandleNotificationBlock)block
{
    shouldHandleNotification = block;
}

- (void)requireMessageContent:(NSString *)messageId
          withCompletionBlock:(LeanplumVariablesChangedBlock)onCompleted
{
    [Leanplum onceVariablesChangedAndNoDownloadsPending:^{
        LP_END_USER_CODE
        if (!messageId || LPVarCache.messages[messageId]) {
            onCompleted();
        } else {
            // Try downloading the messages again if it doesn't exist.
            // Maybe the message was created while the app was running.
            LeanplumRequest *req = [LeanplumRequest
                                    post:LP_METHOD_GET_VARS
                                    params:@{
                                             LP_PARAM_INCLUDE_DEFAULTS: @(NO),
                                             LP_PARAM_INCLUDE_MESSAGE_ID: messageId
                                             }];
            [req onResponse:^(id<LPNetworkOperationProtocol> operation, id json) {
                LP_TRY
                NSDictionary *getVariablesResponse = [LPResponse getLastResponse:json];
                NSDictionary *values = getVariablesResponse[LP_KEY_VARS];
                NSDictionary *messages = getVariablesResponse[LP_KEY_MESSAGES];
                NSArray *updateRules = getVariablesResponse[LP_KEY_UPDATE_RULES];
                NSArray *eventRules = getVariablesResponse[LP_KEY_EVENT_RULES];
                NSArray *variants = getVariablesResponse[LP_KEY_VARIANTS];
                NSDictionary *regions = getVariablesResponse[LP_KEY_REGIONS];
                if (![LPConstantsState sharedState].canDownloadContentMidSessionInProduction ||
                    [values isEqualToDictionary:LPVarCache.diffs]) {
                    values = nil;
                }
                if ([messages isEqualToDictionary:LPVarCache.messageDiffs]) {
                    messages = nil;
                }
                if ([updateRules isEqualToArray:LPVarCache.updateRulesDiffs]) {
                    updateRules = nil;
                }
                if ([eventRules isEqualToArray:LPVarCache.updateRulesDiffs]) {
                    eventRules = nil;
                }
                if ([regions isEqualToDictionary:LPVarCache.regions]) {
                    regions = nil;
                }
                if (values || messages || updateRules || eventRules || regions) {
                    [LPVarCache applyVariableDiffs:values
                                          messages:messages
                                       updateRules:updateRules
                                        eventRules:eventRules
                                          variants:variants
                                           regions:regions];
                    onCompleted();
                }
                LP_END_TRY
             }];
            [req sendIfConnected];
        }
        LP_BEGIN_USER_CODE
    }];
}

+ (NSString *)messageIdFromUserInfo:(NSDictionary *)userInfo
{
    NSString *messageId = [userInfo[LP_KEY_PUSH_MESSAGE_ID] description];
    if (messageId == nil) {
        messageId = [userInfo[LP_KEY_PUSH_MUTE_IN_APP] description];
        if (messageId == nil) {
            messageId = [userInfo[LP_KEY_PUSH_NO_ACTION] description];
            if (messageId == nil) {
                messageId = [userInfo[LP_KEY_PUSH_NO_ACTION_MUTE] description];
            }
        }
    }
    return messageId;
}

- (BOOL)isDuplicateNotification:(NSDictionary *)userInfo
{
    if ([notificationHandled isEqualToString:[LPJSON stringFromJSON:userInfo]] &&
        [[NSDate date] timeIntervalSinceDate:notificationHandledTime] < 10.0) {
        return YES;
    }

    notificationHandled = [LPJSON stringFromJSON:userInfo];
    notificationHandledTime = [NSDate date];
    return NO;
}

// Performs the notification action if
// (a) The app wasn't active before
// (b) The user accepts that they want to view the notification
- (void)maybePerformNotificationActions:(NSDictionary *)userInfo
                                 action:(NSString *)action
                                 active:(BOOL)active
{
    // Don't handle duplicate notifications.
    if ([self isDuplicateNotification:userInfo]) {
        return;
    }

    LPLog(LPInfo, @"Handling push notification");
    NSString *messageId = [LPActionManager messageIdFromUserInfo:userInfo];
    NSString *actionName;
    if (action == nil) {
        actionName = LP_VALUE_DEFAULT_PUSH_ACTION;
    } else {
        actionName = [NSString stringWithFormat:@"iOS options.Custom actions.%@", action];
    }
    LPActionContext *context;
    if ([LPActionManager areActionsEmbedded:userInfo]) {
        NSMutableDictionary *args = [NSMutableDictionary dictionary];
        if (action) {
            args[actionName] = userInfo[LP_KEY_PUSH_CUSTOM_ACTIONS][action];
        } else {
            args[actionName] = userInfo[LP_KEY_PUSH_ACTION];
        }
        context = [LPActionContext actionContextWithName:LP_PUSH_NOTIFICATION_ACTION
                                                    args:args
                                               messageId:messageId];
        [context preventRealtimeUpdating];
    } else {
        context = [Leanplum createActionContextForMessageId:messageId];
    }
    [context maybeDownloadFiles];

    LeanplumVariablesChangedBlock handleNotificationBlock = ^{
        [context runTrackedActionNamed:actionName];
    };

    if (!active) {
        handleNotificationBlock();
    } else {
        if (shouldHandleNotification) {
            shouldHandleNotification(userInfo, handleNotificationBlock);
        } else {
            if (userInfo[LP_KEY_PUSH_NO_ACTION] ||
                userInfo[LP_KEY_PUSH_NO_ACTION_MUTE]) {
                handleNotificationBlock();
            } else {
                id message = userInfo[@"aps"][@"alert"];
                if ([message isKindOfClass:NSDictionary.class]) {
                    message = message[@"body"];
                }
                if (message) {
                    [LPUIAlert showWithTitle:APP_NAME
                                     message:message
                           cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                           otherButtonTitles:@[NSLocalizedString(@"View", nil)]
                                       block:^(NSInteger buttonIndex) {
                                           if (buttonIndex == 1) {
                                               handleNotificationBlock();
                                           }
                                       }];
                }
            }
        }
    }
}

- (BOOL)hasTrackedDisplayed:(NSDictionary *)userInfo
{
    if ([displayedTracked isEqualToString:[LPJSON stringFromJSON:userInfo]] &&
        [[NSDate date] timeIntervalSinceDate:displayedTrackedTime] < 10.0) {
        return YES;
    }

    displayedTracked = [LPJSON stringFromJSON:userInfo];
    displayedTrackedTime = [NSDate date];
    return NO;
}

- (void)trackMessageDisplayed:(NSDictionary *)userInfo
{
    // Don't track duplicate notifications.
    if ([self hasTrackedDisplayed:userInfo]) {
        return;
    }

    NSString *messageId = [LPActionManager messageIdFromUserInfo:userInfo];
    [Leanplum track:@"Displayed" withValue:0.0 andInfo:nil
            andArgs:@{LP_PARAM_MESSAGE_ID: messageId} andParameters:nil];
}

+ (BOOL)areActionsEmbedded:(NSDictionary *)userInfo
{
    return userInfo[LP_KEY_PUSH_ACTION] != nil ||
        userInfo[LP_KEY_PUSH_CUSTOM_ACTIONS] != nil;
}

// Handles the notification.
// Makes sure the data is loaded, and then displays the notification.
- (void)handleNotification:(NSDictionary *)userInfo
                withAction:(NSString *)action
                 appActive:(BOOL)active
         completionHandler:(LeanplumFetchCompletionBlock)completionHandler
{
    // Don't handle non-Leanplum notifications.
    NSString *messageId = [LPActionManager messageIdFromUserInfo:userInfo];
    if (messageId == nil) {
        return;
    }

    void (^onContent)() = ^{
#if LP_NOT_TV
        if (completionHandler && SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
            completionHandler(UIBackgroundFetchResultNewData);
        }
#endif
        BOOL hasAlert = userInfo[@"aps"][@"alert"] != nil;
        if (hasAlert) {
            UIApplicationState appState = [[UIApplication sharedApplication] applicationState];
            if (appState != UIApplicationStateBackground) {
                [self maybePerformNotificationActions:userInfo action:action active:active];
            } else {
                [self trackMessageDisplayed:userInfo];
            }
        }
    };

    [Leanplum onStartIssued:^() {
        if ([LPActionManager areActionsEmbedded:userInfo]) {
            onContent();
        } else {
            [self requireMessageContent:messageId withCompletionBlock:onContent];
        }
    }];
}

- (void)didReceiveRemoteNotification:(NSDictionary *)userInfo
                          withAction:(NSString *)action
              fetchCompletionHandler:(LeanplumFetchCompletionBlock)completionHandler
{
    // If app was inactive, then handle notification because the user tapped it.
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
        [self handleNotification:userInfo
                      withAction:action
                       appActive:NO
               completionHandler:completionHandler];
        return;
    } else {
        // Application is active.
        // Hide notifications that should be muted.
        if (!userInfo[LP_KEY_PUSH_MUTE_IN_APP] &&
            !userInfo[LP_KEY_PUSH_NO_ACTION_MUTE]) {
            [self handleNotification:userInfo
                          withAction:action
                           appActive:YES
                   completionHandler:completionHandler];
            return;
        }
    }
#if LP_NOT_TV
    // Call the completion handler only for Leanplum notifications.
    NSString *messageId = [LPActionManager messageIdFromUserInfo:userInfo];
    if (messageId && completionHandler &&
        SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        completionHandler(UIBackgroundFetchResultNoData);
    }
#endif
}

// Listens for push notifications.
- (void)listenForPushNotifications
{
    id appDelegate = [[UIApplication sharedApplication] delegate];
    if (appDelegate && [NSStringFromClass([appDelegate class])
                        rangeOfString:@"AppDelegateProxy"].location != NSNotFound) {
        @try {
            SEL selector = NSSelectorFromString(@"originalAppDelegate");
            IMP imp = [appDelegate methodForSelector:selector];
            id (*func)(id, SEL) = (void *)imp;
            id originalAppDelegate = func(appDelegate, selector);
            if (originalAppDelegate) {
                appDelegate = originalAppDelegate;
            }
        }
        @catch (NSException *exception) {
            // Ignore. Means that app delegate doesn't repsond to the selector.
            // Can't use respondsToSelector since proxies override this method so that
            // it doesn't work for this particular selector.
        }
    }

    // Detect when registered for push notifications.
    swizzledApplicationDidRegisterRemoteNotifications =
    [LPSwizzle hookInto:@selector(application:didRegisterForRemoteNotificationsWithDeviceToken:)
           withSelector:@selector(leanplum_application:didRegisterForRemoteNotificationsWithDeviceToken:)
              forObject:[appDelegate class]];

#if LP_NOT_TV
    // Detect when registered for user notification types.
    swizzledApplicationDidRegisterUserNotificationSettings =
    [LPSwizzle hookInto:@selector(application:didRegisterUserNotificationSettings:)
           withSelector:@selector(leanplum_application:didRegisterUserNotificationSettings:)
              forObject:[appDelegate class]];
#endif
    
    // Detect when couldn't register for push notifications.
    swizzledApplicationDidFailToRegisterForRemoteNotificationsWithError =
    [LPSwizzle hookInto:@selector(application:didFailToRegisterForRemoteNotificationsWithError:)
           withSelector:@selector(leanplum_application:didFailToRegisterForRemoteNotificationsWithError:)
              forObject:[appDelegate class]];
    
    // Detect push while app is running.
    SEL applicationDidReceiveRemoteNotificationSelector =
        @selector(application:didReceiveRemoteNotification:);
    Method applicationDidReceiveRemoteNotificationMethod = class_getInstanceMethod(
        [appDelegate class],
        applicationDidReceiveRemoteNotificationSelector);
    void (^swizzleApplicationDidReceiveRemoteNotification)(void) = ^{
        swizzledApplicationDidReceiveRemoteNotification =
        [LPSwizzle hookInto:applicationDidReceiveRemoteNotificationSelector
               withSelector:@selector(leanplum_application:
                                      didReceiveRemoteNotification:)
                  forObject:[appDelegate class]];
    };

    SEL applicationDidReceiveRemoteNotificationFetchCompletionHandlerSelector =
        @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:);
    Method applicationDidReceiveRemoteNotificationCompletionHandlerMethod = class_getInstanceMethod(
        [appDelegate class],
        applicationDidReceiveRemoteNotificationFetchCompletionHandlerSelector);
    void (^swizzleApplicationDidReceiveRemoteNotificationFetchCompletionHandler)(void) = ^{
        swizzledApplicationDidReceiveRemoteNotificationWithCompletionHandler =
        [LPSwizzle hookInto:applicationDidReceiveRemoteNotificationFetchCompletionHandlerSelector
               withSelector:@selector(leanplum_application:
                                      didReceiveRemoteNotification:
                                      fetchCompletionHandler:)
                  forObject:[appDelegate class]];
    };

    SEL userNotificationCenterDidReceiveNotificationResponseWithCompletionHandlerSelector =
    @selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:);
    Method userNotificationCenterDidReceiveNotificationResponseWithCompletionHandlerMethod =
    class_getInstanceMethod([appDelegate class],
            userNotificationCenterDidReceiveNotificationResponseWithCompletionHandlerSelector);
    void (^swizzleUserNotificationDidReceiveNotificationResponseWithCompletionHandler)(void) =^{
        swizzledUserNotificationCenterDidReceiveNotificationResponseWithCompletionHandler =
        [LPSwizzle hookInto:
         userNotificationCenterDidReceiveNotificationResponseWithCompletionHandlerSelector
               withSelector:@selector(leanplum_userNotificationCenter:
                                      didReceiveNotificationResponse:
                                      withCompletionHandler:)
                  forObject:[appDelegate class]];
    };

    if (!applicationDidReceiveRemoteNotificationMethod
        && !applicationDidReceiveRemoteNotificationCompletionHandlerMethod) {
        swizzleApplicationDidReceiveRemoteNotification();
        swizzleApplicationDidReceiveRemoteNotificationFetchCompletionHandler();
        if (NSClassFromString(@"UNUserNotificationCenter")) {
            swizzleUserNotificationDidReceiveNotificationResponseWithCompletionHandler();
        }
    } else {
        if (applicationDidReceiveRemoteNotificationMethod) {
            swizzleApplicationDidReceiveRemoteNotification();
        }
        if (applicationDidReceiveRemoteNotificationCompletionHandlerMethod) {
            swizzleApplicationDidReceiveRemoteNotificationFetchCompletionHandler();
        }
        if (NSClassFromString(@"UNUserNotificationCenter")) {
            if (userNotificationCenterDidReceiveNotificationResponseWithCompletionHandlerMethod) {
                swizzleUserNotificationDidReceiveNotificationResponseWithCompletionHandler();
            }
        }
    }

#if LP_NOT_TV && __IPHONE_OS_VERSION_MAX_REQUIRED >= 80000
    // Detect local notifications while app is running.
    swizzledApplicationDidReceiveLocalNotification =
    [LPSwizzle hookInto:@selector(application:didReceiveLocalNotification:)
           withSelector:@selector(leanplum_application:didReceiveLocalNotification:)
              forObject:[appDelegate class]];
    
    // Detect receiving notifications.
    [[NSNotificationCenter defaultCenter]
     addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil
     usingBlock:^(NSNotification *notification) {
         if (notification.userInfo) {
             NSDictionary *userInfo = notification.userInfo
                                       [UIApplicationLaunchOptionsRemoteNotificationKey];
             [self handleNotification:userInfo
                           withAction:nil
                            appActive:NO
                    completionHandler:nil];
         }
     }];
#endif
}

#pragma mark - Local Notifications
#if LP_NOT_TV
- (void)listenForLocalNotifications
{
    [Leanplum onAction:LP_PUSH_NOTIFICATION_ACTION invoke:^BOOL(LPActionContext *context) {
        LP_END_USER_CODE
        UIApplication *app = [UIApplication sharedApplication];

        BOOL contentAvailable = [context boolNamed:@"iOS options.Preload content"];
        NSString *message = [context stringNamed:@"Message"];

        // Don't send notification if the user doesn't have the permission enabled.
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
        if ([app respondsToSelector:@selector(currentUserNotificationSettings)]) {
            BOOL isSilentNotification = message.length == 0 && contentAvailable;
            if (!isSilentNotification) {
                UIUserNotificationSettings *currentSettings = [app currentUserNotificationSettings];
                if ([currentSettings types] == UIUserNotificationTypeNone) {
                    return NO;
                }
            }
        }
#endif

        NSString *messageId = [context private_MessageId];

        NSDictionary *messageConfig = LPVarCache.messageDiffs[messageId];
        
        NSNumber *countdown = messageConfig[@"countdown"];
        if ([context private_IsPreview]) {
            countdown = @(5.0);
        }
        if (![countdown.class isSubclassOfClass:NSNumber.class]) {
            LPLog(LPInternal, @"Invalid notification countdown: %@", countdown);
            return NO;
        }
        int countdownSeconds = [countdown intValue];
        NSDate *eta = [[NSDate date] dateByAddingTimeInterval:countdownSeconds];

        // If there's already one scheduled before the eta, discard this.
        // Otherwise, discard the scheduled one.
        NSArray *notifications = [app scheduledLocalNotifications];
        for (UILocalNotification *notification in notifications) {
            NSString *messageId = [LPActionManager messageIdFromUserInfo:[notification userInfo]];
            if ([messageId isEqualToString:[context private_MessageId]]) {
                NSComparisonResult comparison = [notification.fireDate compare:eta];
                if (comparison == NSOrderedAscending) {
                    return NO;
                } else {
                    [app cancelLocalNotification:notification];
                }
            }
        }

        UILocalNotification *localNotif = [[UILocalNotification alloc] init];
        localNotif.fireDate = eta;
        localNotif.timeZone = [NSTimeZone defaultTimeZone];
        if (message) {
            localNotif.alertBody = message;
        } else {
            localNotif.alertBody = LP_VALUE_DEFAULT_PUSH_MESSAGE;
        }
        localNotif.alertAction = @"View";

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
        if ([localNotif respondsToSelector:@selector(setCategory:)]) {
            NSString *category = [context stringNamed:@"iOS options.Category"];
            if (category) {
                localNotif.category = category;
            }
        }
#endif

        NSString *sound = [context stringNamed:@"iOS options.Sound"];
        if (sound) {
            localNotif.soundName = sound;
        } else {
            localNotif.soundName = UILocalNotificationDefaultSoundName;
        }

        NSString *badge = [context stringNamed:@"iOS options.Badge"];
        if (badge) {
            localNotif.applicationIconBadgeNumber = [badge intValue];
        }

        NSDictionary *userInfo = [context dictionaryNamed:@"Advanced options.Data"];
        NSString *openAction = [context stringNamed:LP_VALUE_DEFAULT_PUSH_ACTION];
        BOOL muteInsideApp = [context boolNamed:@"Advanced options.Mute inside app"];

        // Specify custom data for the notification
        NSMutableDictionary *mutableInfo;
        if (userInfo) {
            mutableInfo = [userInfo mutableCopy];
        } else {
            mutableInfo = [NSMutableDictionary dictionary];
        }
        
        // Adding body message manually.
        mutableInfo[@"aps"] = @{@"alert":@{@"body": message} };

        // Specify open action
        if (openAction) {
            if (muteInsideApp) {
                mutableInfo[LP_KEY_PUSH_MUTE_IN_APP] = messageId;
            } else {
                mutableInfo[LP_KEY_PUSH_MESSAGE_ID] = messageId;
            }
        } else {
            if (muteInsideApp) {
                mutableInfo[LP_KEY_PUSH_NO_ACTION_MUTE] = messageId;
            } else {
                mutableInfo[LP_KEY_PUSH_NO_ACTION] = messageId;
            }
        }

        localNotif.userInfo = mutableInfo;

        // Schedule the notification
        [app scheduleLocalNotification:localNotif];
        
        if ([LPConstantsState sharedState].isDevelopmentModeEnabled) {
            LPLog(LPInfo, @"Scheduled notification");
        }
        LP_BEGIN_USER_CODE
        return YES;
    }];

    [Leanplum onAction:@"__Cancel__Push Notification" invoke:^BOOL(LPActionContext *context) {
        LP_END_USER_CODE
        UIApplication *app = [UIApplication sharedApplication];
        NSArray *notifications = [app scheduledLocalNotifications];
        BOOL didCancel = NO;
        for (UILocalNotification *notification in notifications) {
            NSString *messageId = [LPActionManager messageIdFromUserInfo:[notification userInfo]];
            if ([messageId isEqualToString:[context private_MessageId]]) {
                [app cancelLocalNotification:notification];
                if ([LPConstantsState sharedState].isDevelopmentModeEnabled) {
                    LPLog(LPInfo, @"Cancelled notification");
                }
                didCancel = YES;
            }
        }
        LP_BEGIN_USER_CODE
        return didCancel;
    }];
}
#endif

#pragma mark - Delivery

- (NSMutableDictionary *)getMessageImpressionOccurrences:(NSString *)messageId
{
    NSMutableDictionary *occurrences = _messageImpressionOccurrences[messageId];
    if (occurrences) {
        return occurrences;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *savedValue = [defaults objectForKey:
                                [NSString stringWithFormat:LEANPLUM_DEFAULTS_MESSAGE_IMPRESSION_OCCURRENCES_KEY, messageId]];
    if (savedValue) {
        occurrences = [savedValue mutableCopy];
        _messageImpressionOccurrences[messageId] = occurrences;
    }
    return occurrences;
}

// Increment message impression occurrences.
// The @synchronized insures multiple threads create and increment the same
// dictionary. A corrupt dictionary will cause an NSUserDefaults crash.
- (void)incrementMessageImpressionOccurrences:(NSString *)messageId
{
    @synchronized (_messageImpressionOccurrences) {
        NSMutableDictionary *occurrences = [self getMessageImpressionOccurrences:messageId];
        if (occurrences == nil) {
            occurrences = [NSMutableDictionary dictionary];
            occurrences[@"min"] = @(0);
            occurrences[@"max"] = @(0);
            occurrences[@"0"] = @([[NSDate date] timeIntervalSince1970]);
        } else {
            int min = [occurrences[@"min"] intValue];
            int max = [occurrences[@"max"] intValue];
            max++;
            occurrences[[NSString stringWithFormat:@"%d", max]] =
                    @([[NSDate date] timeIntervalSince1970]);
            if (max - min + 1 > MAX_STORED_OCCURRENCES_PER_MESSAGE) {
                [occurrences removeObjectForKey:[NSString stringWithFormat:@"%d", min]];
                min++;
                occurrences[@"min"] = @(min);
            }
            occurrences[@"max"] = @(max);
        }
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:occurrences
                     forKey:[NSString stringWithFormat:LEANPLUM_DEFAULTS_MESSAGE_IMPRESSION_OCCURRENCES_KEY, messageId]];
    }
}

- (NSInteger)getMessageTriggerOccurrences:(NSString *)messageId
{
    NSNumber *occurrences = _messageTriggerOccurrences[messageId];
    if (occurrences) {
        return [occurrences intValue];
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger savedValue = [defaults integerForKey:
                            [NSString stringWithFormat:LEANPLUM_DEFAULTS_MESSAGE_TRIGGER_OCCURRENCES_KEY, messageId]];
    _messageTriggerOccurrences[messageId] = @(savedValue);
    return savedValue;
}

- (void)incrementMessageTriggerOccurrences:(NSString *)messageId
{
    @synchronized (_messageTriggerOccurrences) {
        NSInteger occurrences = [self getMessageTriggerOccurrences:messageId];
        occurrences++;
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setInteger:occurrences
                      forKey:[NSString stringWithFormat:LEANPLUM_DEFAULTS_MESSAGE_TRIGGER_OCCURRENCES_KEY, messageId]];
        _messageTriggerOccurrences[messageId] = @(occurrences);
    }   
}

+ (BOOL)matchedTriggers:(NSDictionary *)triggerConfig
                   when:(NSString *)when
              eventName:(NSString *)eventName
       contextualValues:(LPContextualValues *)contextualValues
{
    if ([triggerConfig isKindOfClass:[NSDictionary class]]) {
        NSArray *triggers = triggerConfig[@"children"];
        for (NSDictionary *trigger in triggers) {
            if ([self matchedTrigger:trigger
                                when:when
                           eventName:eventName
                    contextualValues:contextualValues]) {
                return YES;
            }
        }
    }
    return NO;
}

+ (BOOL)matchedTrigger:(NSDictionary *)trigger
                  when:(NSString *)when
             eventName:(NSString *)eventName
      contextualValues:(LPContextualValues *)contextualValues
{
    NSString *subject = trigger[@"subject"];
    if ([subject isEqualToString:when]) {
        NSString *noun = trigger[@"noun"];
        if ((noun == nil && eventName == nil) || [noun isEqualToString:eventName]) {
            NSString *verb = trigger [@"verb"];
            NSArray *objects = trigger[@"objects"];

            // Evaluate user attribute changed to value.
            if ([verb isEqual:@"changesTo"]) {
                NSString *value = [contextualValues.attributeValue description];
                for (id object in objects) {
                    if ([[object description]
                         caseInsensitiveCompare:value] == NSOrderedSame) {
                        return YES;
                    }
                }
                return NO;
            }

            // Evaluate user attribute changed from value to value.
            if ([verb isEqual:@"changesFromTo"]) {
                NSString *previousValue = [[contextualValues previousAttributeValue] description];
                NSString *value = [contextualValues.attributeValue description];
                return objects.count >= 2 &&
                    [[objects[0] description]
                        caseInsensitiveCompare:previousValue] == NSOrderedSame &&
                    [[objects[1] description] caseInsensitiveCompare:value] == NSOrderedSame;
            }

            // Evaluate event parameter is value.
            if ([verb isEqual:@"triggersWithParameter"]) {
                // We need to check whether the key is in the parameter
                // or else it will create a null object that will always return YES.
                return objects.count >= 2 &&
                    contextualValues.parameters[objects[0]] &&
                    [[contextualValues.parameters[objects[0]] description]
                        caseInsensitiveCompare:[objects[1] description]] == NSOrderedSame;
            }

            return YES;
        }
    }
    return NO;
}

+ (void)getForegroundRegionNames:(NSMutableSet **)foregroundRegionNames
        andBackgroundRegionNames:(NSMutableSet **)backgroundRegionNames
{
    *foregroundRegionNames = [NSMutableSet set];
    *backgroundRegionNames = [NSMutableSet set];
    NSDictionary *messages = [LPVarCache messages];
    for (NSString *messageId in messages) {
        NSDictionary *messageConfig = messages[messageId];
        NSMutableSet *regionNames;
        id action = messageConfig[@"action"];
        if ([action isKindOfClass:NSString.class]) {
            if ([action isEqualToString:LP_PUSH_NOTIFICATION_ACTION]) {
                regionNames = *backgroundRegionNames;
            } else {
                regionNames = *foregroundRegionNames;
            }
            [LPActionManager addRegionNamesFromTriggers:messageConfig[@"whenTriggers"]
                                                  toSet:regionNames];
            [LPActionManager addRegionNamesFromTriggers:messageConfig[@"unlessTriggers"]
                                                  toSet:regionNames];
        }
    }
}

+ (void)addRegionNamesFromTriggers:(NSDictionary *)triggerConfig toSet:(NSMutableSet *)set
{
    NSArray *triggers = triggerConfig[@"children"];
    for (NSDictionary *trigger in triggers) {
        NSString *subject = trigger[@"subject"];
        if ([subject isEqualToString:@"enterRegion"] ||
            [subject isEqualToString:@"exitRegion"]) {
            [set addObject:trigger[@"noun"]];
        }
    }
}

- (LeanplumMessageMatchResult)shouldShowMessage:(NSString *)messageId
                                     withConfig:(NSDictionary *)messageConfig
                                           when:(NSString *)when
                                  withEventName:(NSString *)eventName
                               contextualValues:(LPContextualValues *)contextualValues
{
    LeanplumMessageMatchResult result = LeanplumMessageMatchResultMake(NO, NO, NO);

    // 1. Must not be muted.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:
         [NSString stringWithFormat:LEANPLUM_DEFAULTS_MESSAGE_MUTED_KEY, messageId]]) {
        return result;
    }

    // 2. Must match at least one trigger.
    result.matchedTrigger = [LPActionManager matchedTriggers:messageConfig[@"whenTriggers"]
                                                        when:when
                                                   eventName:eventName
                                            contextualValues:contextualValues];
    result.matchedUnlessTrigger = [LPActionManager matchedTriggers:messageConfig[@"unlessTriggers"]
                                                              when:when
                                                         eventName:eventName
                                                  contextualValues:contextualValues];
    if (!result.matchedTrigger && !result.matchedUnlessTrigger) {
        return result;
    }

    // 3. Must match all limit conditions.
    NSDictionary *limitConfig = messageConfig[@"whenLimits"];
    result.matchedLimit = [self matchesLimits:limitConfig messageId:messageId];
    return result;
}

- (BOOL)matchesLimits:(NSDictionary *)limitConfig
            messageId:(NSString *)messageId
{
    if (![limitConfig isKindOfClass:[NSDictionary class]]) {
        return YES;
    }
    NSArray *limits = limitConfig[@"children"];
    if (!limits.count) {
        return YES;
    }
    NSDictionary *impressionOccurrences = [self getMessageImpressionOccurrences:messageId];
    NSInteger triggerOccurrences = [self getMessageTriggerOccurrences:messageId] + 1;
    for (NSDictionary *limit in limits) {
        NSString *subject = limit[@"subject"];
        NSString *noun = limit[@"noun"];
        NSString *verb = limit[@"verb"];

        // E.g. 5 times per session; 2 times per 7 minutes.
        if ([subject isEqualToString:@"times"]) {
            if (![self matchesLimitTimes:[noun intValue]
                                     per:[[limit[@"objects"] firstObject] intValue]
                               withUnits:verb
                             occurrences:impressionOccurrences
                               messageId:messageId]) {
                return NO;
            }
        
        // E.g. On the 5th occurrence.
        } else if ([subject isEqualToString:@"onNthOccurrence"]) {
            int amount = [noun intValue];
            if (triggerOccurrences != amount) {
                return NO;
            }

        // E.g. Every 5th occurrence.
        } else if ([subject isEqualToString:@"everyNthOccurrence"]) {
            int multiple = [noun intValue];
            if (multiple == 0 || triggerOccurrences % multiple != 0) {
                return NO;
            }
        }
    }
    return YES;
}

- (BOOL)matchesLimitTimes:(int)amount
                      per:(int)time
                withUnits:(NSString *)units
              occurrences:(NSDictionary *)occurrences
                messageId:(NSString *)messageId
{
    int existing = 0;
    if ([units isEqualToString:@"limitSession"]) {
        existing = [_sessionOccurrences[messageId] intValue];
    } else {
        if (occurrences == nil) {
            return YES;
        }
        int min = [occurrences[@"min"] intValue];
        int max = [occurrences[@"max"] intValue];
        if ([units isEqualToString:@"limitUser"]) {
            existing = max - min + 1;
        } else {
            int perSeconds = time;
            if ([units isEqualToString:@"limitMinute"]) {
                perSeconds *= 60;
            } else if ([units isEqualToString:@"limitHour"]) {
                perSeconds *= 3600;
            } else if ([units isEqualToString:@"limitDay"]) {
                perSeconds *= 86400;
            } else if ([units isEqualToString:@"limitWeek"]) {
                perSeconds *= 604800;
            } else if ([units isEqualToString:@"limitMonth"]) {
                perSeconds *= 2592000;
            }
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            int matchedOccurrences = 0;
            for (int i = max; i >= min; i--) {
                NSTimeInterval timeAgo = now -
                        [occurrences[[NSString stringWithFormat:@"%d", i]] doubleValue];
                if (timeAgo > perSeconds) {
                    break;
                }
                matchedOccurrences++;
                if (matchedOccurrences >= amount) {
                    return NO;
                }
            }
        }
    }
    return existing < amount;
}

- (void)recordMessageTrigger:(NSString *)messageId
{
    [self incrementMessageTriggerOccurrences:messageId];
}

/**
 * Tracks the "Open" event for a message and records it's occurrence.
 * @param messageId The ID of the message
 */
- (void)recordMessageImpression:(NSString *)messageId
{
    [self recordImpression:messageId originalMessageId:nil];
}

/**
 * Tracks the "Held Back" event for a message and records the held back occurrences.
 * @param messageId The spoofed ID of the message.
 * @param originalMessageId The original ID of the held back message.
 */
- (void)recordHeldBackImpression:(NSString *)messageId
               originalMessageId:(NSString *)originalMessageId
{
    [self recordImpression:messageId originalMessageId:originalMessageId];
}

/**
 * Records the occurrence of a message and tracks the correct impression event.
 * @param messageId The ID of the message.
 * @param originalMessageId The original message ID of the held back message. Supply this
 *     only if the message is held back. Otherwise, use nil.
 */
- (void)recordImpression:(NSString *)messageId originalMessageId:(NSString *)originalMessageId
{
    if (originalMessageId) {
        // This is a held back impression - track it with the original message id.
        [Leanplum track:LP_HELD_BACK_EVENT_NAME withValue:0.0 andInfo:nil
                andArgs:@{LP_PARAM_MESSAGE_ID: originalMessageId} andParameters:nil];
    } else {
        // Track occurrence.
        [Leanplum track:nil withValue:0.0 andInfo:nil
                andArgs:@{LP_PARAM_MESSAGE_ID: messageId} andParameters:nil];
    }

    // Record session occurrences.
    @synchronized (_sessionOccurrences) {
        int existing = [_sessionOccurrences[messageId] intValue];
        existing++;
        _sessionOccurrences[messageId] = @(existing);
    }
    
    // Record cross-session occurrences.
    [self incrementMessageImpressionOccurrences:messageId];
}

- (void)muteFutureMessagesOfKind:(NSString *)messageId
{
    if (messageId) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:YES forKey:[NSString stringWithFormat:LEANPLUM_DEFAULTS_MESSAGE_MUTED_KEY, messageId]];
    }
}

@end
