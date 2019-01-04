//
//  MMPaperStackView.m
//  Loose Leaf
//
//  Created by Adam Wulf on 6/7/12.
//  Copyright (c) 2012 Milestone Made, LLC. All rights reserved.
//

#import "MMPaperStackView.h"
#import <QuartzCore/QuartzCore.h>
#import "MMShadowManager.h"
#import "NSThread+BlockAdditions.h"
#import "MMScrappedPaperView.h"
#import "Mixpanel.h"
#import "MMExportablePaperView.h"
#import "NSMutableSet+Extras.h"
#import "MMSingleStackManager.h"
#import "MMVisibleStackHolderView.h"
#import "MMHiddenStackHolderView.h"
#import "MMBezelStackHolderView.h"
#import "UIScreen+MMSizing.h"

#define kBounceThreshhold .1


@implementation MMPaperStackView {
    MMPapersIcon* _papersIcon;
    MMPaperIcon* _paperIcon;
    MMPlusIcon* _plusIcon;
    MMLeftArrow* _leftArrow;
    MMRightArrow* _rightArrow;

    // track if we're currently pulling in a page
    // from the bezel
    MMPaperView* _inProgressOfBezeling;
}

@synthesize uuid = _uuid;
@synthesize stackManager = _stackManager;
@synthesize stackDelegate = _stackDelegate;
@synthesize visibleStackHolder = _visibleStackHolder;
@synthesize hiddenStackHolder = _hiddenStackHolder;
@synthesize bezelStackHolder = _bezelStackHolder;

- (id)initWithFrame:(CGRect)frame andUUID:(NSString*)uuid {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _uuid = uuid;
        // Initialization code
        _setOfPagesBeingPanned = [[NSMutableSet alloc] init]; // use this as a quick cache of pages being panned
        // These custom classes exist so that they
        // are easily discernable in the UI inspector in
        // the debugger.
        _visibleStackHolder = [[MMVisibleStackHolderView alloc] initWithFrame:self.bounds];
        _hiddenStackHolder = [[MMHiddenStackHolderView alloc] initWithFrame:self.bounds];
        _bezelStackHolder = [[MMBezelStackHolderView alloc] initWithFrame:self.bounds];

        _bezelStackHolder.userInteractionEnabled = NO;

        _visibleStackHolder.tag = 0;
        _bezelStackHolder.tag = 1;
        _hiddenStackHolder.tag = 2;

        CGRect frameOfHiddenStack = _hiddenStackHolder.frame;
        frameOfHiddenStack.origin.x += _hiddenStackHolder.bounds.size.width + 10;
        _hiddenStackHolder.frame = frameOfHiddenStack;
        _bezelStackHolder.frame = frameOfHiddenStack;

        _hiddenStackHolder.clipsToBounds = YES;
        _visibleStackHolder.clipsToBounds = YES;
        _bezelStackHolder.clipsToBounds = NO;

        _stackManager = [[MMSingleStackManager alloc] initWithUUID:self.uuid visibleStack:_visibleStackHolder andHiddenStack:_hiddenStackHolder andBezelStack:_bezelStackHolder];

        //
        // icons for moving and panning pages
        [self addSubview:_visibleStackHolder];
        [self addSubview:_hiddenStackHolder];
        [self addSubview:_bezelStackHolder];
        _papersIcon = [[MMPapersIcon alloc] initWithFrame:CGRectMake([UIScreen screenWidth] - 168, [UIScreen screenHeight] / 2 - 52, 80, 80)];
        [self addSubview:_papersIcon];
        _paperIcon = [[MMPaperIcon alloc] initWithFrame:CGRectMake([UIScreen screenWidth] - 168, [UIScreen screenHeight] / 2 - 52, 80, 80)];
        [self addSubview:_paperIcon];
        _plusIcon = [[MMPlusIcon alloc] initWithFrame:CGRectMake([UIScreen screenWidth] - 228, [UIScreen screenHeight] / 2 - 36, 46, 46)];
        [self addSubview:_plusIcon];
        _leftArrow = [[MMLeftArrow alloc] initWithFrame:CGRectMake([UIScreen screenWidth] - 228, [UIScreen screenHeight] / 2 - 36, 46, 46)];
        [self addSubview:_leftArrow];
        _rightArrow = [[MMRightArrow alloc] initWithFrame:CGRectMake([UIScreen screenWidth] - 88, [UIScreen screenHeight] / 2 - 36, 46, 46)];
        [self addSubview:_rightArrow];
        _papersIcon.alpha = 0;
        _paperIcon.alpha = 0;
        _leftArrow.alpha = 0;
        _rightArrow.alpha = 0;
        _plusIcon.alpha = 0;

        _fromRightBezelGesture = [[MMBezelInGestureRecognizer alloc] initWithTarget:self action:@selector(isBezelingInRightWithGesture:)];
        _fromRightBezelGesture.gestureIsFromRightBezel = YES;
        [self addGestureRecognizer:_fromRightBezelGesture];

        _fromLeftBezelGesture = [[MMBezelInGestureRecognizer alloc] initWithTarget:self action:@selector(isBezelingInLeftWithGesture:)];
        [self addGestureRecognizer:_fromLeftBezelGesture];
    }
    return self;
}

- (int)fullByteSize {
    return _papersIcon.fullByteSize + _paperIcon.fullByteSize + _plusIcon.fullByteSize + _leftArrow.fullByteSize + _rightArrow.fullByteSize;
}

- (NSString*)activeGestureSummary {
    @throw kAbstractMethodException;
}


#pragma mark - Gesture Helpers

- (void)cancelAllGestures {
    [_fromLeftBezelGesture cancel];
    [_fromRightBezelGesture cancel];
}

#pragma mark - Future Model Methods

/**
 * this function makes sure there's at least numberOfPagesToEnsure pages
 * in the hidden stack, and returns the top page
 */
- (void)ensureAtLeast:(NSInteger)numberOfPagesToEnsure pagesInStack:(UIView*)stackView {
    while ([stackView.subviews count] < numberOfPagesToEnsure) {
        MMEditablePaperView* page = [[MMExportablePaperView alloc] initWithFrame:stackView.bounds];
        page.delegate = self;
        [stackView addSubviewToBottomOfStack:page];
        [[[Mixpanel sharedInstance] people] increment:kMPNumberOfPages by:@(1)];
    }
    [self saveStacksToDisk];
}

/**
 * adds the page to the bottom of the stack
 * and adds to the bottom of the subviews
 */
- (void)addPaperToBottomOfStack:(MMPaperView*)page {
    page.isBrandNewPage = NO;
    page.delegate = self;
    [page enableAllGestures];
    [_visibleStackHolder addSubviewToBottomOfStack:page];
}

/**
 * adds the page to the bottom of the stack
 * and adds to the bottom of the subviews
 */
- (void)addPage:(MMPaperView*)page belowPage:(MMPaperView*)otherPage {
    page.isBrandNewPage = NO;
    page.delegate = self;
    [page enableAllGestures];
    if ([_bezelStackHolder containsSubview:otherPage]) {
        [_visibleStackHolder pushSubview:page];
    } else if ([_visibleStackHolder containsSubview:otherPage]) {
        // this will convert the frame of the newly inserted page
        [_visibleStackHolder pushSubview:page];
        // and this will position it at the correct index
        [_visibleStackHolder insertSubview:page belowSubview:otherPage];
    } else if ([_hiddenStackHolder containsSubview:otherPage]) {
        // this will convert the frame of the newly inserted page
        [_hiddenStackHolder pushSubview:page];
        // and this will position it at the correct index
        [_hiddenStackHolder insertSubview:page aboveSubview:otherPage];
    }
}

/**
 * adds the page to the bottom of the stack
 * and adds to the bottom of the subviews
 */
- (void)addPaperToBottomOfHiddenStack:(MMPaperView*)page {
    page.delegate = self;
    [page disableAllGestures];
    [_hiddenStackHolder addSubviewToBottomOfStack:page];
}


#pragma mark - Pan and Bezel Icons

/**
 * we need to update the icons that are visible
 * depending on the locations of the pages that are
 * currently being panned and scaled
 *
 * this is the + <= => icons on the right side of the screen
 * when a page is being panned
 */
