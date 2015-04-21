//
//  MMTutorialStackView.m
//  LooseLeaf
//
//  Created by Adam Wulf on 2/23/15.
//  Copyright (c) 2015 Milestone Made, LLC. All rights reserved.
//

#import "MMTutorialStackView.h"
#import "MMTutorialView.h"
#import "MMStopWatch.h"
#import "MMTutorialSidebarButton.h"
#import "Mixpanel.h"
#import "MMTutorialManager.h"
#import "MMLargeTutorialSidebarButton.h"

@implementation MMTutorialStackView{
    UIView* backdrop;
    MMTutorialView* tutorialView;
    MMTextButton* helpButton;
    MMLargeTutorialSidebarButton* listViewTutorialButton;
}

-(id) initWithFrame:(CGRect)frame{
    if(self = [super initWithFrame:frame]){
        helpButton = [[MMTutorialSidebarButton alloc] initWithFrame:CGRectMake((kWidthOfSidebar - kWidthOfSidebarButton)/2, self.frame.size.height - kWidthOfSidebarButton - (kWidthOfSidebar - kWidthOfSidebarButton)/2 - 2*60, kWidthOfSidebarButton, kWidthOfSidebarButton) andTutorialList:^NSArray *{
            return [[MMTutorialManager sharedInstance] appIntroTutorialSteps];
        }];
        helpButton.delegate = self;
        [helpButton addTarget:self action:@selector(tutorialButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:helpButton];
        buttons[numberOfButtons].button = (__bridge void *)(helpButton);
        buttons[numberOfButtons].originalRect = helpButton.frame;
        numberOfButtons++;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tutorialShouldOpen:) name:kTutorialStartedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tutorialShouldClose:) name:kTutorialClosedNotification object:nil];
        
        if(![[MMTutorialManager sharedInstance] hasFinishedTutorial]){
            [[MMTutorialManager sharedInstance] startWatchingTutorials:[[MMTutorialManager sharedInstance] appIntroTutorialSteps]];
        }
        
        CGRect typicalBounds = CGRectMake(0, 0, 80, 80);
        listViewTutorialButton = [[MMLargeTutorialSidebarButton alloc] initWithFrame:typicalBounds andTutorialList:^NSArray *{
            return [[MMTutorialManager sharedInstance] listViewTutorialSteps];
        }];
        listViewTutorialButton.center = CGPointMake(self.bounds.size.width/2, self.bounds.size.height - 100);
        [listViewTutorialButton addTarget:self action:@selector(tutorialButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        [self moveAddButtonToBottom];
    }
    return self;
}

#pragma mark - Tutorial Buttons

-(void) tutorialButtonPressed:(MMTutorialSidebarButton*)tutorialButton{
    [[MMTutorialManager sharedInstance] startWatchingTutorials:tutorialButton.tutorialList];
}


#pragma mark - Private Helpers

-(BOOL) isShowingTutorial{
    return tutorialView != nil || tutorialView.alpha;
}

#pragma mark - Tutorial Notifications

-(void) tutorialShouldOpen:(NSNotification*)note{
    if([self isShowingTutorial]){
        // tutorial is already showing, just return
        return;
    }
    
    NSArray* tutorials = [note.userInfo objectForKey:@"tutorialList"];
    backdrop = [[UIView alloc] initWithFrame:self.bounds];
    backdrop.backgroundColor = [UIColor whiteColor];
    backdrop.alpha = 0;
    [self addSubview:backdrop];
    
    tutorialView = [[MMTutorialView alloc] initWithFrame:self.bounds andTutorials:tutorials];
    tutorialView.delegate = self;
    tutorialView.alpha = 0;
    [self addSubview:tutorialView];
    
    [UIView animateWithDuration:.3 animations:^{
        backdrop.alpha = 1;
        tutorialView.alpha = 1;
    }];
}

-(void) tutorialShouldClose:(NSNotification*)note{
    if(![self isShowingTutorial]){
        // tutorial is already hidden, just return
        return;
    }
    [UIView animateWithDuration:.3 animations:^{
        backdrop.alpha = 0;
        tutorialView.alpha = 0;
    } completion:^(BOOL finished) {
        [backdrop removeFromSuperview];
        backdrop = nil;
        [tutorialView removeFromSuperview];
        tutorialView = nil;
        NSInteger numPendingTutorials = [[MMTutorialManager sharedInstance] numberOfPendingTutorials:[[MMTutorialManager sharedInstance] appIntroTutorialSteps]];
        if(numPendingTutorials){
            [self performSelector:@selector(bounceSidebarButton:) withObject:helpButton afterDelay:.3];
        }
    }];
}


#pragma mark - MMTutorialViewDelegate

-(void) userIsViewingTutorialStep:(NSInteger)stepNum{
    NSLog(@"user is watching %d", (int) stepNum);
}

-(void) didFinishTutorial{
    [self tutorialShouldClose:nil];
}


#pragma mark - Rotation Manager Delegate

-(void) didRotateToIdealOrientation:(UIInterfaceOrientation)orientation{
    [super didRotateToIdealOrientation:orientation];
    [tutorialView didRotateToIdealOrientation:orientation];
}

#pragma mark - List View Tutorial

-(CGFloat) contentHeightForAllPages{
    return [super contentHeightForAllPages] + 140;
}

-(void) moveAddButtonToBottom{
    [super moveAddButtonToBottom];
    [self insertSubview:listViewTutorialButton atIndex:0];
    listViewTutorialButton.alpha = 0;
}

-(void) moveAddButtonToTop{
    [super moveAddButtonToTop];
    [self addSubview:listViewTutorialButton];
    listViewTutorialButton.alpha = 1;
    
    listViewTutorialButton.center = CGPointMake(self.bounds.size.width/2, [self contentHeightForAllPages] - 70);
}

@end