//
//  MMTutorialManager.m
//  LooseLeaf
//
//  Created by Adam Wulf on 3/21/15.
//  Copyright (c) 2015 Milestone Made, LLC. All rights reserved.
//

#import "MMTutorialManager.h"
#import "MMStopWatch.h"
#import "Mixpanel.h"
#import "Constants.h"

@implementation MMTutorialManager{
    MMStopWatch* stopwatch;
    BOOL hasFinishedTutorial;
    CGFloat timeSpentInTutorial;
    NSInteger currentTutorialStep;
    NSOperationQueue* subscriptionOpQueue;
}

@synthesize hasFinishedTutorial;

#pragma mark - Singleton

static MMTutorialManager* _instance = nil;

-(id) init{
    if(_instance) return _instance;
    if((self = [super init])){
        hasFinishedTutorial = [[NSUserDefaults standardUserDefaults] boolForKey:kMPHasFinishedTutorial];
        timeSpentInTutorial = [[NSUserDefaults standardUserDefaults] floatForKey:kMPDurationWatchingTutorial];
        currentTutorialStep = [[NSUserDefaults standardUserDefaults] integerForKey:kCurrentTutorialStep];
        stopwatch = [[MMStopWatch alloc] initWithDuration:timeSpentInTutorial];
        subscriptionOpQueue = [[NSOperationQueue alloc] init];
        subscriptionOpQueue.maxConcurrentOperationCount = 1;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        
#ifdef DEBUG
        for (NSDictionary* tutorial in [[[self appIntroTutorialSteps] arrayByAddingObjectsFromArray:[self listViewTutorialSteps]] arrayByAddingObjectsFromArray:[self shareTutorialSteps]]) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:[kCurrentTutorialStep stringByAppendingString:[tutorial objectForKey:@"id"]]];
        }
        
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kHasIgnoredNewsletter];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kHasSignedUpForNewsletter];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPendingEmailToSubscribe];
        
#endif
    }
    return self;
}

+(MMTutorialManager*) sharedInstance{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[MMTutorialManager alloc] init];
    });
    return _instance;
}

#pragma mark - Public API

-(BOOL) hasCompletedStep:(NSString*)stepID{
    return [[NSUserDefaults standardUserDefaults] boolForKey:[kCurrentTutorialStep stringByAppendingString:stepID]];
}

-(void) didCompleteStep:(NSString*)stepID{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:[kCurrentTutorialStep stringByAppendingString:stepID]];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTutorialStepCompleteNotification object:stepID];
}

-(NSInteger) numberOfPendingTutorials:(NSArray*)possiblyPendingTutorials{
    __block NSInteger numCompleted = 0;
    
    [possiblyPendingTutorials enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        numCompleted += [self hasCompletedStep:[obj objectForKey:@"id"]] ? 1 : 0;
    }];
    
    return [possiblyPendingTutorials count] - numCompleted;
}

-(NSArray*) appIntroTutorialSteps{
    return @[@{
                 @"id":@"app-intro-pen",
                 @"title":@"Draw and Erase",
                 @"video":@"hello.mov"
                 },@{
                 @"id":@"app-intro-pinch",
                 @"title":@"Pinch to See Your Pages",
                 @"video":@"pinch-to-list.mov"
                 },@{
                 @"id":@"app-intro-import-scissor",
                 @"title":@"Import and Crop Your Photos",
                 @"video":@"import-and-scissor.mov"
                 },@{
                 @"id":@"app-intro-export",
                 @"title":@"Export Your Pages",
                 @"video":@"export-to-facebook.mov"
                 }];
}

-(NSArray*) listViewTutorialSteps{
    return @[@{
                 @"id":@"list-view-reorder-pages",
                 @"title":@"Organize Your Pages",
                 @"video":@"list-view-reorder-pages.mov"
                 },@{
                 @"id":@"list-view-delete-page",
                 @"title":@"Delete a Page",
                 @"video":@"list-view-delete-page.mov"
                 }];
}

-(NSArray*) shareTutorialSteps{
    return @[@{
                 @"id":@"pen",
                 @"title":@"Draw and Erase",
                 @"video":@"hello.mov"
                 },@{
                 @"id":@"nav",
                 @"title":@"Pinch to See Your Pages",
                 @"video":@"pinch-to-list.mov"
                 },@{
                 @"id":@"ruler",
                 @"title":@"Import and Crop Your Photos",
                 @"video":@"import-and-scissor.mov"
                 },@{
                 @"id":@"clip",
                 @"title":@"Export Your Pages",
                 @"video":@"export-to-facebook.mov"
                 }];
}

-(BOOL) isWatchingTutorial{
    return [stopwatch isRunning];
}

-(void) startWatchingTutorials:(NSArray*)tutorialList{
    [stopwatch start];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTutorialStartedNotification object:self userInfo:@{@"tutorialList" : tutorialList}];
}

-(void) pauseWatchingTutorial{
    timeSpentInTutorial = [stopwatch stop];
    [[[Mixpanel sharedInstance] people] set:kMPDurationWatchingTutorial to:@(timeSpentInTutorial)];
    [[NSUserDefaults standardUserDefaults] setFloat:timeSpentInTutorial forKey:kMPDurationWatchingTutorial];
}

-(void) finishWatchingTutorial{
    [self pauseWatchingTutorial];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kMPHasFinishedTutorial];
    [[[Mixpanel sharedInstance] people] set:kMPHasFinishedTutorial to:@(YES)];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTutorialClosedNotification object:self];
}


#pragma mark - Newsletter


-(BOOL) hasSignedUpForNewsletter{
    return [[NSUserDefaults standardUserDefaults] boolForKey:kHasSignedUpForNewsletter] ||
    [[NSUserDefaults standardUserDefaults] boolForKey:kHasIgnoredNewsletter];
}


-(void) optOutOfNewsletter{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHasIgnoredNewsletter];
    [[[Mixpanel sharedInstance] people] set:kMPNewsletterStatus to:@"Opt Out"];
}

-(void) signUpForNewsletter:(NSString*)email{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHasSignedUpForNewsletter];
    [[[Mixpanel sharedInstance] people] set:kMPNewsletterStatus to:@"Subscribed"];
    [[NSUserDefaults standardUserDefaults] setObject:email forKey:kPendingEmailToSubscribe];
}


#pragma mark - Notifications

-(void) didEnterBackground{
    [self pauseWatchingTutorial];
}

#pragma mark - Dealloc

-(void) dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end