- (void)updateIconAnimations {
    // YES if we're pulling pages in from the hidden stack, NO otherwise
    BOOL bezelingFromRight = _fromRightBezelGesture.subState == UIGestureRecognizerStateBegan || _fromRightBezelGesture.subState == UIGestureRecognizerStateChanged;
    // YES if the top page will bezel right, NO otherwise
    BOOL topPageWillBezelRight = [[_visibleStackHolder peekSubview] willExitToBezel:MMBezelDirectionRight];
    // YES if the top page will bezel left, NO otherwise
    BOOL topPageWillBezelLeft = [[_visibleStackHolder peekSubview] willExitToBezel:MMBezelDirectionLeft];
    // number of times the top page has been bezeled
    NSInteger numberOfTimesTheTopPageHasExitedBezel = [[_visibleStackHolder peekSubview] numberOfTimesExitedBezel];

    // YES if a non top page is will exit bezel
    BOOL nonTopPageWillExitBezel = _inProgressOfBezeling != [_visibleStackHolder peekSubview] && ([_inProgressOfBezeling numberOfTimesExitedBezel] > 0);
    // YES if we should show the right arrow (push pages to hidden stack)
    BOOL showRightArrow = NO;
    if ([_setOfPagesBeingPanned count] > 1 ||
        (topPageWillBezelRight && numberOfTimesTheTopPageHasExitedBezel > 0) ||
        nonTopPageWillExitBezel) {
        showRightArrow = YES;
    }
    // YES if we should show the left arrow (pulling pages in from hidden stack)
    BOOL showLeftArrow = NO;
    if (topPageWillBezelLeft && numberOfTimesTheTopPageHasExitedBezel > 0) {
        showLeftArrow = YES;
    }
    if (bezelingFromRight) {
        if ((_fromRightBezelGesture.panDirection & MMBezelDirectionLeft) == MMBezelDirectionLeft) {
            showLeftArrow = YES;
        } else if ((_fromRightBezelGesture.panDirection & MMBezelDirectionRight) == MMBezelDirectionRight) {
            showRightArrow = YES;
        }
    }

    MMPaperView* topPage = [_visibleStackHolder peekSubview];
    if ([self shouldPushPageOntoVisibleStack:topPage withFrame:topPage.frame]) {
        showLeftArrow = YES;
    }
    if ([self shouldPopPageFromVisibleStack:topPage withFrame:topPage.frame]) {
        showRightArrow = YES;
    }

    if ([_visibleStackHolder peekSubview].scale < kMinPageZoom) {
        //
        // ok, we're in zoomed out mode, looking at the list
        // of all the pages, so hide all the icons
        showLeftArrow = NO;
        showRightArrow = NO;
    }

    //
    // now all the variables are set, we know our state
    // so update the actual icons
    if ((showLeftArrow || showRightArrow) &&
        ((!showLeftArrow && _leftArrow.alpha) ||
         (!showRightArrow && _rightArrow.alpha) ||
         (!_paperIcon.alpha && [_setOfPagesBeingPanned count] == 1) ||
         (!_papersIcon.alpha && [_setOfPagesBeingPanned count] > 1) ||
         (!_paperIcon.alpha && topPageWillBezelRight && numberOfTimesTheTopPageHasExitedBezel > 0) ||
         (!_paperIcon.alpha && nonTopPageWillExitBezel) ||
         bezelingFromRight)) {
        [_papersIcon removeAllAnimationsAndPreservePresentationFrame];

        __block CGFloat papersIconAlpha = 0;
        __block CGFloat paperIconAlpha = 0;
        __block CGFloat leftArrowAlpha = 0;
        __block CGFloat plusIconAlpha = 0;
        __block CGFloat rightArrowAlpha = 0;

        if (([_setOfPagesBeingPanned count] > 1 && !nonTopPageWillExitBezel)) {
            //
            // user is holding the top page
            // plus at least 1 other
            //
            // calculate the number of pages that will be sent
            // to the hidden stack if the user stops panning
            // the top page
            NSInteger numberToShowOnPagesIconIfNeeded = 0;
            for (MMPaperView* page in [[_visibleStackHolder.subviews copy] reverseObjectEnumerator]) {
                if ([page isBeingPannedAndZoomed] && page != [_visibleStackHolder peekSubview]) {
                    break;
                } else {
                    numberToShowOnPagesIconIfNeeded++;
                }
            }

            //
            // update the icons as necessary
            papersIconAlpha = numberToShowOnPagesIconIfNeeded > 1 ? 1 : 0;
            paperIconAlpha = numberToShowOnPagesIconIfNeeded > 1 ? 0 : 1;
            _papersIcon.numberToShowIfApplicable = numberToShowOnPagesIconIfNeeded;

            //
            // show right arrow since this gesture can only send pages
            // to the hidden stack
            plusIconAlpha = 0;
            leftArrowAlpha = 0;
            rightArrowAlpha = 1;
        } else {
            if (bezelingFromRight && _fromRightBezelGesture.numberOfRepeatingBezels > 1) {
                //
                // show the number of pages that the user
                // is bezeling in
                _papersIcon.numberToShowIfApplicable = _fromRightBezelGesture.numberOfRepeatingBezels;
                papersIconAlpha = 1;
                paperIconAlpha = 0;
            } else if (numberOfTimesTheTopPageHasExitedBezel > 1) {
                //
                // show pages icon w/ numbers if the user is exiting
                // bezel more than once
                if (numberOfTimesTheTopPageHasExitedBezel > 50) {
                    @throw [NSException exceptionWithName:@"BezelException" reason:@"Too many pages being bezeled" userInfo:nil];
                }
                _papersIcon.numberToShowIfApplicable = numberOfTimesTheTopPageHasExitedBezel;
                papersIconAlpha = 1;
                paperIconAlpha = 0;
            } else {
                //
                // ok, we're dealing with only
                // panning the top most page
                papersIconAlpha = 0;
                paperIconAlpha = 1;
            }

            if (showLeftArrow && bezelingFromRight && ![_bezelStackHolder peekSubview].isBrandNewPage) {
                leftArrowAlpha = 1;
                plusIconAlpha = 0;
            } else if (showLeftArrow && [_hiddenStackHolder.subviews count] && ![_hiddenStackHolder peekSubview].isBrandNewPage) {
                leftArrowAlpha = 1;
                plusIconAlpha = 0;
            } else if (showLeftArrow) {
                leftArrowAlpha = 0;
                plusIconAlpha = 1;
            } else if (!showLeftArrow) {
                leftArrowAlpha = 0;
                plusIconAlpha = 0;
            }
            if (showRightArrow) {
                rightArrowAlpha = 1;
            } else {
                rightArrowAlpha = 0;
            }
        }

        if (_papersIcon.alpha == papersIconAlpha &&
            _paperIcon.alpha == paperIconAlpha &&
            _leftArrow.alpha == leftArrowAlpha &&
            _plusIcon.alpha == plusIconAlpha &&
            _rightArrow.alpha == rightArrowAlpha) {
            //               DebugLog(@"duplicate animation");
        } else {
            [UIView animateWithDuration:0.2
                                  delay:0
                                options:UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                                 _papersIcon.alpha = papersIconAlpha;
                                 _paperIcon.alpha = paperIconAlpha;
                                 _leftArrow.alpha = leftArrowAlpha;
                                 _plusIcon.alpha = plusIconAlpha;
                                 _rightArrow.alpha = rightArrowAlpha;
                             }
                             completion:nil];
        }
    } else if (!showLeftArrow && !showRightArrow && (_paperIcon.alpha || _papersIcon.alpha)) {
        if (_papersIcon.alpha == 0 &&
            _paperIcon.alpha == 0 &&
            _leftArrow.alpha == 0 &&
            _plusIcon.alpha == 0 &&
            _rightArrow.alpha == 0) {
            //               DebugLog(@"duplicate animation");
        } else {
            [UIView animateWithDuration:0.3
                                  delay:0
                                options:UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                                 _papersIcon.alpha = 0;
                                 _paperIcon.alpha = 0;
                                 _leftArrow.alpha = 0;
                                 _plusIcon.alpha = 0;
                                 _rightArrow.alpha = 0;
                             }
                             completion:nil];
        }
    }
}


#pragma mark - Bezel Left and Right Gestures

- (void)addPageButtonTapped:(UIButton*)button {
    if ([_setOfPagesBeingPanned count]) {
        DebugLog(@"adding new page, but pages are being panned.");
        for (MMPaperView* page in [_setOfPagesBeingPanned copy]) {
            [page cancelAllGestures];
        }
    }
    [[_visibleStackHolder peekSubview] cancelAllGestures];
}

/**
 * this is the event handler for the MMBezelInRightGestureRecognizer
 *
 * this handles pulling pages from the hidden stack onto the visible
 * stack. either one at a time, or multiple if the gesture is repeated
 * without interruption.
 */
