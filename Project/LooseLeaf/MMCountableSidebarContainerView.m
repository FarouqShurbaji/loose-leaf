//
//  MMCountableSidebarContainerView.m
//  LooseLeaf
//
//  Created by Adam Wulf on 9/27/16.
//  Copyright © 2016 Milestone Made, LLC. All rights reserved.
//

#import "MMCountableSidebarContainerView.h"
#import "MMSidebarButtonTapGestureRecognizer.h"
#import "MMCountableSidebarButton.h"
#import "Constants.h"
#import "Mixpanel.h"

#define kAnimationDuration 0.3


@implementation MMCountableSidebarContainerView {
    CGFloat targetAlpha;
    NSMutableArray* viewsInSidebar;
}

@synthesize bubbleDelegate;
@synthesize contentView = contentView;
@synthesize countButton;

- (id)initWithFrame:(CGRect)frame andCountButton:(MMCountBubbleButton*)_countButton {
    if (self = [super initWithFrame:frame forReferenceButtonFrame:[_countButton frame] animateFromLeft:NO]) {
        targetAlpha = 1;
        viewsInSidebar = [NSMutableArray array];
        bubbleForScrap = [NSMutableDictionary dictionary];

        countButton = _countButton;
        countButton.delegate = self;
        [countButton addTarget:self action:@selector(countButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:countButton];
    }
    return self;
}

- (NSArray<MMUUIDView>*)viewsInSidebar {
    return [viewsInSidebar copy];
}

- (BOOL)containsView:(UIView<MMUUIDView>*)view {
    return [[self viewsInSidebar] containsObject:view];
}

- (BOOL)containsViewUUID:(NSString*)viewUUID {
    for (UIView<MMUUIDView>* view in [self viewsInSidebar]) {
        if ([view.uuid isEqualToString:viewUUID]) {
            return YES;
        }
    }
    return NO;
}

- (void)deleteAllViewsFromSidebar {
    for (UIView* otherBubble in self.subviews) {
        if ([otherBubble isKindOfClass:[MMCountBubbleButton class]]) {
            [otherBubble removeFromSuperview];
        }
    }

    [viewsInSidebar removeAllObjects];
}

- (void)didTapOnViewFromMenu:(UIView<MMUUIDView>*)view withPreferredProperties:(NSDictionary*)properties below:(BOOL)below {
    [viewsInSidebar removeObject:view];
    view.center = [self convertPoint:view.center fromView:view.superview];

    if (below) {
        [self insertSubview:view belowSubview:countButton];
    } else {
        [self addSubview:view];
    }

    [self.countButton setCount:[[self viewsInSidebar] count]];

    [self.bubbleDelegate willRemoveView:view fromCountableSidebar:self];

    UIView<MMBubbleButton>* bubbleToAddToPage = [bubbleForScrap objectForKey:view.uuid];

    view.scale = view.scale * [[bubbleToAddToPage class] idealScaleForView:view];

    BOOL hadProperties = properties != nil;

    if (!properties) {
        properties = [self idealPropertiesForViewInBubble:bubbleToAddToPage];
    }

    view.layer.borderWidth = 0;

    // remove the reference to the scrap from the button
    bubbleToAddToPage.view = nil;

    [self sidebarCloseButtonWasTapped];

    [UIView animateWithDuration:.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [view setPropertiesDictionary:properties];
    } completion:^(BOOL finished) {
        NSUInteger index = NSNotFound;
        if ([properties objectForKey:@"subviewIndex"]) {
            index = [[properties objectForKey:@"subviewIndex"] unsignedIntegerValue];
        }
        [self.bubbleDelegate didRemoveView:view atIndex:index hadProperties:hadProperties fromCountableSidebar:self];
    }];
    [UIView animateWithDuration:.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        bubbleToAddToPage.alpha = 0;
        for (UIView<MMBubbleButton>* otherBubble in self.subviews) {
            if ([otherBubble conformsToProtocol:@protocol(MMBubbleButton)]) {
                if (otherBubble.view && otherBubble != bubbleToAddToPage) {
                    int index = (int)[[self viewsInSidebar] indexOfObject:otherBubble.view];
                    otherBubble.center = [self centerForBubbleAtIndex:index];
                    otherBubble.alpha = [self targetAlphaForBubbleButton:otherBubble];
                    otherBubble.transform = [self targetTransformForBubbleButton:otherBubble];
                    if ([[self viewsInSidebar] count] <= kMaxButtonsInBezelSidebar) {
                        // we need to reset the view here, because it could have been stolen
                        // by the actual sidebar content view. If that's the case, then we
                        // need to steal the view back so it can display in the bubble button
                        otherBubble.view = otherBubble.view;
                        [self loadCachedPreviewForView:otherBubble.view];
                    }
                }
            }
        }
        if ([[self viewsInSidebar] count] <= kMaxButtonsInBezelSidebar) {
            self.countButton.alpha = 0;
        }
    } completion:^(BOOL finished) {
        [bubbleToAddToPage removeFromSuperview];
    }];

    [bubbleForScrap removeObjectForKey:view.uuid];
}

