//
//  MMStretchGestureRecognizer.h
//  ShapeShifter
//
//  Created by Adam Wulf on 2/21/14.
//  Copyright (c) 2014 Milestone Made, LLC. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "Constants.h"
#import "MMPanAndPinchScrapGestureRecognizer.h"
#import "MMStretchScrapGestureRecognizerDelegate.h"
#import "MMCancelableGestureRecognizer.h"


@interface MMStretchScrapGestureRecognizer : MMCancelableGestureRecognizer <UIGestureRecognizerDelegate>

@property (nonatomic, weak) MMPanAndPinchScrapGestureRecognizer* pinchScrapGesture1;
@property (nonatomic, weak) MMPanAndPinchScrapGestureRecognizer* pinchScrapGesture2;
@property (nonatomic, weak) NSObject<MMStretchScrapGestureRecognizerDelegate>* scrapDelegate;
@property (readonly) MMScrapView* scrap;
@property (readonly) NSArray* validTouches;
@property (readonly) CATransform3D skewTransform;
@property (nonatomic, readonly) NSDictionary* startingScrapProperties;
@property (nonatomic, readonly) MMUndoablePaperView* startingPageForScrap;

- (void)ownershipOfTouches:(NSSet*)touches isGesture:(UIGestureRecognizer*)gesture;

- (void)blessTouches:(NSSet*)touches;

- (CATransform3D)transformForBounceAtScale:(CGFloat)scale;

@end