- (void)isBezelingInLeftWithGesture:(MMBezelInGestureRecognizer*)bezelGesture {
    CGPoint translation = [bezelGesture translationInView:self];

    if ([bezelGesture isActivelyBezeling] &&
        !bezelGesture.hasSeenSubstateBegin &&
        (bezelGesture.subState == UIGestureRecognizerStateBegan || bezelGesture.subState == UIGestureRecognizerStateChanged)) {
        // a bezel might begin while a page is being actively
        // panned. in this case, the pan gesture (or ruler, etc) should be cancelled
        // so that bezel will own the entire touch state except for scrap panning
        // and/or drawing
        if ([_setOfPagesBeingPanned count]) {
            DebugLog(@"Wanting to bezel from left, but pages are being panned.");
            for (MMPaperView* page in [_setOfPagesBeingPanned copy]) {
                [page cancelAllGestures];
            }
        }

        // make sure to disable all gestures on the top page.
        // this will cancel any strokes / ruler / etc
        [[_visibleStackHolder peekSubview] disableAllGestures];

        // this flag is an ugly hack because i'm using substates in gestures.
        // ideally, i could handle this gesture entirely inside of the state,
        // but i get an odd sitation where the gesture steals touches even
        // though its state has never been set to began (see https://github.com/adamwulf/loose-leaf/issues/455 ).
        //
        // worse, i can set the substate to Began, but it's possible that both
        // the touchesBegan: and touchesMoved: gets called on the gesture before
        // the delegate is notified, so i've no idea when to set the substate from
        // began to changed, because i never know when the delegate has or hasn't
        // been notified about the substate
        bezelGesture.hasSeenSubstateBegin = YES;

        //
        // ok, the user is beginning the drag two fingers from the
        // left hand bezel. we need to push a page from the visible
        // stack onto the bezel stack, and then we'll move that bezel
        // stack with the user's fingers
        if ([_bezelStackHolder.subviews count]) {
            // uh oh, we still have views in the bezel gesture
            // that haven't compeleted their animation.
            //
            // we need to cancel all of their animations
            // and move them immediately to the visible view
            // being sure to maintain proper order
            while ([_bezelStackHolder.subviews count]) {
                MMPaperView* page = [_bezelStackHolder.subviews firstObject];
                [page.layer removeAllAnimations];
                [page enableAllGestures];
                [_visibleStackHolder pushSubview:page];
                if ([_bezelStackHolder.subviews count] != 1) {
                    // this will immediately move all pages
                    // that are already in the bezel stack, but
                    // won't immediately move the new page that
                    // we're adding
                    page.frame = _visibleStackHolder.bounds;
                }
            }
        }
        [_bezelStackHolder removeAllAnimationsAndPreservePresentationFrame];
        _bezelStackHolder.frame = _visibleStackHolder.frame;

        // make sure we have two pages, the one we're pulling, and
        // the one below it
        [[_visibleStackHolder peekSubview] removeAllAnimationsAndPreservePresentationFrame];
        [_bezelStackHolder pushSubview:[_visibleStackHolder peekSubview]];
        [self mayChangeTopPageTo:[_visibleStackHolder peekSubview]];
        // at this point, the bezel stack is immediately on top of the visible stack,
        // and it has 1 page in it. now animate the bezel stack to the user's finger
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
            CGRect newFrame = CGRectMake(_visibleStackHolder.frame.origin.x + translation.x,
                                         _visibleStackHolder.frame.origin.y,
                                         _visibleStackHolder.frame.size.width,
                                         _visibleStackHolder.frame.size.height);
            _bezelStackHolder.frame = newFrame;
            [_bezelStackHolder peekSubview].frame = _bezelStackHolder.bounds;
        } completion:nil];
    } else if ([bezelGesture isActivelyBezeling] &&
               (bezelGesture.subState == UIGestureRecognizerStateCancelled || bezelGesture.subState == UIGestureRecognizerStateFailed ||
                (bezelGesture.subState == UIGestureRecognizerStateEnded && ((bezelGesture.panDirection & MMBezelDirectionLeft) != MMBezelDirectionLeft)))) {
        //
        // ok, the user has completed a bezel gesture, so we should take all
        // the pages in the bezel view and push them onto the hidden stack
        //
        // to do that, we'll just pop all of the bezel stack straight over
        // to the hidden stack

        if ([_bezelStackHolder.subviews count]) {
            if ([_visibleStackHolder.subviews count] == 0) {
                [self animateAdditionalPageIntoVisibleStackFromLeft];
            }

            NSArray* pagesToDisable = [_bezelStackHolder.subviews copy];
            [self willNotChangeTopPageTo:[_bezelStackHolder peekSubview]];
            [self willChangeTopPageTo:[_visibleStackHolder peekSubview]];
            [self emptyBezelStackToHiddenStackAnimated:YES onComplete:^(BOOL finished) {
                if (!finished) {
                    DebugLog(@"not finished4!");
                }
                [self didChangeTopPage];
                // since we've added pages to the hidden stack, make sure
                // all of their gestures are turned off
                for (MMPaperView* page in pagesToDisable) {
                    [page disableAllGestures];
                }
            }];
            [[_visibleStackHolder peekSubview] enableAllGestures];
        }
    } else if ([bezelGesture isActivelyBezeling] &&
               bezelGesture.subState == UIGestureRecognizerStateEnded &&
               ((bezelGesture.panDirection & MMBezelDirectionLeft) == MMBezelDirectionLeft)) {
        //
        // they cancelled the bezel. so push all the views from the bezel back
        // onto the visible stack, then animate them back into position.
        //
        // during the animation, all of the views are still inside the bezelStackHolder
        // until the animation for that page completes. they're not re-added to the
        // visible stack until their animation completes.
        //
        // this is handled in the UIGestureRecognizerStateBegan state, if the user
        // begins a new bezel gesture but the animations for the previous bezel
        // haven't completed.
        [[_visibleStackHolder peekSubview] enableAllGestures];
        if ([_bezelStackHolder.subviews count]) {
            [self willNotChangeTopPageTo:[_visibleStackHolder peekSubview]];
            NSArray* pagesToEnable = [_bezelStackHolder.subviews copy];
            while ([_bezelStackHolder.subviews count]) {
                // this will translate the frame from the bezel stack to the
                // hidden stack, so that the pages appear in the same place
                // to the user, the pop calls next will animate them to the
                // visible stack
                [_hiddenStackHolder pushSubview:[_bezelStackHolder peekSubview]];
            }
            void (^finishedBlock)(BOOL finished) = ^(BOOL finished) {
                _bezelStackHolder.frame = _hiddenStackHolder.frame;
                [self didChangeTopPage];
                // since we've added pages to the hidden stack, make sure
                // all of their gestures are turned off
                for (MMPaperView* page in pagesToEnable) {
                    [page enableAllGestures];
                }
            };
            // now pop all of those pages back onto the visible stack.
            // each of these came from the visible stack initially, so
            // we don't need to toggle their gestures enabled/disabled
            [self popHiddenStackForPages:bezelGesture.numberOfRepeatingBezels onComplete:finishedBlock];

            //
            // successful gesture complete, so reset the gesture count
            // we only reset on the successful gesture, not a cancelled gesture
            //
            // that way, if the user moves their entire 2 fingers off bezel and
            // immediately back on bezel, then it'll increment count correctly
            [bezelGesture resetPageCount];
        }
    } else if ([bezelGesture isActivelyBezeling] &&
               bezelGesture.subState == UIGestureRecognizerStateChanged &&
               bezelGesture.numberOfRepeatingBezels) {
        //
        // we're in progress of a bezel gesture from the right
        //
        // let's:
        // a) make sure we're bezeling the correct number of pages
        // b) make sure that (a) animates them to the correct place
        // c) add correct number of pages to the bezelStackHolder
        // d) update the offset for the bezelStackHolder so they all move in tandem
        BOOL needsAnimationUpdate = bezelGesture.numberOfRepeatingBezels != [_bezelStackHolder.subviews count];
        while (bezelGesture.numberOfRepeatingBezels != [_bezelStackHolder.subviews count]) {
            //
            // we need to add another page
            [self ensureAtLeast:1 pagesInStack:_visibleStackHolder];
            if ([[_visibleStackHolder peekSubview] isBeingPannedAndZoomed]) {
                [[_visibleStackHolder peekSubview] cancelAllGestures];
            }
            [_bezelStackHolder insertSubview:[_visibleStackHolder peekSubview]];
            [[_visibleStackHolder peekSubview] disableAllGestures];
        }
        if (needsAnimationUpdate) {
            //
            // we just added a new page to the bezel gesture,
            // so make sure we've notified that it may be the new top
            [self mayChangeTopPageTo:[_visibleStackHolder peekSubview]];

            //
            // ok, animate them all into place
            NSInteger numberOfPages = [_bezelStackHolder.subviews count];
            CGFloat delta;
            if (numberOfPages < 10) {
                delta = 10;
            } else {
                delta = 100 / numberOfPages;
            }
            CGFloat currOffset = 0;
            for (MMPaperView* page in _bezelStackHolder.subviews) {
                CGRect fr = page.frame;
                if (fr.origin.x != currOffset) {
                    fr.origin.x = currOffset;
                    if (page == [_bezelStackHolder.subviews firstObject]) {
                        [UIView animateWithDuration:0.2 animations:^{
                            page.frame = fr;
                        }];
                    } else {
                        page.frame = fr;
                    }
                }
                currOffset += delta;
            }
        }
        CGRect newFrame = CGRectMake(_visibleStackHolder.frame.origin.x + translation.x - kFingerWidth,
                                     _visibleStackHolder.frame.origin.y,
                                     _visibleStackHolder.frame.size.width,
                                     _visibleStackHolder.frame.size.height);
        _bezelStackHolder.frame = newFrame;

        // in some cases, the top page on the visible stack will
        // think it's also being panned at the same time as this bezel
        // gesture
        //
        // double check and cancel it if needbe.
        MMPaperView* topPage = [_visibleStackHolder peekSubview];
        if ([topPage isBeingPannedAndZoomed]) {
            [topPage cancelAllGestures];
        }
    }
    [self updateIconAnimations];
}


/**
 * this is the event handler for the MMBezelInRightGestureRecognizer
 *
 * this handles pulling pages from the hidden stack onto the visible
 * stack. either one at a time, or multiple if the gesture is repeated
 * without interruption.
 */