- (void)addViewToCountableSidebar:(UIView<MMUUIDView>*)view animated:(BOOL)animated {
    if (!view) {
        [[Mixpanel sharedInstance] track:kMPEventCrashAverted properties:@{ @"Issue #": @(1765) }];
        return;
    }

    [viewsInSidebar addObject:view];

    // exit the scrap to the bezel!
    CGPoint center = [self centerForBubbleAtIndex:[[self viewsInSidebar] indexOfObject:view]];

    // prep the animation by creating the new bubble for the scrap
    // and initializing it's probable location (may change if count > 6)
    // and set it's alpha/rotation/scale to prepare for the animation
    UIView<MMBubbleButton>* bubble = [self newBubbleForView:view];
    bubble.center = center;

    //
    // iOS7 changes how buttons can be tapped during a gesture (i think).
    // so adding our gesture recognizer explicitly, and disallowing it to
    // be prevented ensures that buttons can be tapped while other gestures
    // are in flight.
    //    [bubble addTarget:self action:@selector(bubbleTapped:) forControlEvents:UIControlEventTouchUpInside];
    UITapGestureRecognizer* tappy = [[MMSidebarButtonTapGestureRecognizer alloc] initWithTarget:self action:@selector(bubbleTapped:)];
    [bubble addGestureRecognizer:tappy];
    [self insertSubview:bubble belowSubview:countButton];

    CGPoint theirCenter = view.center;
    CGPoint myCenter = [self convertPoint:theirCenter fromView:view.superview];

    [self insertSubview:view aboveSubview:bubble];
    view.center = myCenter;

    // keep the scrap in the bezel container during the animation, then
    // push it into the bubble
    bubble.alpha = 0;
    bubble.scale = .9;
    [bubbleForScrap setObject:bubble forKey:view.uuid];

    if (animated) {
        CGFloat animationDuration = 0.5;

        if ([[self viewsInSidebar] count] <= kMaxButtonsInBezelSidebar) {
            // allow adding to 6 in the sidebar, otherwise
            // we need to pull them all into 1 button w/
            // a menu
            [self loadCachedPreviewForView:view];

            [self.bubbleDelegate willAddView:view toCountableSidebar:self];

            [UIView animateWithDuration:animationDuration * .51 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                // animate the scrap into position
                bubble.alpha = [self targetAlphaForBubbleButton:bubble];
                view.bounds = [[bubble class] idealBoundsForView:view];
                view.transform = CGAffineTransformConcat([[bubble class] idealTransformForView:view], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
                bubble.transform = [self targetTransformForBubbleButton:bubble];
                view.center = bubble.center;
                for (UIView<MMBubbleButton>* otherBubble in self.subviews) {
                    if (otherBubble != bubble) {
                        if ([otherBubble conformsToProtocol:@protocol(MMBubbleButton)]) {
                            NSInteger index = [[self viewsInSidebar] indexOfObject:otherBubble.view];
                            otherBubble.center = [self centerForBubbleAtIndex:index];
                            otherBubble.alpha = [self targetAlphaForBubbleButton:otherBubble];
                            otherBubble.transform = [self targetTransformForBubbleButton:otherBubble];
                        }
                    }
                }

            } completion:^(BOOL finished) {
                // add it to the bubble and bounce
                bubble.view = view;
                [UIView animateWithDuration:animationDuration * .2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                    // scrap "hits" the bubble and pushes it down a bit
                    bubble.scale = .8;
                    bubble.alpha = [self targetAlphaForBubbleButton:bubble];
                } completion:^(BOOL finished) {
                    [self.countButton setCount:[[self viewsInSidebar] count]];
                    [UIView animateWithDuration:animationDuration * .2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                        // bounce back
                        bubble.scale = 1.1;
                    } completion:^(BOOL finished) {
                        [UIView animateWithDuration:animationDuration * .16 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                            // and done
                            bubble.scale = 1.0;
                        } completion:^(BOOL finished) {
                            [self.bubbleDelegate didAddView:view toCountableSidebar:self];
                        }];
                    }];
                }];
            }];
        } else if ([[self viewsInSidebar] count] > kMaxButtonsInBezelSidebar) {
            // we need to merge all the bubbles together into
            // a single button during the bezel animation
            [self.bubbleDelegate willAddView:view toCountableSidebar:self];
            [self.countButton setCount:[[self viewsInSidebar] count]];
            bubble.center = self.countButton.center;
            bubble.scale = 1;
            [UIView animateWithDuration:animationDuration * .51 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                // animate the scrap into position
                self.countButton.alpha = targetAlpha;
                for (UIView<MMBubbleButton>* bubble in self.subviews) {
                    if ([bubble conformsToProtocol:@protocol(MMBubbleButton)]) {
                        bubble.view.bounds = [[bubble class] idealBoundsForView:bubble.view];
                        bubble.alpha = [self targetAlphaForBubbleButton:bubble];
                        bubble.center = self.countButton.center;
                        view.transform = CGAffineTransformConcat([[bubble class] idealTransformForView:view], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
                        bubble.transform = [self targetTransformForBubbleButton:bubble];
                        if (!bubble.alpha) {
                            [self unloadCachedPreviewForView:bubble.view];
                        } else {
                            [self loadCachedPreviewForView:view];
                        }
                    }
                }
                view.bounds = [[bubble class] idealBoundsForView:view];
                view.transform = CGAffineTransformConcat([[bubble class] idealTransformForView:view], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
                view.center = bubble.center;
            } completion:^(BOOL finished) {
                // add it to the bubble and bounce
                bubble.view = view;
                [UIView animateWithDuration:animationDuration * .2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                    // scrap "hits" the bubble and pushes it down a bit
                    self.countButton.scale = .8;
                } completion:^(BOOL finished) {
                    [self.countButton setCount:[[self viewsInSidebar] count]];
                    [UIView animateWithDuration:animationDuration * .2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                        // bounce back
                        self.countButton.scale = 1.1;
                    } completion:^(BOOL finished) {
                        [UIView animateWithDuration:animationDuration * .16 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                            // and done
                            self.countButton.scale = 1.0;
                        } completion:^(BOOL finished) {
                            [self.bubbleDelegate didAddView:view toCountableSidebar:self];
                        }];
                    }];
                }];
            }];
        }
    } else {
        bubble.scale = 1.0;

        [self.bubbleDelegate willAddView:view toCountableSidebar:self];
        bubble.alpha = [self targetAlphaForBubbleButton:bubble];
        view.bounds = [[bubble class] idealBoundsForView:view];
        view.transform = CGAffineTransformConcat([[bubble class] idealTransformForView:view], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
        view.center = bubble.center;
        bubble.transform = [self targetTransformForBubbleButton:bubble];
        bubble.view = view;
        [self resetAlphaForButtonsWithoutAnimation];
        [self.bubbleDelegate didAddView:view toCountableSidebar:self];
    }
}

