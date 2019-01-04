//
//  MMClonePaperStackView.m
//  LooseLeaf
//
//  Created by Adam Wulf on 9/26/16.
//  Copyright © 2016 Milestone Made, LLC. All rights reserved.
//

#import "MMClonePaperStackView.h"
#import "NSURL+UTI.h"
#import "MMPageCloner.h"
#import "Mixpanel.h"


@interface MMListPaperStackView (Protected)

- (void)realignPagesInListView:(NSSet*)pagesToMove animated:(BOOL)animated forceRecalculateAll:(BOOL)recalculateAll;

@end


@implementation MMClonePaperStackView {
    MMPageCloner* pageCloner;
}

#pragma mark - MMStretchPageGestureRecognizerDelegate

- (void)didPickUpAPageInListView:(MMLongPressFromListViewGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateFailed ||
               gesture.state == UIGestureRecognizerStateCancelled) {
        [pageCloner abortClone];
        pageCloner = nil;
    }

    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateFailed ||
        gesture.state == UIGestureRecognizerStateCancelled) {
        if (gesture.pinchedPage.center.x > CGRectGetWidth([self bounds]) - kBezelInGestureWidth) {
            // properties for drag behavior
            realizedThatPageIsBeingDragged = NO;
            pageBeingDragged = nil;
            // go to page/list view
            // based on how the gesture ended
            [self setScrollEnabled:YES];
            [self.stackDelegate.bezelPagesContainer addViewToCountableSidebar:(MMEditablePaperView*)gesture.pinchedPage animated:YES];
            [self realignPagesInListView:[NSSet setWithArray:[self findPagesInVisibleRowsOfListView]] animated:YES forceRecalculateAll:YES];
            [self finishUITransitionToListView];
            return;
        }
    }

    [super didPickUpAPageInListView:gesture];
}

- (void)didCancelStretchToDuplicatePageWithGesture:(MMStretchPageGestureRecognizer*)gesture {
    [pageCloner abortClone];
    pageCloner = nil;
}

- (void)didBeginStretchToDuplicatePageWithGesture:(MMStretchPageGestureRecognizer*)gesture {
    pageCloner = [[MMPageCloner alloc] initWithOriginalUUID:[gesture.pinchedPage uuid] clonedUUID:[[NSUUID UUID] UUIDString] inStackUUID:[self uuid]];
    [pageCloner beginClone];
}

- (void)didStretchToDuplicatePageWithGesture:(MMStretchPageGestureRecognizer*)gesture withOffset:(CGPoint)offset {
    CGRect targetFrame = gesture.pinchedPage.bounds;
    targetFrame.origin = gesture.pinchedPage.frame.origin;
    targetFrame.origin.x += offset.x - CGRectGetWidth(targetFrame) / 2;
    targetFrame.origin.y += offset.y;
    BOOL shouldSubOne = targetFrame.origin.x < 0;
    targetFrame.origin.x = MIN(MAX(0, targetFrame.origin.x), CGRectGetWidth([self bounds]));

    CGPoint targetPoint = CGRectGetMidPoint(targetFrame);

    NSInteger row = (targetPoint.y) / ([MMListPaperStackView rowHeight] + [MMListPaperStackView bufferWidth]);
    NSInteger col = targetPoint.x / (([MMListPaperStackView columnWidth] + [MMListPaperStackView bufferWidth]) + [MMListPaperStackView bufferWidth] / kNumberOfColumnsInListView);
    NSInteger index = row * kNumberOfColumnsInListView + col - shouldSubOne;
    if (col == kNumberOfColumnsInListView - 1) {
        index -= 1;
    }
    CGRect targetPageFrame = [self frameForIndexInList:index];

    [pageCloner finishCloneAndThen:^(NSString* clonedUUID) {
        CheckMainThread;

        MMExportablePaperView* page = [[MMExportablePaperView alloc] initWithFrame:self.bounds andUUID:clonedUUID];
        page.delegate = self;
        // this like will ensure the new page slides in with
        // its preview properly loaded in time.
        [page loadCachedPreviewAndDecompressImmediately:YES];

        page.frame = targetFrame;

        MMPaperView* pageToInsertAfter = [self pageForPointInList:CGRectGetMidPoint(targetPageFrame)];

        if (!pageToInsertAfter) {
            pageToInsertAfter = gesture.pinchedPage;
        }

        if ([self.visibleStackHolder containsSubview:pageToInsertAfter]) {
            [self.visibleStackHolder insertPage:page abovePage:pageToInsertAfter];
        } else if ([self.hiddenStackHolder containsSubview:pageToInsertAfter]) {
            [self.hiddenStackHolder insertPage:page abovePage:pageToInsertAfter];
        }

        [[Mixpanel sharedInstance] track:kMPEventClonePage];
        [[[Mixpanel sharedInstance] people] increment:kMPNumberOfPages by:@(1)];
        [[[Mixpanel sharedInstance] people] set:@{ kMPHasAddedPage: @(YES) }];

        NSMutableArray* pagesToMove = [[self findPagesInVisibleRowsOfListView] mutableCopy];
        [pagesToMove removeObject:gesture.pinchedPage];

        [self realignPagesInListView:[NSSet setWithArray:pagesToMove] animated:YES forceRecalculateAll:YES];

        [self saveStacksToDisk];

        pageCloner = nil;
    }];
}

@end