- (void)isBezelingInRightWithGesture:(MMBezelInGestureRecognizer*)bezelGesture {
    CGPoint translation = [bezelGesture translationInView:self];

    if ([bezelGesture isActivelyBezeling] &&
        !bezelGesture.hasSeenSubstateBegin &&
        (bezelGesture.subState == UIGestureRecognizerStateBegan || bezelGesture.subState == UIGestureRecognizerStateChanged)) {
        // cancel panning all pages, if any
        // this will make sure to cancel pages from back to front,
        // so that the top held page will fall back onto the visible stack.
        //
        // otherwise, if the front page was released first, it + all
        // pages to the next held page would be pushed immediately onto
        // the hidden stack, and would end up held by the bezel. the user
        // would see the top page suddenly 'disappear' and suddenly held
        // by the bezel.
        [[[_setOfPagesBeingPanned allObjects] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            // put the top visible page last
            if (obj1 == [_visibleStackHolder peekSubview]) {
                return NSOrderedDescending;
            } else if (obj2 == [_visibleStackHolder peekSubview]) {
                return NSOrderedAscending;
            }
            return NSOrderedSame;
        }] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
            // now cancel all of those pages pan gestures
            if ([obj panGesture].subState != UIGestureRecognizerStatePossible) {
                [[obj panGesture] cancel];
            }
        }];

        // make sure there's a page to bezel
        [self ensureAtLeast:1 pagesInStack:_hiddenStackHolder];
        // this flag is an ugly hack because i'm using substates in gestures.
        // ideally, i could handle this gesture entirely inside of the state,
        // but i get an odd sitation where the gesture steals touches even
        // though its state has never been set to began (see https://github.com/adamwulf/loose-leaf/issues/455 ).
        //
        // worse, i can set the substate to Began, but it's possible that both
        // the touchesBegan: and touchesMoved: gets called on the gesture before
        // the delegate is notified, so i've no idea when to set the substate from
        // began to changed, because i never know when the delegate has or hasn't
        // been notified about the substate
        bezelGesture.hasSeenSubstateBegin = YES;
        [[_visibleStackHolder peekSubview] saveToDisk:nil];
        //
        // ok, the user is beginning the drag two fingers from the
        // right hand bezel. we need to push a page from the hidden
        // stack onto the bezel stack, and then we'll move that bezel
        // stack with the user's fingers
        if ([_bezelStackHolder.subviews count]) {
            // uh oh, we still have views in the bezel gesture
            // that haven't compeleted their animation.
            //
            // this may happen from the new page bumped onto the bezel
            // when panning a page far left
            //
            // we need to cancel all of their animations
            // and move them immediately to the hidden view
            // being sure to maintain proper order
            //            DebugLog(@"empty bezel stack");
            while ([_bezelStackHolder.subviews count]) {
                MMPaperView* page = [_bezelStackHolder peekSubview];
                [page.layer removeAllAnimations];
                [_hiddenStackHolder pushSubview:page];
                page.frame = _hiddenStackHolder.bounds;
                //                DebugLog(@"pushing %@ onto hidden", page.uuid);
            }
        } else {
            //            DebugLog(@"get top of hidden stack");
        }
        [[_visibleStackHolder peekSubview] disableAllGestures];
        //        DebugLog(@"right bezelling %@", [hiddenStackHolder peekSubview].uuid);
        [self mayChangeTopPageTo:[_hiddenStackHolder peekSubview]];
        [_bezelStackHolder pushSubview:[_hiddenStackHolder peekSubview]];
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            CGRect newFrame = CGRectMake(_hiddenStackHolder.frame.origin.x + translation.x,
                                         _hiddenStackHolder.frame.origin.y,
                                         _hiddenStackHolder.frame.size.width,
                                         _hiddenStackHolder.frame.size.height);
            _bezelStackHolder.frame = newFrame;
            [_bezelStackHolder peekSubview].frame = _bezelStackHolder.bounds;
        } completion:nil];
    } else if ([bezelGesture isActivelyBezeling] &&
               (bezelGesture.subState == UIGestureRecognizerStateCancelled || bezelGesture.subState == UIGestureRecognizerStateFailed ||
                (bezelGesture.subState == UIGestureRecognizerStateEnded && ((bezelGesture.panDirection & MMBezelDirectionLeft) != MMBezelDirectionLeft)))) {
        //
        // they cancelled the bezel. so push all the views from the bezel back
        // onto the hidden stack, then animate them back into position.
        //
        // during the animation, all of the views are still inside the bezelStackHolder
        // until the animation for that page completes. they're not re-added to the
        // hidden stack until their animation completes.
        //
        // this is handled in the UIGestureRecognizerStateBegan state, if the user
        // begins a new bezel gesture but the animations for the previous bezel
        // haven't completed.

        if ([_bezelStackHolder.subviews count]) {
            [self willNotChangeTopPageTo:[_bezelStackHolder peekSubview]];
            [self emptyBezelStackToHiddenStackAnimated:YES onComplete:nil];
            [[_visibleStackHolder peekSubview] enableAllGestures];
        }
    } else if ([bezelGesture isActivelyBezeling] &&
               bezelGesture.subState == UIGestureRecognizerStateEnded &&
               ((bezelGesture.panDirection & MMBezelDirectionLeft) == MMBezelDirectionLeft)) {
        if ([_bezelStackHolder.subviews count]) {
            //
            // ok, the user has completed a bezel gesture, so we should take all
            // the pages in the bezel view and push them onto the visible stack
            //
            // to do that, we'll move them back onto the hidden frame (and retain their visible frame)
            // and then use our animation functions to pop them off the hidden stack onto
            // the visible stack
            //
            // this'll let us move the bezel frame back to its hidden place above the hidden stack
            // immediately
            NSArray* pagesToEnable = [_bezelStackHolder.subviews copy];
            [[_visibleStackHolder peekSubview] enableAllGestures];
            [self willChangeTopPageTo:[_bezelStackHolder peekSubview]];
            while ([_bezelStackHolder.subviews count]) {
                // this will translate the frame from the bezel stack to the
                // hidden stack, so that the pages appear in the same place
                // to the user, the pop calls next will animate them to the
                // visible stack
                [_hiddenStackHolder pushSubview:[_bezelStackHolder peekSubview]];
            }
            void (^finishedBlock)(BOOL finished) = ^(BOOL finished) {
                _bezelStackHolder.frame = _hiddenStackHolder.frame;
                [self didChangeTopPage];
                // since we've added pages to the hidden stack, make sure
                // all of their gestures are turned off
                for (MMPaperView* page in pagesToEnable) {
                    [page enableAllGestures];
                }
            };
            [self popHiddenStackForPages:bezelGesture.numberOfRepeatingBezels onComplete:finishedBlock];

            //
            // successful gesture complete, so reset the gesture count
            // we only reset on the successful gesture, not a cancelled gesture
            //
            // that way, if the user moves their entire 2 fingers off bezel and
            // immediately back on bezel, then it'll increment count correctly
            [bezelGesture resetPageCount];
        }
    } else if ([bezelGesture isActivelyBezeling] &&
               bezelGesture.subState == UIGestureRecognizerStateChanged &&
               bezelGesture.numberOfRepeatingBezels) {
        //
        // we're in progress of a bezel gesture from the right
        //
        // let's:
        // a) make sure we're bezeling the correct number of pages
        // b) make sure that (a) animates them to the correct place
        // c) add correct number of pages to the bezelStackHolder
        // d) update the offset for the bezelStackHolder so they all move in tandem
        BOOL needsAnimationUpdate = bezelGesture.numberOfRepeatingBezels != [_bezelStackHolder.subviews count];
        while (bezelGesture.numberOfRepeatingBezels > [_bezelStackHolder.subviews count]) {
            // if we want more pages than are in the stack, then
            // we need to add another page
            // make sure there's a page to bezel
            [self ensureAtLeast:1 pagesInStack:_hiddenStackHolder];
            [_bezelStackHolder pushSubview:[_hiddenStackHolder peekSubview]];
        }
        if (needsAnimationUpdate) {
            // we just added a new page to the bezel gesture,
            // so make sure we've notified that it may be the new top
            [self mayChangeTopPageTo:[_bezelStackHolder peekSubview]];

            //
            // ok, animate them all into place
            NSInteger numberOfPages = [_bezelStackHolder.subviews count];
            CGFloat delta;
            if (numberOfPages < 10) {
                delta = 10;
            } else {
                delta = 100 / numberOfPages;
            }
            CGFloat currOffset = 0;
            for (MMPaperView* page in _bezelStackHolder.subviews) {
                CGRect fr = page.frame;
                if (fr.origin.x != currOffset) {
                    fr.origin.x = currOffset;
                    if (page == [_bezelStackHolder peekSubview]) {
                        [UIView animateWithDuration:.2 animations:^{
                            page.frame = fr;
                        }];
                    } else {
                        page.frame = fr;
                    }
                }
                currOffset += delta;
            }
        }
        CGRect newFrame = CGRectMake(_hiddenStackHolder.frame.origin.x + translation.x - kFingerWidth,
                                     _hiddenStackHolder.frame.origin.y,
                                     _hiddenStackHolder.frame.size.width,
                                     _hiddenStackHolder.frame.size.height);
        _bezelStackHolder.frame = newFrame;

        // in some cases, the top page on the visible stack will
        // think it's also being panned at the same time as this bezel
        // gesture
        //
        // double check and cancel it if needbe.
        MMPaperView* topPage = [_visibleStackHolder peekSubview];
        if ([topPage isBeingPannedAndZoomed]) {
            [topPage cancelAllGestures];
        }
    }
    [self updateIconAnimations];
}

- (void)emptyBezelStackToVisibleStackOnComplete:(void (^)(BOOL finished))completionBlock {
    [_bezelStackHolder removeAllAnimationsAndPreservePresentationFrame];
    CGFloat delay = 0;
    if ([_bezelStackHolder.subviews count] == 0) {
        if (completionBlock)
            completionBlock(YES);
    } else {
        while ([_bezelStackHolder.subviews count]) {
            BOOL isLastToAnimate = [_bezelStackHolder.subviews count] == 1;
            MMPaperView* aPage = [_bezelStackHolder.subviews objectAtIndex:0];
            [aPage removeAllAnimationsAndPreservePresentationFrame];
            [aPage enableAllGestures];
            [_visibleStackHolder pushSubview:aPage];
            [self animatePageToFullScreen:aPage withDelay:delay withBounce:NO onComplete:(isLastToAnimate ? ^(BOOL finished) {
                _bezelStackHolder.frame = _hiddenStackHolder.frame;
                if (completionBlock)
                    completionBlock(finished);
            } : nil)];
            delay += kAnimationDelay;
        }
    }
}
- (void)emptyBezelStackToHiddenStackAnimated:(BOOL)animated onComplete:(void (^)(BOOL finished))completionBlock {
    [self emptyBezelStackToHiddenStackAnimated:animated andPreservePageFrame:NO onComplete:completionBlock];
}
- (void)emptyBezelStackToHiddenStackAnimated:(BOOL)animated andPreservePageFrame:(BOOL)preserveFrame onComplete:(void (^)(BOOL finished))completionBlock {
    [_bezelStackHolder removeAllAnimationsAndPreservePresentationFrame];
    if (animated) {
        CGFloat delay = 0;
        if ([_bezelStackHolder.subviews count] == 0) {
            if (completionBlock)
                completionBlock(YES);
        } else {
            for (MMPaperView* page in [_bezelStackHolder.subviews reverseObjectEnumerator]) {
                BOOL isLastToAnimate = page == [_bezelStackHolder.subviews objectAtIndex:0];
                [self animateBackToHiddenStack:page withDelay:delay onComplete:(isLastToAnimate ? ^(BOOL finished) {
                    // since we're  moving the bezel frame for the drag animation, be sure to re-hide it
                    // above the hidden stack off screen after all the pages animate
                    // back to the hidden stack
                    _bezelStackHolder.frame = _hiddenStackHolder.frame;
                    if (completionBlock)
                        completionBlock(finished);
                } : nil)];
                delay += kAnimationDelay;
            }
        }
    } else {
        for (MMPaperView* page in [[_bezelStackHolder.subviews copy] reverseObjectEnumerator]) {
            [page removeAllAnimationsAndPreservePresentationFrame];
            [_hiddenStackHolder pushSubview:page];
            if (!preserveFrame) {
                page.frame = _hiddenStackHolder.bounds;
            }
        }
        _bezelStackHolder.frame = _hiddenStackHolder.frame;
        if (completionBlock)
            completionBlock(YES);
    }
}

#pragma mark - MMPaperViewDelegate

- (BOOL)isAnimatingTowardPageView {
    @throw kAbstractMethodException;
}

- (void)didStartToWriteWithStylus {
    @throw kAbstractMethodException;
}

- (void)didEndWritingWithStylus {
    @throw kAbstractMethodException;
}

- (void)didDrawStrokeOfCm:(CGFloat)distanceInCentimeters {
    @throw kAbstractMethodException;
}

/**
 * notify that we just long pressed
 */
- (void)didLongPressPage:(MMPaperView*)page withTouches:(NSSet*)touches {
    @throw kAbstractMethodException;
}

/**
 * return true if we should require a long press
 * before picking up a scrap
 */
- (BOOL)panScrapRequiresLongPress {
    @throw kAbstractMethodException;
}

- (BOOL)isAllowedToPan {
    @throw kAbstractMethodException;
}

- (BOOL)isAllowedToBezel {
    return ![_fromLeftBezelGesture isActivelyBezeling] && ![_fromRightBezelGesture isActivelyBezeling];
}

- (BOOL)allowsHoldingScrapsWithTouch:(UITouch*)touch {
    @throw kAbstractMethodException;
}


/**
 * these are implemented in MMEditablePaperStackView
 */
- (void)didMoveRuler:(MMRulerToolGestureRecognizer*)gesture {
    @throw kAbstractMethodException;
}

- (void)didStopRuler:(MMRulerToolGestureRecognizer*)gesture {
    @throw kAbstractMethodException;
}

/**
 * return YES if we're in hand mode, no otherwise
 */
- (BOOL)shouldAllowPan:(MMPaperView*)page {
    return YES;
}

/**
 * let's only allow scaling the top most page
 */
- (BOOL)allowsScaleForPage:(MMPaperView*)page {
    return [_visibleStackHolder peekSubview] == page;
}

/**
 * during a pan, we'll need to show different icons
 * depending on where they drag a page
 */