- (void)resetAlphaForButtonsWithoutAnimation {
    if ([[self viewsInSidebar] count] <= kMaxButtonsInBezelSidebar) {
        self.countButton.alpha = 0;
        for (UIView<MMBubbleButton>* bubble in self.subviews) {
            if ([bubble conformsToProtocol:@protocol(MMBubbleButton)]) {
                int index = (int)[[self viewsInSidebar] indexOfObject:bubble.view];
                bubble.alpha = [self targetAlphaForBubbleButton:bubble];
                bubble.center = [self centerForBubbleAtIndex:index];
                bubble.transform = [self targetTransformForBubbleButton:bubble];
                if (!bubble.alpha) {
                    [self unloadCachedPreviewForView:bubble.view];
                } else {
                    [self loadCachedPreviewForView:bubble.view];
                }
            }
        }
    } else {
        [self.countButton setCount:[[self viewsInSidebar] count]];
        self.countButton.alpha = targetAlpha;
        for (UIView<MMBubbleButton>* bubble in self.subviews) {
            if ([bubble conformsToProtocol:@protocol(MMBubbleButton)]) {
                bubble.alpha = [self targetAlphaForBubbleButton:bubble];
                bubble.center = self.countButton.center;
                bubble.transform = [self targetTransformForBubbleButton:bubble];
                if (!bubble.alpha) {
                    [self unloadCachedPreviewForView:bubble.view];
                } else {
                    [self loadCachedPreviewForView:bubble.view];
                }
            }
        }
    }
}

