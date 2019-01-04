//
//  MMListSidebarStackView.m
//  LooseLeaf
//
//  Created by Adam Wulf on 10/18/16.
//  Copyright © 2016 Milestone Made, LLC. All rights reserved.
//

#import "MMListSidebarStackView.h"
#import "NSArray+Extras.h"
#import "UIScreen+MMSizing.h"


@interface MMListPaperStackView (Protected)

- (void)realignPagesInListView:(NSSet*)pagesToMove animated:(BOOL)animated forceRecalculateAll:(BOOL)recalculateAll;

- (void)ensurePageIsAtTopOfVisibleStack:(MMPaperView*)aPage;

- (CGRect)frameForListViewForPage:(MMPaperView*)page;

- (CGRect)frameForAddPageButton;

@end


@implementation MMListSidebarStackView

// This affects how much the pages are squished together
- (CGFloat)pageSidebarWidth {
    if ([UIScreen screenWidth] > 768) {
        return roundf([UIScreen screenWidth] * 1.18 / 10.0);
    }

    return roundf([UIScreen screenWidth] * 1.17 / 10.0);
}

// This affects how far the pages are offset to the left
- (CGFloat)pageSidebarOffset {
    if ([UIScreen screenWidth] > 768) {
        // ipad pro 12in
        return 4;
    }

    return 1;
}

- (void)immediatelyRelayoutIfInListMode {
    if (!self.isShowingPageView) {
        NSArray* allPages = [[self.visibleStackHolder subviews] arrayByAddingObjectsFromArray:[self.hiddenStackHolder subviews]];
        [self realignPagesInListView:[NSSet setWithArray:allPages] animated:NO forceRecalculateAll:YES];
    }
}

- (CGRect)frameForListViewForPage:(MMPaperView*)page {
    CGRect fr = [super frameForListViewForPage:page];

    if ([[self.stackDelegate.bezelPagesContainer viewsInSidebar] count]) {
        CGFloat maxMove = [self pageSidebarWidth];
        CGFloat maxX = CGRectGetWidth([self.stackDelegate.bezelPagesContainer bounds]);
        CGFloat movement = (fr.origin.x) / maxX * maxMove + kWidthOfSidebarButtonBuffer + [self pageSidebarOffset];
        fr.origin.x -= movement;
    }

    return fr;
}

- (CGRect)frameForAddPageButton {
    CGRect fr = [super frameForAddPageButton];

    if ([[self.stackDelegate.bezelPagesContainer viewsInSidebar] count]) {
        CGFloat maxMove = [self pageSidebarWidth];
        CGFloat maxX = CGRectGetWidth([self.stackDelegate.bezelPagesContainer bounds]);
        CGFloat movement = (fr.origin.x) / maxX * maxMove + kWidthOfSidebarButtonBuffer + [self pageSidebarOffset];
        fr.origin.x -= movement;
    }

    return fr;
}

- (CGPoint)addPageBackToListViewAndAnimateOtherPages:(MMPaperView*)page {
    // oddly, self.bounds.origin.y is the contentOffset. I'm not using that fact here because
    // it's not immediately clear when reading this, but something to be aware of when looking.
    CGPoint locInSelf = CGPointMake(CGRectGetMaxX(self.bounds), CGRectGetHeight(self.bounds) / 2 + self.contentOffset.y);

    id<MMPaperViewDelegate> previousStack = page.delegate;

    NSArray* currentlyVisiblePages = [self findPagesInVisibleRowsOfListView];
    MMPaperView* nearbyPage = [self findPageClosestToOffset:locInSelf];

    if (nearbyPage) {
        [self ensurePageIsAtTopOfVisibleStack:nearbyPage];
        [self addPage:page belowPage:nearbyPage];
        [page disableAllGestures];
    } else {
        [self.hiddenStackHolder addSubviewToBottomOfStack:page];
    }
    // need to set the delegate, otherwise it's only reset in the nearbyPage case above.
    // this delegate also determines the stack UUID for the page's paths
    page.delegate = self;

    [(MMExportablePaperView*)page moveAssetsFrom:previousStack];

    currentlyVisiblePages = [currentlyVisiblePages arrayByAddingObject:page];

    // animate pages into their new location
    [self realignPagesInListView:[NSSet setWithArray:currentlyVisiblePages] animated:YES forceRecalculateAll:YES];

    // immediately move non-visible pages to their new location
    NSMutableSet* allOtherPages = [NSMutableSet setWithArray:self.visibleStackHolder.subviews];
    [allOtherPages addObjectsFromArray:self.hiddenStackHolder.subviews];
    [allOtherPages removeObjectsInArray:currentlyVisiblePages];
    [allOtherPages removeObject:page];
    [self realignPagesInListView:allOtherPages animated:NO forceRecalculateAll:NO];

    return [super addPageBackToListViewAndAnimateOtherPages:page];
}

- (MMPaperView*)findPageClosestToOffset:(CGPoint)offsetOfListView {
    //
    // scrolling is enabled, so we need to return
    // the list of pages that are currently visible

    NSArray* arraysOfSubviews[2];
    arraysOfSubviews[0] = self.visibleStackHolder.subviews;
    arraysOfSubviews[1] = self.hiddenStackHolder.subviews;
    int countOfSubviews[2]; // can't be NSUInteger, or -1 < count will be false
    countOfSubviews[0] = (int)[self.visibleStackHolder.subviews count];
    countOfSubviews[1] = (int)[self.hiddenStackHolder.subviews count];

    NSArray* allPages = [self.visibleStackHolder.subviews arrayByAddingObjectsFromArray:[self.hiddenStackHolder.subviews reversedArray]];

    NSInteger startRow = floor(offsetOfListView.y) / ([MMListPaperStackView bufferWidth] + [MMListPaperStackView rowHeight]);
    NSInteger startCol = floor(offsetOfListView.x) / ([MMListPaperStackView bufferWidth] + [MMListPaperStackView columnWidth]);
    NSInteger startIndex = startRow * kNumberOfColumnsInListView + startCol;

    NSInteger endIndex = startIndex + kNumberOfColumnsInListView;
    startIndex -= kNumberOfColumnsInListView;
    endIndex = MIN([allPages count] - 1, endIndex);

    if (startIndex >= 0 && endIndex < [allPages count] && startIndex <= endIndex) {
        NSArray* closePages = [allPages subarrayWithRange:NSMakeRange(startIndex, endIndex - startIndex + 1)];
        return [closePages jotReduce:^id(id obj, NSUInteger index, MMPaperView* accum) {
            CGRect fr1 = [self frameForListViewForPage:obj];
            CGRect fr2 = [self frameForListViewForPage:accum];
            CGFloat d1 = DistanceBetweenTwoPoints(offsetOfListView, CGRectGetMidPoint(fr1));
            CGFloat d2 = DistanceBetweenTwoPoints(offsetOfListView, CGRectGetMidPoint(fr2));
            if (!accum || d1 < d2) {
                return obj;
            } else {
                return accum;
            }
        }];
    }
    return nil;
}


@end