- (CGRect)isBeginning:(BOOL)isBeginningGesture toPanAndScalePage:(MMPaperView*)page fromFrame:(CGRect)fromFrame toFrame:(CGRect)toFrame withTouches:(NSArray*)touches {
    BOOL isPanningTopPage = page == [_visibleStackHolder peekSubview];

    //
    // resume normal behavior for any pages
    // of normal scale
    if ([page numberOfTimesExitedBezel] > 0) {
        _inProgressOfBezeling = page;
    }
    if (![_setOfPagesBeingPanned containsObject:page]) {
        [_setOfPagesBeingPanned addObject:page];
    }
    [self updateIconAnimations];

    //
    // with the pinch/pan gesture, pages may be
    // loading or unloading. so we should notify
    // when to start pushing pages in or out of
    // caches.
    if (isBeginningGesture && isPanningTopPage) {
        // if they're panning the top page
        [self mayChangeTopPageTo:[_visibleStackHolder getPageBelow:page]];
    } else if (isBeginningGesture) {
        [self mayChangeTopPageTo:page];
    }

    //
    // the user is bezeling a page to the left, which will pop
    // in pages from the hidden stack if they let go
    //
    // let's animate a small pop in
    if (isPanningTopPage && ([page willExitToBezel:MMBezelDirectionLeft] ||
                             [self shouldPushPageOntoVisibleStack:page withFrame:page.frame])) {
        //
        // we're in progress of a bezel gesture from the right
        //
        // let's:
        // a) make sure we're bezeling the correct number of pages
        // b) make sure that (a) animates them to the correct place
        // c) add correct number of pages to the bezelStackHolder
        // d) update the offset for the bezelStackHolder so they all move in tandem
        NSInteger numberOfPagesToAnimateFromRightBezel = 1;
        BOOL needsToUpdateAnimations = numberOfPagesToAnimateFromRightBezel > [_bezelStackHolder.subviews count];
        while (numberOfPagesToAnimateFromRightBezel > [_bezelStackHolder.subviews count]) {
            [self ensureAtLeast:1 pagesInStack:_hiddenStackHolder];
            //
            // we need to add another page
            [_bezelStackHolder pushSubview:[_hiddenStackHolder peekSubview]];
        }
        if (needsToUpdateAnimations) {
            [self mayChangeTopPageTo:[_bezelStackHolder peekSubview]];
            MMPaperView* topPage = [_bezelStackHolder peekSubview];
            CGRect topPageFrame = topPage.frame;
            topPageFrame.origin.x = _visibleStackHolder.frame.size.width - [_bezelStackHolder.layer.presentationLayer frame].origin.x;
            topPage.frame = topPageFrame;
            //
            // ok, animate them all into place
            NSInteger numberOfPages = [_bezelStackHolder.subviews count];
            CGFloat delta;
            if (numberOfPages < 10) {
                delta = 10;
            } else {
                delta = 100 / numberOfPages;
            }
            CGFloat currOffset = 0;
            for (MMPaperView* page in _bezelStackHolder.subviews) {
                CGRect fr = page.frame;
                if (fr.origin.x != currOffset) {
                    fr.origin.x = currOffset;
                    if (page == [_bezelStackHolder peekSubview]) {
                        [UIView animateWithDuration:.2 animations:^{
                            page.frame = fr;
                        }];
                    } else {
                        page.frame = fr;
                    }
                }
                currOffset += delta;
            }
            CGRect newFrame = CGRectMake(_hiddenStackHolder.frame.origin.x - MIN([_bezelStackHolder.subviews count] * 10 + 20, 106),
                                         _hiddenStackHolder.frame.origin.y,
                                         _hiddenStackHolder.frame.size.width,
                                         _hiddenStackHolder.frame.size.height);

            if (!CGRectEqualToRect(_bezelStackHolder.frame, newFrame) ||
                CGRectEqualToRect(_bezelStackHolder.frame, _hiddenStackHolder.frame)) {
                if (CGRectEqualToRect([_bezelStackHolder.layer.presentationLayer frame], _hiddenStackHolder.frame)) {
                    // bounce
                    [UIView animateWithDuration:.1 animations:^{
                        CGRect bounceFrame = newFrame;
                        bounceFrame.origin.x -= 10;
                        _bezelStackHolder.frame = bounceFrame;
                    } completion:^(BOOL finished) {
                        if (finished) {
                            [UIView animateWithDuration:.2 animations:^{
                                _bezelStackHolder.frame = newFrame;
                            }];
                        }
                    }];
                } else {
                    // expand
                    [UIView animateWithDuration:.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
                        _bezelStackHolder.frame = newFrame;
                    } completion:nil];
                }
            }
        }
    } else if (isPanningTopPage) {
        if ([page willExitToBezel:MMBezelDirectionRight] && page.numberOfTimesExitedBezel > 1) {
            //
            // ok, the user is bezeling the top page to the right,
            // so find the page that's page.numberOfTimesExitedBezel
            // below the top page on the visible stack, and notify
            // that we may pop to that page.
            //
            // we only need to notify if the bezel number is > 1 because
            // we'll have already notified about the page immediately below
            // the top page when the user first picked up the top page
            MMPaperView* pageMayPopTo = page;
            for (int i = 0; i < page.numberOfTimesExitedBezel; i++) {
                pageMayPopTo = [_visibleStackHolder getPageBelow:pageMayPopTo];
            }
            if (pageMayPopTo) {
                [self mayChangeTopPageTo:pageMayPopTo];
            }
        } else {
            MMPaperView* pageBelow = [_visibleStackHolder getPageBelow:[_visibleStackHolder peekSubview]];
            if (pageBelow) {
                [self mayChangeTopPageTo:pageBelow];
            }
        }
        if (!CGRectEqualToRect(_bezelStackHolder.frame, _hiddenStackHolder.frame)) {
            // ok, the user isn't bezeling left anymore
            [UIView animateWithDuration:.2 delay:.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
                _bezelStackHolder.frame = _hiddenStackHolder.frame;
            } completion:^(BOOL finished) {
                if (finished && CGRectEqualToRect(_bezelStackHolder.frame, _hiddenStackHolder.frame)) {
                    // empty the bezel stack to the hidden stack,
                    // animates are all offscreen and complete now
                    [_bezelStackHolder.subviews makeObjectsPerformSelector:@selector(removeAllAnimationsAndPreservePresentationFrame)];
                    [self emptyBezelStackToHiddenStackAnimated:NO onComplete:nil];
                }
            }];
        }
    }

    return toFrame;
}

/**
 * the user has completed their panning / scaling gesture
 * on a page. they may still be panning / scaling other pages,
 * so this function will take into account two scenarios:
 *
 * a) user bezel'd a page
 * b) user is done with top page
 * c) user is done with non-top page
 */