- (CGFloat)targetAlphaForBubbleButton:(UIView<MMBubbleButton>*)bubble {
    if (self.alpha) {
        if ([[self viewsInSidebar] count] <= kMaxButtonsInBezelSidebar) {
            return 1;
        } else {
            return 0;
        }
    } else {
        return 0;
    }
}

- (CGAffineTransform)targetTransformForBubbleButton:(UIView<MMBubbleButton>*)bubble {
    return CGAffineTransformIdentity;
}

#pragma mark - Protected

- (UIView<MMBubbleButton>*)newBubbleForView:(UIView<MMUUIDView>*)scrap {
    @throw kAbstractMethodException;
}

- (void)loadCachedPreviewForView:(UIView<MMUUIDView>*)view {
    @throw kAbstractMethodException;
}

- (void)unloadCachedPreviewForView:(UIView<MMUUIDView>*)view {
    @throw kAbstractMethodException;
}

- (NSDictionary*)idealPropertiesForViewInBubble:(UIView<MMBubbleButton>*)bubble {
    UIView<MMUUIDView>* scrap = bubble.view;
    CGPoint positionOnScreenToScaleTo = [self.bubbleDelegate positionOnScreenToScaleViewTo:scrap fromCountableSidebar:self];
    CGFloat scaleOnScreenToScaleTo = [self.bubbleDelegate scaleOnScreenToScaleViewTo:scrap givenOriginalScale:bubble.originalViewScale fromCountableSidebar:self];
    NSMutableDictionary* mproperties = [[scrap propertiesDictionary] mutableCopy];
    [mproperties setObject:[NSNumber numberWithFloat:positionOnScreenToScaleTo.x] forKey:@"center.x"];
    [mproperties setObject:[NSNumber numberWithFloat:positionOnScreenToScaleTo.y] forKey:@"center.y"];
    [mproperties setObject:[NSNumber numberWithFloat:scaleOnScreenToScaleTo] forKey:@"scale"];
    return mproperties;
}

#pragma mark - Actions

// count button was tapped,
// so show or hide the menu
// so the user can choose a scrap to add
- (void)countButtonTapped:(UIButton*)button {
    if (countButton.alpha) {
        countButton.alpha = 0;
        [contentView viewWillShow];
        [contentView prepareContentView];
        [self show:YES];
    }
}

- (void)bubbleTapped:(UITapGestureRecognizer*)gesture {
    UIView<MMBubbleButton>* bubble = (UIView<MMBubbleButton>*)gesture.view;
    UIView<MMUUIDView>* scrap = bubble.view;

    if ([[self viewsInSidebar] containsObject:bubble.view]) {
        scrap.transform = CGAffineTransformConcat([[bubble class] idealTransformForView:scrap], CGAffineTransformMakeScale(bubble.scale, bubble.scale));
        [self didTapOnViewFromMenu:scrap withPreferredProperties:nil below:NO];
    }
}

