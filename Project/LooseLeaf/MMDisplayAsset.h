//
//  MMDisplayAsset.h
//  LooseLeaf
//
//  Created by Adam Wulf on 3/5/15.
//  Copyright (c) 2015 Milestone Made, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol MMDisplayAssetCoordinator

- (CGSize)visibleImageSize;

- (CGPoint)visibleImageOrigin;

- (void)setPreferredAspectRatioForEmptyImage:(CGSize)size;


@end


@interface MMDisplayAsset : NSObject

- (UIImage*)aspectRatioThumbnail;

- (UIImage*)aspectThumbnailWithMaxPixelSize:(int)maxDim;

- (UIImage*)aspectThumbnailWithMaxPixelSize:(int)maxDim andRatio:(CGFloat)ratio;

- (NSURL*)fullResolutionURL;

- (CGSize)resolutionSizeWithMaxDim:(NSInteger)maxDim;

- (CGSize)fullResolutionSize;

- (CGFloat)defaultRotation;

- (CGFloat)preferredImportMaxDim;

- (UIBezierPath*)fullResolutionPath;

@end