- (void)finishedPanningAndScalingPage:(MMPaperView*)page
                            intoBezel:(MMBezelDirection)bezelDirection
                            fromFrame:(CGRect)fromFrame
                              toFrame:(CGRect)toFrame {
    // check if we finished the in progress bezel
    if (page == _inProgressOfBezeling)
        _inProgressOfBezeling = nil;
    // check if we finished the top page
    BOOL justFinishedPanningTheTopPage = [_visibleStackHolder peekSubview] == page;
    // this finished page isn't panned anymore...
    [_setOfPagesBeingPanned removeObject:page];
    // ok, update the icons
    [self updateIconAnimations];

    if (justFinishedPanningTheTopPage && (bezelDirection & MMBezelDirectionLeft) == MMBezelDirectionLeft) {
        [[[Mixpanel sharedInstance] people] set:@{ kMPHasBookTurnedPage: @(YES) }];
        //        DebugLog(@"finished bezelling top page left %d %d", (int) (bezelDirection & MMBezelDirectionLeft), (int) (bezelDirection & MMBezelDirectionRight));
        //
        // CASE 1:
        // left bezel by top page
        // ============================================================================
        //
        // cancel any other gestures going on
        if ([_setOfPagesBeingPanned count]) {
            // need to cancel pages being panned (?)
            for (MMPaperView* aPage in _setOfPagesBeingPanned) {
                [aPage cancelAllGestures];
            }
        }

        MMScrappedPaperView* oldTopVisiblePage = [_visibleStackHolder peekSubview];
        //
        // the bezelStackHolder was been filled during the pan, so add
        // the top page of the visible stack to the bottom of the bezelGestureHolder,
        // then animate
        if ([_bezelStackHolder peekSubview]) {
            [self willChangeTopPageTo:[_bezelStackHolder peekSubview]];
            [self animatePageToFullScreen:page withDelay:0.1 withBounce:NO onComplete:^(BOOL finished) {
                [self didChangeTopPage];
            }];
            [self emptyBezelStackToVisibleStackOnComplete:^(BOOL finished) {
                [self updateIconAnimations];
                [oldTopVisiblePage saveToDisk:nil];
            }];
        } else {
            // we just picked up the top page close to the bezel,
            // and tossed it over the bezel.
            // time to send a page from the hidden stack to the
            // visible stack
            [self ensureAtLeast:1 pagesInStack:_hiddenStackHolder];
            [self willChangeTopPageTo:[_hiddenStackHolder peekSubview]];
            [self popHiddenStackForPages:1 onComplete:^(BOOL completed) {
                page.frame = self.bounds;
                [self didChangeTopPage];
                [oldTopVisiblePage saveToDisk:nil];
            }];
        }
        return;
    } else if (justFinishedPanningTheTopPage && [_setOfPagesBeingPanned count]) {
        //        DebugLog(@"finished top page, but still holding other pages");
        //
        // CASE 2:
        // they released the top page, but are still panning
        // other pages
        // ============================================================================
        //
        // find the top most page that we're still panning,
        // and pop until there.
        MMPaperView* popUntil = nil;
        for (MMPaperView* aPage in [_visibleStackHolder.subviews reverseObjectEnumerator]) {
            if (aPage != page) {
                // don't adjust the page we just dropped
                // obviously :)
                if ([aPage isBeingPannedAndZoomed]) {
                    popUntil = aPage;
                    break;
                }
            }
        }
        if (popUntil) {
            [self willChangeTopPageTo:popUntil];
            [self mayChangeTopPageTo:[_visibleStackHolder getPageBelow:popUntil]];
            [self popStackUntilPage:popUntil onComplete:^(BOOL finished) {
                [self updateIconAnimations];
                [self didChangeTopPage];
            }];
        } else {
            for (MMPaperView* page in _setOfPagesBeingPanned) {
                [page cancelAllGestures];
            }
            [_setOfPagesBeingPanned removeAllObjects];
            [self cancelAllGestures];
        }
        return;
    } else if (!justFinishedPanningTheTopPage && [self shouldPopPageFromVisibleStack:page withFrame:toFrame]) {
        //        DebugLog(@"didn't release top page but need to pop a page");
        //
        // CASE 3:
        // they release a non-top page near the right bezel (but didn't bezel)
        // send the page to hidden stack
        // ============================================================================
        [self willNotChangeTopPageTo:page];
        [page removeAllAnimationsAndPreservePresentationFrame];
        if ([_visibleStackHolder.subviews containsObject:page]) {
            // need to animate with animateBackToHiddenStack:withDelay:onComplete:
            // to keep this page in the visible stack while it animates to the hidden stack.
            // this would prevent the page from snapping in front of the top page during the animation
            // see: https://github.com/adamwulf/loose-leaf/issues/19
            //
            // i used to use [self sendPageToHiddenStack:page onComplete:], but this would put the page in
            // the bezel stack, which would pop it in front of the top held page
            [self animateBackToHiddenStack:page withDelay:0 onComplete:^(BOOL finished) {
                [self updateIconAnimations];
                [self ensureAtLeast:1 pagesInStack:_visibleStackHolder];
            }];
        }
        [self mayChangeTopPageTo:[_visibleStackHolder getPageBelow:[_visibleStackHolder peekSubview]]];
        return;
    } else if ((bezelDirection & MMBezelDirectionRight) == MMBezelDirectionRight) {
        [[[Mixpanel sharedInstance] people] set:@{ kMPHasBookTurnedPage: @(YES) }];
        //        DebugLog(@"finished top page, bezel right");
        //
        // CASE 4:
        // right bezel by any page
        // ============================================================================
        //
        // bezelStackHolder debugging DONE
        //
        // either, i bezeled right the top page and am not bezeling anything else
        // or, i bezeled right a bottom page and am holding the top page
        if (justFinishedPanningTheTopPage) {
            MMScrappedPaperView* oldTopVisiblePage = [_visibleStackHolder peekSubview];

            if ([_visibleStackHolder.subviews count] == 1) {
                [self animateAdditionalPageIntoVisibleStackFromLeft];
            }

            //
            // we bezeled right the top page.
            // send as many as necessary to the hidden stack
            if (page.numberOfTimesExitedBezel > 1) {
                MMPaperView* pageToPopUntil = page;
                for (int i = 0; i < page.numberOfTimesExitedBezel && (![pageToPopUntil isBeingPannedAndZoomed] || pageToPopUntil == page); i++) {
                    if (pageToPopUntil == [_visibleStackHolder.subviews objectAtIndex:0]) {
                        // make sure the visible stack has enough pages in it
                        [self ensureAtLeast:[_visibleStackHolder.subviews count] + 1 pagesInStack:_visibleStackHolder];
                    }
                    pageToPopUntil = [_visibleStackHolder getPageBelow:pageToPopUntil];
                }
                [self willChangeTopPageTo:pageToPopUntil];
                [self popStackUntilPage:pageToPopUntil onComplete:^(BOOL finished) {
                    [self updateIconAnimations];
                    [self didChangeTopPage];
                    [oldTopVisiblePage saveToDisk:nil];
                }];
            } else {
                [self willChangeTopPageTo:[_visibleStackHolder getPageBelow:page]];
                [self sendPageToHiddenStack:page onComplete:^(BOOL finished) {
                    [self updateIconAnimations];
                    [self didChangeTopPage];
                    [oldTopVisiblePage saveToDisk:nil];
                }];
            }
            //
            // now that pages are sent to the hidden stack,
            // realign anything left in the visible stack
            [self realignPagesInVisibleStackExcept:page animated:YES];
        } else {
            //
            // they bezeled right a non-top page, just get
            // rid of it
            [page removeAllAnimationsAndPreservePresentationFrame];
            [self sendPageToHiddenStack:page onComplete:^(BOOL finished) {
                [self updateIconAnimations];
                if ([page isKindOfClass:[MMEditablePaperView class]]) {
                    MMEditablePaperView* editablePage = (MMEditablePaperView*)page;
                    [editablePage saveToDisk:nil];
                }
            }];
        }
        return;
    } else if (!justFinishedPanningTheTopPage) {
        //        DebugLog(@"finished panning non-top page");
        //
        // CASE 5:
        //
        // bezelStackHolder debugging DONE
        //
        // just released a non-top page, but didn't
        // send it anywhere. just exit as long
        // as we're still holding the top page
        // ============================================================================
        if (![[_visibleStackHolder peekSubview] isBeingPannedAndZoomed]) {
            //
            // odd, no idea how this happened. but we
            // just released a non-top page and the top
            // page is not being held.
            //
            // i've only seen this happen when touches get
            // confused and gestures are "still on" even
            // though no fingers are touching the screen
            //
            // just realign and log

            //            NSString* reasonAndDebugInfo = [self activeGestureSummary];
            //            reasonAndDebugInfo = [NSString stringWithFormat:@"released non-top page while top page was not held\n%@", reasonAndDebugInfo];
            //            @throw [NSException exceptionWithName:@"InvalidPageStack" reason:reasonAndDebugInfo userInfo:nil];


            NSString* errorToLogToMixpanel = @"released non-top page while top page was not held";
            [[Mixpanel sharedInstance] track:kMPEventGestureBug properties:@{ @"Gesture Description": errorToLogToMixpanel }];

            //
            // as a backup, i think realignPagesInVisibleStackExcept:nil: would have "worked"... but hard to test
            // so better to kill the app and debug properly.
            //
            // TODO: https://github.com/adamwulf/loose-leaf/issues/896
            //
            // since i can't consistently repro, i'm cancelling all gestures and then
            // realigning pages. we'll also track in mixpanel so i can see how often
            // this shows up in the wild.
            [self cancelAllGestures];
            [[[self visibleStackHolder] peekSubview] cancelAllGestures];
            [self realignPagesInVisibleStackExcept:nil animated:YES];
        }
        return;
    }

    //    DebugLog(@"just released the top page, and no other pages being panned");

    //
    // CASE 6:
    //
    // bezelStackHolder debugging DONE
    //
    // just relased the top page, and no
    // other pages are being held
    // ============================================================================
    // all the actions below will move the top page only,
    // so it's safe to realign allothers
    [self realignPagesInVisibleStackExcept:page animated:YES];

    if (justFinishedPanningTheTopPage && [self shouldPopPageFromVisibleStack:page withFrame:toFrame]) {
        if ([_visibleStackHolder.subviews count] == 1) {
            [self animateAdditionalPageIntoVisibleStackFromLeft];
        }

        //        DebugLog(@"should pop from visible");
        //
        // bezelStackHolder debugging DONE
        // pop the top page, it's close to the right bezel
        [self willChangeTopPageTo:[_visibleStackHolder getPageBelow:page]];
        [self popStackUntilPage:[_visibleStackHolder getPageBelow:page] onComplete:^(BOOL finished) {
            [self updateIconAnimations];
            [self didChangeTopPage];
        }];
    } else if (justFinishedPanningTheTopPage && [self shouldPushPageOntoVisibleStack:page withFrame:toFrame]) {
        //        DebugLog(@"should pop to visible");
        //
        // bezelStackHolder debugging DONE
        //
        // pull a page from the hidden stack, and re-align
        // the top page
        //
        // the user may have bezeled left a lot, but then released
        // the gesture inside the screen (which should only push 1 page).
        //
        // so check the bezelStackHolder
        [self animatePageToFullScreen:page withDelay:0.1 withBounce:NO onComplete:^(BOOL finished) {
            [self updateIconAnimations];
        }];
        if ([_bezelStackHolder.subviews count]) {
            // pull the view onto the visible stack
            MMPaperView* pageToPushToVisible = [_bezelStackHolder.subviews objectAtIndex:0];
            [self willChangeTopPageTo:pageToPushToVisible];
            [pageToPushToVisible removeAllAnimationsAndPreservePresentationFrame];
            [_visibleStackHolder pushSubview:pageToPushToVisible];
            [self animatePageToFullScreen:pageToPushToVisible withDelay:0 withBounce:NO onComplete:^(BOOL finished) {
                [self didChangeTopPage];
            }];
            [_bezelStackHolder.subviews makeObjectsPerformSelector:@selector(removeAllAnimationsAndPreservePresentationFrame)];
            [self emptyBezelStackToHiddenStackAnimated:YES onComplete:nil];
        } else {
            // the pop method will notify us about the change
            // in top page, so we won't do it here.
            [self popTopPageOfHiddenStack];
        }
    } else {
        // bounce it back to full screen
        [_bezelStackHolder.subviews makeObjectsPerformSelector:@selector(removeAllAnimationsAndPreservePresentationFrame)];
        [self emptyBezelStackToHiddenStackAnimated:YES onComplete:nil];
        BOOL shouldBounce = ABS(page.scale - 1) > kBounceThreshhold;
        [self animatePageToFullScreen:page withDelay:0 withBounce:shouldBounce onComplete:nil];
    }
}

- (void)animateAdditionalPageIntoVisibleStackFromLeft {
    // this would make the visible stack empty, so add an additional page below this one and animate in from the left
    MMPaperView* addedPage;
    if ([_visibleStackHolder peekSubview]) {
        [self ensureAtLeast:2 pagesInStack:_visibleStackHolder];
        addedPage = [_visibleStackHolder getPageBelow:[_visibleStackHolder peekSubview]];
    } else {
        [self ensureAtLeast:1 pagesInStack:_visibleStackHolder];
        addedPage = [_visibleStackHolder peekSubview];
    }

    addedPage.frame = CGRectTranslate([addedPage bounds], -CGRectGetWidth([addedPage bounds]) + 40, 0);

    [UIView animateWithDuration:.3 animations:^{
        addedPage.frame = addedPage.bounds;
    }];
}

- (void)ownershipOfTouches:(NSSet*)touches isGesture:(UIGestureRecognizer*)gesture {
    // noop
}

- (void)isBeginningToScaleReallySmall:(MMPaperView*)page {
    [self updateIconAnimations];
}

- (void)finishedScalingReallySmall:(MMPaperView*)page animated:(BOOL)animated {
    [self updateIconAnimations];
}

- (void)cancelledScalingReallySmall:(MMPaperView*)page {
    [self updateIconAnimations];
}

- (void)finishedScalingBackToPageView:(MMPaperView*)page {
    [self updateIconAnimations];
}