#pragma mark - Helper Methods

- (CGSize)sizeForButton {
    @throw kAbstractMethodException;
}

- (CGPoint)centerForBubbleAtIndex:(NSInteger)index {
    CGSize sizeOfButton = [self sizeForButton];
    CGFloat rightBezelSide = self.bounds.size.width - sizeOfButton.width - 20;
    // midpoint calculates for 6 buttons
    CGFloat midPointY = (self.bounds.size.height - 6 * sizeOfButton.height) / 2;
    CGPoint ret = CGPointMake(rightBezelSide + sizeOfButton.width / 2, midPointY + sizeOfButton.height / 2);
    ret.y += sizeOfButton.height * index;
    return ret;
}

- (CGFloat)alpha {
    return targetAlpha;
}

- (void)setAlpha:(CGFloat)alpha {
    targetAlpha = alpha;
    if ([[self viewsInSidebar] count] > kMaxButtonsInBezelSidebar) {
        countButton.alpha = targetAlpha;
    } else {
        countButton.alpha = 0;
    }
    for (UIView<MMBubbleButton>* subview in self.subviews) {
        if ([subview conformsToProtocol:@protocol(MMBubbleButton)]) {
            subview.alpha = [self targetAlphaForBubbleButton:subview];
        }
    }
    if (!targetAlpha) {
        [self sidebarCloseButtonWasTapped];
    }
}

#pragma mark - Ignore Touches

/**
 * these two methods make sure that this scrap container view
 * can never intercept any touch input. instead it will
 * effectively pass through this view to the views behind it
 */
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    for (UIView* bubble in self.subviews) {
        if (bubble.alpha && [[self viewsInSidebar] count] <= kMaxButtonsInBezelSidebar) {
            if ([bubble conformsToProtocol:@protocol(MMBubbleButton)]) {
                UIView* output = [bubble hitTest:[self convertPoint:point toView:bubble] withEvent:event];
                if (output) {
                    return output;
                }
            }
        }
    }
    if (countButton.alpha) {
        UIView* output = [countButton hitTest:[self convertPoint:point toView:countButton] withEvent:event];
        if (output) {
            return output;
        }
    }
    if (contentView.alpha) {
        UIView* output = [contentView hitTest:[self convertPoint:point toView:contentView] withEvent:event];
        if (output) {
            return output;
        }
    }
    return [super hitTest:point withEvent:event];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event {
    for (UIView* bubble in self.subviews) {
        if ([bubble conformsToProtocol:@protocol(MMBubbleButton)]) {
            if ([bubble pointInside:[self convertPoint:point toView:bubble] withEvent:event]) {
                return YES;
            }
        }
    }
    return [super pointInside:point withEvent:event];
}

#pragma mark - MMFullScreenSidebarContainingView

- (void)sidebarCloseButtonWasTapped {
    if ([self isVisible]) {
        [contentView viewWillHide];

        // reset our buttons
        for (UIView<MMBubbleButton>* subview in self.subviews) {
            if ([subview conformsToProtocol:@protocol(MMBubbleButton)]) {
                subview.view = subview.view;
                subview.view.alpha = subview.view.alpha;
            }
        }

        [self hide:YES onComplete:^(BOOL finished) {
            [self resetAlphaForButtonsWithoutAnimation];
            [contentView viewDidHide];
        }];
        [UIView animateWithDuration:kAnimationDuration animations:^{
            [self setAlpha:1];
        } completion:nil];
        [self.delegate sidebarCloseButtonWasTapped:self];
    }
}

#pragma mark - MMSidebarButtonDelegate

- (CGFloat)sidebarButtonRotation {
    return 0;
}

#pragma mark - Rotation

- (void)didRotateToIdealOrientation:(UIInterfaceOrientation)orientation {
    [contentView didRotateToIdealOrientation:orientation];
}

#pragma mark - For Content

- (Class)sidebarButtonClass {
    return [MMCountableSidebarButton class];
}

@end