- (NSInteger)indexOfPageInCompleteStack:(MMPaperView*)page {
    @throw kAbstractMethodException;
}

- (NSInteger)rowInListViewGivenIndex:(NSInteger)indexOfPage {
    @throw kAbstractMethodException;
}

- (NSInteger)columnInListViewGivenIndex:(NSInteger)indexOfPage {
    @throw kAbstractMethodException;
}

- (BOOL)isInVisibleStack:(MMPaperView*)page {
    @throw kAbstractMethodException;
}

- (void)didSavePage:(MMPaperView*)page {
    @throw kAbstractMethodException;
}

- (BOOL)isPageEditable:(MMPaperView*)page {
    @throw kAbstractMethodException;
}

- (MMScrapsInBezelContainerView*)bezelContainerView {
    @throw kAbstractMethodException;
}

- (void)didExportPage:(MMPaperView*)page toZipLocation:(NSString*)fileLocationOnDisk {
    @throw kAbstractMethodException;
}

- (void)didFailToExportPage:(MMPaperView*)page {
    @throw kAbstractMethodException;
}

- (void)isExportingPage:(MMPaperView*)page withPercentage:(CGFloat)percentComplete toZipLocation:(NSString*)fileLocationOnDisk {
    @throw kAbstractMethodException;
}

#pragma mark - Page Animation and Navigation Helpers

/**
 * returns YES if the page should slide
 * to the target frame as if it had inertia
 *
 * returns NO if the page should just bounce
 * instead
 */
- (BOOL)shouldInterialSlideThePage:(MMPaperView*)page toFrame:(CGRect)frame {
    if (frame.origin.y <= 0 && frame.origin.y + frame.size.height > self.superview.frame.size.height &&
        frame.origin.x <= 0 && frame.origin.x + frame.size.width > self.superview.frame.size.width) {
        return YES;
    }
    return NO;
}

/**
 * returns YES if a page should trigger removing
 * a page from the visible stack to the hidden stack.
 *
 * this is used when a user drags a page to the left/right
 */
- (BOOL)shouldPopPageFromVisibleStack:(MMPaperView*)page withFrame:(CGRect)frame {
    return frame.origin.x > self.frame.size.width - kGutterWidthToDragPages;
}

/**
 * returns YES if a page should trigger adding
 * a page to the visible stack from the hidden stack.
 *
 * this is used when a user drags a page to the left/right
 */
- (BOOL)shouldPushPageOntoVisibleStack:(MMPaperView*)page withFrame:(CGRect)frame {
    return frame.origin.x + frame.size.width < kGutterWidthToDragPages;
}

/**
 * this will realign all the pages except the input page
 * to be scale 1 and (0,0) in the visibleStackHolder
 */
- (void)realignPagesInVisibleStackExcept:(MMPaperView*)page animated:(BOOL)animated {
    for (MMPaperView* aPage in [_visibleStackHolder.subviews copy]) {
        if (aPage != page) {
            if (!CGRectEqualToRect(aPage.frame, self.bounds)) {
                [aPage cancelAllGestures];
                if (animated) {
                    [self animatePageToFullScreen:aPage withDelay:0 withBounce:NO onComplete:nil];
                } else {
                    aPage.frame = self.bounds;
                }
            }
        }
    }
}


#pragma mark - Page Animations

/**
 * immediately animates the page from the visible stack
 * to the hidden stack
 */
- (void)sendPageToHiddenStack:(MMPaperView*)page onComplete:(void (^)(BOOL finished))completionBlock {
    if ([_visibleStackHolder.subviews containsObject:page]) {
        [page removeAllAnimationsAndPreservePresentationFrame];
        [_bezelStackHolder addSubviewToBottomOfStack:page];
        [self emptyBezelStackToHiddenStackAnimated:YES onComplete:completionBlock];
        [self ensureAtLeast:1 pagesInStack:_visibleStackHolder];
    }
}

/**
 * will pop just the top of the hidden stack
 * onto the visible stack.
 *
 * if a page does not exist, it will create one
 * so that it has something to pop.
 */
- (void)popTopPageOfHiddenStack {
    [self ensureAtLeast:1 pagesInStack:_hiddenStackHolder];
    MMPaperView* page = [_hiddenStackHolder peekSubview];
    [self willChangeTopPageTo:page];
    page.isBrandNewPage = NO;
    [self popHiddenStackUntilPage:[_hiddenStackHolder getPageBelow:page] onComplete:^(BOOL finished) {
        [self didChangeTopPage];
    }];
}

/**
 * the input is a page in the visible stack,
 * and we pop all pages above but not including
 * the input page
 *
 * these pages will be pushed over to the invisible stack
 */
- (void)popStackUntilPage:(MMPaperView*)page onComplete:(void (^)(BOOL finished))completionBlock {
    if (page == nil) {
        DebugLog(@"what9");
        @throw [NSException exceptionWithName:@"popping to nil page" reason:@"unknown" userInfo:nil];
    }
    if ([_visibleStackHolder.subviews containsObject:page] || page == nil) {
        // list of pages from bottom to top
        NSArray* pages = [_visibleStackHolder peekSubviewFromSubview:page];
        // enumerage backwards, so top pages stay on top,
        // and all are below anything already in the bezelStackHolder
        for (MMPaperView* pageToPop in [pages reverseObjectEnumerator]) {
            [pageToPop removeAllAnimationsAndPreservePresentationFrame];
            [_bezelStackHolder addSubviewToBottomOfStack:pageToPop];
        }
        [self emptyBezelStackToHiddenStackAnimated:YES onComplete:completionBlock];
        [self ensureAtLeast:1 pagesInStack:_visibleStackHolder];
    }
}

/**
 * the input is a page in the visible stack,
 * and we pop all pages above but not including
 * the input page
 *
 * these pages will be pushed over to the invisible stack
 */
- (void)popHiddenStackUntilPage:(MMPaperView*)page onComplete:(void (^)(BOOL finished))completionBlock {
    if ([_hiddenStackHolder.subviews containsObject:page] || page == nil) {
        CGFloat delay = 0;
        while ([_hiddenStackHolder peekSubview] != page && [_hiddenStackHolder.subviews count]) {
            //
            // since we're manually popping the stack outside of an
            // animation, we need to make sure the page still exists
            // inside a stack.
            //
            // when the animation completes, it'll validate which stack
            // it's in anyways
            MMPaperView* aPage = [_hiddenStackHolder peekSubview];
            aPage.isBrandNewPage = NO;
            //
            // this push will also pop it off the visible stack, and adjust the frame
            // correctly
            [aPage enableAllGestures];
            [_visibleStackHolder pushSubview:aPage];
            BOOL hasAnotherToPop = [_hiddenStackHolder peekSubview] != page && [_hiddenStackHolder.subviews count];
            [self animatePageToFullScreen:aPage withDelay:delay withBounce:YES onComplete:(!hasAnotherToPop ? completionBlock : nil)];
            delay += kAnimationDelay;
        }
    }
}
/**
 * pop numberOfPages off of the hidden stack
 * and call the completionBlock once they're all
 * animated
 */
- (void)popHiddenStackForPages:(NSInteger)numberOfPages onComplete:(void (^)(BOOL finished))completionBlock {
    [self ensureAtLeast:numberOfPages pagesInStack:_hiddenStackHolder];
    NSInteger index = [_hiddenStackHolder.subviews count] - 1 - numberOfPages;
    if (index >= 0) {
        [self popHiddenStackUntilPage:[_hiddenStackHolder.subviews objectAtIndex:index] onComplete:completionBlock];
    } else {
        // pop entire stack
        [self popHiddenStackUntilPage:nil onComplete:completionBlock];
    }
}

/**
 * this function is used when the user flicks a page
 * and its momentum will carry the page to the edge of
 * the screen.
 *
 * in this case, we want to animate the page to the edge
 * then bounce it like a scrollview would
 */
- (void)bouncePageToEdge:(MMPaperView*)page toFrame:(CGRect)toFrame intertialFrame:(CGRect)inertialFrame {
    //
    //
    // first, check to see if the frame is already out of bounds
    // the toFrame represents where the paper is pre-inertia, so if
    // the toFrame is wrong, then just animate it back to an edge straight away
    if (toFrame.origin.x > 0 || toFrame.origin.y > 0 || toFrame.origin.x + toFrame.size.width < self.superview.frame.size.width || toFrame.origin.y + toFrame.size.height < self.superview.frame.size.height) {
        CGRect newInertialFrame = inertialFrame;
        if (inertialFrame.origin.x > 0) {
            newInertialFrame.origin.x = 0;
        }
        if (inertialFrame.origin.y > 0) {
            newInertialFrame.origin.y = 0;
        }
        if (inertialFrame.origin.x + inertialFrame.size.width < self.superview.frame.size.width) {
            newInertialFrame.origin.x = self.superview.frame.size.width - toFrame.size.width;
        }
        if (inertialFrame.origin.y + inertialFrame.size.height < self.superview.frame.size.height) {
            newInertialFrame.origin.y = self.superview.frame.size.height - toFrame.size.height;
        }
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut animations:^(void) {
            page.frame = newInertialFrame;
        } completion:nil];
        return;
    }

    //
    // ok, the paper is currently in the correct view, but the inertia
    // will carry it to an invalid location. for this, lets get the inertia
    // to carry it a 10px difference, then bounce it back to the edige
    CGRect newInertiaFrame = inertialFrame;
    CGRect postInertialFrame = inertialFrame;
    if (inertialFrame.origin.x > 10) {
        postInertialFrame.origin.x = 0;
        newInertiaFrame.origin.x = 10;
    }
    if (inertialFrame.origin.y > 10) {
        postInertialFrame.origin.y = 0;
        newInertiaFrame.origin.y = 10;
    }
    if (inertialFrame.origin.x + inertialFrame.size.width < self.superview.frame.size.width - 10) {
        postInertialFrame.origin.x = self.superview.frame.size.width - toFrame.size.width;
        newInertiaFrame.origin.x = postInertialFrame.origin.x - 10;
    }
    if (inertialFrame.origin.y + inertialFrame.size.height < self.superview.frame.size.height - 10) {
        postInertialFrame.origin.y = self.superview.frame.size.height - toFrame.size.height;
        newInertiaFrame.origin.y = postInertialFrame.origin.y - 10;
    }
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut animations:^(void) {
        page.frame = newInertiaFrame;
    } completion:^(BOOL finished) {
        if (finished && !CGRectEqualToRect(newInertiaFrame, postInertialFrame)) {
            [UIView animateWithDuration:0.1 delay:0 options:UIViewAnimationOptionAllowUserInteraction
                             animations:^(void) {
                                 page.frame = postInertialFrame;
                             }
                             completion:nil];
        }
    }];
}


/**
 * this animation will zoom the page back to scale of 1 and match it
 * perfect to the screensize.
 *
 * it'll also add a small bounce to the animation for effect
 *
 * this animation is interruptable
 */
- (void)animatePageToFullScreen:(MMPaperView*)page withDelay:(CGFloat)delay withBounce:(BOOL)bounce onComplete:(void (^)(BOOL finished))completionBlock {
    void (^finishedBlock)(BOOL finished) = ^(BOOL finished) {
        if (finished) {
            [page enableAllGestures];
            if (![_visibleStackHolder containsSubview:page]) {
                [_visibleStackHolder pushSubview:page];
            }
        }
        if (completionBlock)
            completionBlock(finished);
    };

    [page enableAllGestures];
    if (bounce) {
        CGFloat duration = .3;
        CGFloat bounceHeight = 10;
        if (page.scale > 1) {
            // this will cause it to bounce in
            // the correct direction of the scale
            bounceHeight = -5;
        }
        //
        // we also need to animate the shadow so that it doesn't "pop"
        // into place. it's not taken care of automatically in the
        // UIView animationWithDuration call...
        CABasicAnimation* theAnimation = [CABasicAnimation animationWithKeyPath:@"shadowPath"];
        theAnimation.duration = duration / 2;
        theAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        theAnimation.fromValue = (id)page.contentView.layer.shadowPath;
        theAnimation.toValue = (id)[[MMShadowManager sharedInstance] getShadowForSize:[MMShadowedView expandBounds:self.bounds].size];
        [page.contentView.layer addAnimation:theAnimation forKey:@"animateShadowPath"];
        [UIView animateWithDuration:duration / 2 delay:delay options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
            animations:^(void) {
                page.scale = 1;
                CGRect bounceFrame = self.bounds;
                bounceFrame.origin.x = bounceFrame.origin.x - bounceHeight;
                bounceFrame.origin.y = bounceFrame.origin.y - bounceHeight;
                bounceFrame.size.width = bounceFrame.size.width + bounceHeight * 2;
                bounceFrame.size.height = bounceFrame.size.height + bounceHeight * 2;
                page.frame = bounceFrame;
            }
            completion:^(BOOL finished) {
                if (finished) {
                    //
                    // ok, here the page is bounced too large for the screen, so
                    // complete the bounce and put the zoom at 100% exactly.
                    // first the shadow, then the frame
                    CABasicAnimation* theAnimation = [CABasicAnimation animationWithKeyPath:@"shadowPath"];
                    theAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
                    theAnimation.duration = duration / 2;
                    theAnimation.fromValue = (id)page.contentView.layer.shadowPath;
                    theAnimation.toValue = (id)[[MMShadowManager sharedInstance] getShadowForSize:self.bounds.size];
                    [page.contentView.layer addAnimation:theAnimation forKey:@"animateShadowPath"];
                    [UIView animateWithDuration:duration / 2 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseIn
                                     animations:^(void) {
                                         page.frame = self.bounds;
                                         page.scale = 1;
                                     }
                                     completion:finishedBlock];
                }
            }];
    } else {
        CGFloat duration = .15;
        [[NSThread mainThread] performBlock:^{
            //
            // always animate the shadow and the frame
            CABasicAnimation* theAnimation = [CABasicAnimation animationWithKeyPath:@"shadowPath"];
            theAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            theAnimation.duration = duration;
            theAnimation.fromValue = (id)page.contentView.layer.shadowPath;
            theAnimation.toValue = (id)[[MMShadowManager sharedInstance] getShadowForSize:self.bounds.size];
            [page.contentView.layer addAnimation:theAnimation forKey:@"animateShadowPath"];
            [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                             animations:^(void) {
                                 page.frame = self.bounds;
                                 page.scale = 1;
                             }
                             completion:finishedBlock];
        } afterDelay:delay];
    }
}


/**
 * this will animate a page onto the hidden stack
 * after the input delay, if any
 *
 * if the page is already offscreen, then it won't
 * animate
 */
- (void)animateBackToHiddenStack:(MMPaperView*)page withDelay:(CGFloat)delay onComplete:(void (^)(BOOL finished))completionBlock {
    //
    // the page may be sent to the hidden stack from ~90px away vs ~760px away
    // this math makes the speed of the exit look more consistent
    CGRect frInVisibleStack = [_visibleStackHolder convertRect:page.frame fromView:page.superview];
    if (frInVisibleStack.origin.x >= _visibleStackHolder.frame.size.width) {
        // it's invisible already, just push it on
        page.frame = _hiddenStackHolder.bounds;
        page.scale = 1;
        [page disableAllGestures];
        [_hiddenStackHolder pushSubview:page];
        if (completionBlock)
            completionBlock(YES);
    } else {
        // the time spent on the animation should depend on how far away the page is from its final position.
        // if the page is very very close to the hidden stack, then the distance will be short so the duration will be tiny.
        // if the page is far away from the hidden stack, the animation duration will be closer to 0.2
        CGFloat dist = MAX((_visibleStackHolder.frame.size.width - frInVisibleStack.origin.x), _visibleStackHolder.frame.size.width / 2);
        [UIView animateWithDuration:0.2 * (dist / _visibleStackHolder.frame.size.width) delay:delay options:UIViewAnimationOptionCurveEaseOut
            animations:^(void) {
                CGRect toFrame = [page.superview convertRect:_hiddenStackHolder.bounds fromView:_hiddenStackHolder];
                page.frame = toFrame;
                page.scale = 1;
            }
            completion:^(BOOL finished) {
                if (finished) {
                    [page disableAllGestures];
                    [_hiddenStackHolder pushSubview:page];
                }
                if (completionBlock)
                    completionBlock(finished);
            }];
    }
}


#pragma mark - Page Loading and Unloading

/**
 * this page is in the visible stack, and might be
 * unloaded soon. so we may want to start generating
 * the cached image of the page, and writing the memcache
 * to disk
 */
- (void)mayChangeTopPageTo:(MMPaperView*)page {
    [[MMPageCacheManager sharedInstance] mayChangeTopPageTo:page];
}

/**
 * this page is definitely getting kicked out of cache,
 * so finish writing it all to disk and free up
 * any OpenGL / graphics memory for other pages.
 * get this into static mode asap.
 */
- (void)willChangeTopPageTo:(MMPaperView*)page {
    [[MMPageCacheManager sharedInstance] willChangeTopPageTo:page];
}

// convenience method
- (void)didChangeTopPage {
    [self didChangeTopPageTo:[_visibleStackHolder peekSubview]];
}

- (void)didChangeTopPageTo:(MMPaperView*)topPage {
    if ([[MMPageCacheManager sharedInstance] didChangeToTopPage:topPage]) {
        [self saveStacksToDisk];
    }
}

/**
 * this page is definitely getting kicked out of cache,
 * so finish writing it all to disk and free up
 * any OpenGL / graphics memory for other pages.
 * get this into static mode asap.
 */
- (void)willNotChangeTopPageTo:(MMPaperView*)page {
    [[MMPageCacheManager sharedInstance] willNotChangeTopPageTo:page];
}

- (void)saveStacksToDisk {
    @throw kAbstractMethodException;
}

#pragma mark - JotViewDelegate
- (BOOL)willBeginStrokeWithCoalescedTouch:(UITouch*)coalescedTouch fromTouch:(UITouch*)touch inJotView:(JotView*)jotView {
    @throw kAbstractMethodException;
}

- (void)willMoveStrokeWithCoalescedTouch:(UITouch*)coalescedTouch fromTouch:(UITouch*)touch inJotView:(JotView*)jotView {
    @throw kAbstractMethodException;
}

- (void)willEndStrokeWithCoalescedTouch:(UITouch*)coalescedTouch fromTouch:(UITouch*)touch shortStrokeEnding:(BOOL)shortStrokeEnding inJotView:(JotView*)jotView {
    @throw kAbstractMethodException;
}

- (void)didEndStrokeWithCoalescedTouch:(UITouch*)coalescedTouch fromTouch:(UITouch*)touch inJotView:(JotView*)jotView {
    @throw kAbstractMethodException;
}

- (void)willCancelStroke:(JotStroke*)stroke withCoalescedTouch:(UITouch*)coalescedTouch fromTouch:(UITouch*)touch inJotView:(JotView*)jotView {
    @throw kAbstractMethodException;
}

- (void)didCancelStroke:(JotStroke*)stroke withCoalescedTouch:(UITouch*)coalescedTouch fromTouch:(UITouch*)touch inJotView:(JotView*)jotView {
    @throw kAbstractMethodException;
}

- (JotBrushTexture*)textureForStroke {
    @throw kAbstractMethodException;
}

- (CGFloat)stepWidthForStroke {
    @throw kAbstractMethodException;
}

- (BOOL)supportsRotation {
    @throw kAbstractMethodException;
}

- (UIColor*)colorForCoalescedTouch:(UITouch*)coalescedTouch fromTouch:(UITouch*)touch {
    @throw kAbstractMethodException;
}

- (CGFloat)widthForCoalescedTouch:(UITouch*)coalescedTouch fromTouch:(UITouch*)touch {
    @throw kAbstractMethodException;
}

- (CGFloat)smoothnessForCoalescedTouch:(UITouch*)coalescedTouch fromTouch:(UITouch*)touch {
    @throw kAbstractMethodException;
}

- (CGFloat)rotationForSegment:(AbstractBezierPathElement*)segment fromPreviousSegment:(AbstractBezierPathElement*)previousSegment {
    @throw kAbstractMethodException;
}

- (NSArray*)willAddElements:(NSArray*)elements toStroke:(JotStroke*)stroke fromPreviousElement:(AbstractBezierPathElement*)previousElement {
    @throw kAbstractMethodException;
}

#pragma mark - Check for Active Gestures

- (BOOL)isActivelyGesturing {
    return [_fromLeftBezelGesture isActivelyBezeling] || [_fromRightBezelGesture isActivelyBezeling] || [_setOfPagesBeingPanned count];
}

- (void)disableAllGesturesForPageView {
    [_fromLeftBezelGesture setEnabled:NO];
    [_fromRightBezelGesture setEnabled:NO];
}

- (void)enableAllGesturesForPageView {
    [_fromLeftBezelGesture setEnabled:YES];
    [_fromRightBezelGesture setEnabled:YES];
}

@end
