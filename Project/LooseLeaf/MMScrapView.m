//
//  MMScrap.m
//  LooseLeaf
//
//  Created by Adam Wulf on 8/23/13.
//  Copyright (c) 2013 Milestone Made, LLC. All rights reserved.
//

#import "MMScrapView.h"
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import "MMRotationManager.h"
#import "UIColor+Shadow.h"
#import "MMDebugDrawView.h"
#import "NSString+UUID.h"
#import "NSThread+BlockAdditions.h"
#import "MMScrapViewState.h"
#import "MMScrapBorderView.h"
#import "UIView+Debug.h"
#import "UIView+Animations.h"
#import <JotUI/AbstractBezierPathElement-Protected.h>
#import <JotUI/UIColor+JotHelper.h>
#import <PerformanceBezier/PerformanceBezier.h>
#import <ClippingBezier/ClippingBezier.h>


@implementation MMScrapView {
    // **
    // these properties will be saved by the page that holds us, if any:
    // our current scale
    CGFloat scale;
    // our current rotation around our center
    CGFloat rotation;

    // these properties are UI only, and
    // don't need to be persisted:
    //
    // boolean to say if the user is currently holding this scrap. used for blue border
    BOOL selected;
    // the layer used for our white background. won't clip sub-content
    CAShapeLayer* backgroundColorLayer;


    // these properties are calculated, and
    // don't need to be persisted

    // this will track whenever a property of the scrap has changed,
    // so that we can recalculate the path to use when clipping strokes
    // around/through this scrap
    BOOL needsClippingPathUpdate;

    UIBezierPath* clippingPath;

    MMScrapViewState* scrapState;

    //
    // TODO: I think I need to have this
    // border view be ideally scaled to the list
    // size. possibly have a 2nd border view
    // that's ideally scaled to the page size?
    //
    // this way the border is crisp when scrolling
    // in list view
    MMScrapBorderView* borderView;

    UILabel* debugLabel;

    NSMutableArray* blocksToFireWhenStateIsLoaded;
}

@synthesize scale;
@synthesize rotation;
@synthesize selected;
@synthesize clippingPath;


/**
 * returns a new and loaded scrap with the specified path at the specified scale and rotation.
 */
- (id)initWithBezierPath:(UIBezierPath*)path andScale:(CGFloat)_scale andRotation:(CGFloat)_rotation andPaperState:(MMScrapCollectionState*)paperState {
    // copy the path, otherwise any changes made to it outside
    // of this class would also be applied to our state.
    UIBezierPath* originalPath = [path copy];
    CGPoint pathC = originalPath.center;

    CGAffineTransform scalePathToFullResTransform = CGAffineTransformMakeTranslation(pathC.x, pathC.y);
    scalePathToFullResTransform = CGAffineTransformScale(scalePathToFullResTransform, 1 / _scale, 1 / _scale);
    scalePathToFullResTransform = CGAffineTransformTranslate(scalePathToFullResTransform, -pathC.x, -pathC.y);
    [originalPath applyTransform:scalePathToFullResTransform];

    // one of our other [init] methods may have already created a state
    // for us, but if not, then go ahead and build one
    MMScrapViewState* _scrapState = [[MMScrapViewState alloc] initWithUUID:[NSString createStringUUID] andBezierPath:originalPath andPaperState:paperState];
    _scrapState.delegate = self;

    if (self = [self initWithScrapViewState:_scrapState]) {
        // when we create a scrap state, it adjusts the path to have its corner in (0,0), so
        // we need to set our center after we create the state
        self.center = pathC;
        [self loadScrapStateAsynchronously:NO];
        [self setScale:_scale];
        [self setRotation:_rotation];
    }
    return self;
}


- (id)initWithScrapViewState:(MMScrapViewState*)_scrapState {
    CheckMainThread;
    if ((self = [super initWithFrame:_scrapState.drawableBounds])) {
        scrapState = _scrapState;
        scrapState.delegate = self;
        blocksToFireWhenStateIsLoaded = [NSMutableArray array];
        self.center = scrapState.bezierPath.center;
        scale = 1;

        //
        // this is our white background
        backgroundColorLayer = [CAShapeLayer layer];
        [backgroundColorLayer setPath:scrapState.bezierPath.CGPath];
        backgroundColorLayer.fillColor = [UIColor whiteColor].CGColor;
        backgroundColorLayer.masksToBounds = YES;
        backgroundColorLayer.frame = self.layer.bounds;

        [self.layer addSublayer:backgroundColorLayer];


        // only the path contents are opaque, but outside the path needs to be transparent
        self.opaque = NO;
        // yes clip to bounds so we keep good performance
        self.clipsToBounds = YES;
        // update our shadow rotation
        [self didUpdateAccelerometerWithRawReading:[[MMRotationManager sharedInstance] currentRawRotationReading]];
        needsClippingPathUpdate = YES;

        //
        // the state content view will show a thumbnail while
        // the drawable view loads
        [self addSubview:scrapState.contentView];

        borderView = [[MMScrapBorderView alloc] initWithFrame:self.bounds];
        borderView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        [borderView setBezierPath:self.bezierPath];
        [self addSubview:borderView];
        borderView.hidden = YES;

        // now we need to show our shadow.
        // this is done just as we do with Shadowed view
        // our view clips to bounds, and our shadow is
        // displayed inside our bounds. this way we dont
        // need to do any offscreen rendering when displaying
        // this view
        [self setShouldShowShadow:NO];

#ifdef DEBUG
#ifdef DEBUGLABELS
#if DEBUGLABELS
        CALayer* cornerTag = [CALayer layer];
        cornerTag.bounds = CGRectMake(10, 10, 10, 10);
        cornerTag.backgroundColor = [UIColor redColor].CGColor;
        [self.layer addSublayer:cornerTag];


        debugLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 150, 20)];
        debugLabel.backgroundColor = [UIColor whiteColor];
        debugLabel.text = self.uuid;
        [self addSubview:debugLabel];
#endif
#endif
#endif
    }
    return self;
}


- (int)fullByteSize {
    return borderView.fullByteSize + scrapState.fullByteSize;
}

- (NSString*)uuid {
    return scrapState.uuid;
}

- (NSString*)owningPageUUID {
    return [scrapState.scrapsOnPaperState.delegate uuidOfScrapCollectionStateOwner];
}

- (MMScrapBackgroundView*)backgroundView {
    return scrapState.backgroundView;
}
- (void)setBackgroundView:(MMScrapBackgroundView*)backgroundView {
    scrapState.backgroundView = backgroundView;
}


/**
 * shadows cause lag during scrolling
 * 
 * i should unload shadows when the page isn't on the
 * top and when any page is in list view.
 */
- (void)setShouldShowShadow:(BOOL)shouldShowShadow {
    if (shouldShowShadow) {
        self.layer.shadowPath = scrapState.bezierPath.CGPath;
        [self setSelected:selected]; // reset shadow
        self.layer.shadowOpacity = .65;
        self.layer.shadowOffset = CGSizeMake(0, 0);
        borderView.hidden = YES;
    } else {
        self.layer.shadowPath = nil;
        borderView.hidden = NO;
    }
}

- (void)setSelected:(BOOL)_selected {
    selected = _selected;
    if (selected) {
        self.layer.shadowColor = [[UIColor blueShadowColor] colorWithAlphaComponent:1].CGColor;
        self.layer.shadowRadius = MAX(1, 2.5 / [self scale]);
    } else {
        self.layer.shadowRadius = MAX(1, 1.5 / [self scale]);
        self.layer.shadowColor = [[UIColor blackColor] colorWithAlphaComponent:.5].CGColor;
    }
}

- (void)setBackgroundColor:(UIColor*)backgroundColor {
    backgroundColorLayer.fillColor = backgroundColor.CGColor;
}

- (UIColor*)backgroundColor {
    if (backgroundColorLayer.fillColor) {
        return [UIColor colorWithCGColor:backgroundColorLayer.fillColor];
    }

    return [UIColor whiteColor];
}

/**
 * scraps will show the shadow move ever so slightly as the device is turned
 */
- (void)didUpdateAccelerometerWithRawReading:(MMVector*)currentRawReading {
    self.layer.shadowOffset = CGSizeMake(cosf(-[currentRawReading angle] - rotation) * 1, sinf(-[currentRawReading angle] - rotation) * 1);
}

#pragma mark - UITouch Helper methods

/**
 * these methods are used from inside of gestures to help
 * determine when touches begin/move/etc inide of a scrap
 */

- (BOOL)containsTouch:(UITouch*)touch {
    CGPoint locationOfTouch = [touch locationInView:self];
    return [scrapState.bezierPath containsPoint:locationOfTouch];
}

- (NSSet*)matchingPairTouchesFrom:(NSSet*)touches {
    NSSet* outArray = [self allMatchingTouchesFrom:touches];
    if ([outArray count] >= 2) {
        return outArray;
    }
    return nil;
}

- (NSSet*)allMatchingTouchesFrom:(NSSet*)touches {
    NSMutableSet* outArray = [NSMutableSet set];
    for (UITouch* touch in touches) {
        if ([self containsTouch:touch]) {
            [outArray addObject:touch];
        }
    }
    return outArray;
}

#pragma mark - Postion, Scale, Rotation

- (void)setScale:(CGFloat)_scale andRotation:(CGFloat)_rotation {
    scale = _scale;
    rotation = _rotation;
    needsClippingPathUpdate = YES;
    self.transform = CGAffineTransformConcat(CGAffineTransformMakeRotation(rotation), CGAffineTransformMakeScale(scale, scale));
    if (selected) {
        self.layer.shadowRadius = MAX(1, 2.5 / [self scale]);
    } else {
        self.layer.shadowRadius = MAX(1, 1.5 / [self scale]);
    }
}

- (void)setScale:(CGFloat)_scale {
    [self setScale:_scale andRotation:self.rotation];
}

- (void)setRotation:(CGFloat)_rotation {
    if (ABS(_rotation - rotation) > .3 && rotation != 0) {
        DebugLog(@"what: large rotation change");
    }
    [self setScale:self.scale andRotation:_rotation];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    needsClippingPathUpdate = YES;
}

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    needsClippingPathUpdate = YES;
}

- (void)setCenter:(CGPoint)center {
    [super setCenter:center];
    needsClippingPathUpdate = YES;
}

- (NSDictionary*)propertiesDictionary {
    CheckMainThread;

    // make sure we calculate all of our properties
    // with a neutral anchor point
    CGPoint currentAnchor = self.layer.anchorPoint;
    [UIView setAnchorPoint:CGPointMake(.5, .5) forView:self];
    NSMutableDictionary* properties = [NSMutableDictionary dictionary];
    [properties setObject:self.uuid forKey:@"uuid"];
    [properties setObject:[NSNumber numberWithFloat:self.center.x] forKey:@"center.x"];
    [properties setObject:[NSNumber numberWithFloat:self.center.y] forKey:@"center.y"];
    [properties setObject:[NSNumber numberWithFloat:self.rotation] forKey:@"rotation"];
    [properties setObject:[NSNumber numberWithFloat:self.scale] forKey:@"scale"];
    [properties setObject:[self.backgroundColor asDictionary] forKey:@"backgroundColor"];

    if (self.superview) {
        NSUInteger index = [self.superview.subviews indexOfObject:self];
        [properties setObject:[NSNumber numberWithUnsignedInteger:index] forKey:@"subviewIndex"];
    } else {
        // noop
    }
    [UIView setAnchorPoint:currentAnchor forView:self];
    return properties;
}

- (void)setPropertiesDictionary:(NSDictionary*)properties {
    // make sure we set all of our properties
    // with a neutral anchor point
    CGPoint currentAnchor = self.layer.anchorPoint;
    [UIView setAnchorPoint:CGPointMake(.5, .5) forView:self];
    self.center = CGPointMake([[properties objectForKey:@"center.x"] floatValue], [[properties objectForKey:@"center.y"] floatValue]);
    self.rotation = [[properties objectForKey:@"rotation"] floatValue];
    self.scale = [[properties objectForKey:@"scale"] floatValue];

    if (properties[@"backgroundColor"]) {
        self.backgroundColor = [UIColor colorWithDictionary:properties[@"backgroundColor"]];
    } else {
        self.backgroundColor = [UIColor whiteColor];
    }

    [UIView setAnchorPoint:currentAnchor forView:self];
}

#pragma mark - Clipping Path

/**
 * we'll cache our clipping path since it
 * takes a bit of processing power to
 * calculate.
 *
 * this will always return the correct clipping
 * path, and will recalculate and update our
 * cache if need be
 */
- (UIBezierPath*)clippingPath {
    if (needsClippingPathUpdate) {
        [self commitEditsAndUpdateClippingPath];
        needsClippingPathUpdate = NO;
    }
    return clippingPath;
}

/**
 * our clippingPath is in OpenGL coordinate space, just
 * as all of the CurveToPathElements that we use for
 * drawing. This will transform our CoreGraphics coordinated
 * bezierPath into OpenGL including our location, rotation,
 * and scale so that we can clip all of the CurveToPathElements
 * with this path to help determine which parts of the drawn
 * line should be added to this scrap.
 */
- (void)commitEditsAndUpdateClippingPath {
    // start with our original path
    clippingPath = [scrapState.bezierPath copy];

    [clippingPath applyTransform:self.clippingPathTransform];
}

- (CGAffineTransform)clippingPathTransform {
    // when we pick up a scrap with a two finger gesture, we also
    // change the position and anchor (which change the center), so
    // that it rotates underneath the gesture correctly.
    //
    // we need to re-caculate the true center of the scrap as if it
    // was not being held, so that we can position our path correctly
    // over it.
    CGPoint actualScrapCenter = CGPointMake(CGRectGetMidX(self.frame), CGRectGetMidY(self.frame));
    CGPoint clippingPathCenter = clippingPath.center;

    // first, align the center of the scrap to the center of the path
    CGAffineTransform reCenterTransform = CGAffineTransformMakeTranslation(actualScrapCenter.x - clippingPathCenter.x, actualScrapCenter.y - clippingPathCenter.y);
    clippingPathCenter = CGPointApplyAffineTransform(clippingPathCenter, reCenterTransform);

    // now we need to rotate the path around it's new center
    CGAffineTransform moveFromCenter = CGAffineTransformMakeTranslation(-clippingPathCenter.x, -clippingPathCenter.y);
    CGAffineTransform rotateAndScale = CGAffineTransformConcat(CGAffineTransformMakeRotation(self.rotation), CGAffineTransformMakeScale(self.scale, self.scale));
    CGAffineTransform moveToCenter = CGAffineTransformMakeTranslation(clippingPathCenter.x, clippingPathCenter.y);

    CGAffineTransform flipTransform = CGAffineTransformMake(1, 0, 0, -1, 0, self.superview.bounds.size.height);

    CGAffineTransform clippingPathTransform = reCenterTransform;
    clippingPathTransform = CGAffineTransformConcat(clippingPathTransform, moveFromCenter);
    clippingPathTransform = CGAffineTransformConcat(clippingPathTransform, rotateAndScale);
    clippingPathTransform = CGAffineTransformConcat(clippingPathTransform, moveToCenter);
    clippingPathTransform = CGAffineTransformConcat(clippingPathTransform, flipTransform);
    return clippingPathTransform;
}

/**
 * this will return the transform required to take
 * a coordinate and transform it from the page's 
 * coordinate space and into the scrap's coordinate space
 */
- (CGAffineTransform)pageToScrapTransformWithPageOriginalUnscaledBounds:(CGRect)originalUnscaledBounds {
    // since a scrap's center point is changed if the scrap is being
    // held, we can't just use scrap.center to adjust the path for
    // rotations etc. we need to calculate the center of a scrap
    // so that it doesn't matter if it's position/anchor have been
    // changed or not.
    CGPoint calculatedScrapCenter = [self convertPoint:CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2) toView:self.superview];

    // determine the tranlsation that we need to make on the path
    // so that it's moved into the scrap's coordinate space
    CGAffineTransform entireTransform = CGAffineTransformIdentity;

    // find the scrap location in open gl
    CGAffineTransform flipTransform = CGAffineTransformMake(1, 0, 0, -1, 0, originalUnscaledBounds.size.height);
    CGPoint scrapCenterInOpenGL = CGPointApplyAffineTransform(calculatedScrapCenter, flipTransform);
    // center the stroke around the scrap center,
    // so that any scale/rotate happens in relation to the scrap
    entireTransform = CGAffineTransformConcat(entireTransform, CGAffineTransformMakeTranslation(-scrapCenterInOpenGL.x, -scrapCenterInOpenGL.y));
    // now scale and rotate the scrap
    // we reverse the scale, b/c the scrap itself is scaled. these two together will make the
    // path have a scale of 1 after it's added
    entireTransform = CGAffineTransformConcat(entireTransform, CGAffineTransformMakeScale(1.0 / self.scale, 1.0 / self.scale));
    // this one confuses me honestly. i would think that
    // i'd need to rotate by -scrap.rotation so that with the
    // scrap's rotation it'd end up not rotated at all. somehow the
    // scrap has an effective rotation of -rotation (?).
    //
    // thinking about it some more, I think the issue is that
    // scrap.rotation is defined as the rotation in Core Graphics
    // coordinate space, but since OpenGL is flipped, then the
    // rotation flips.
    //
    // think of a spinning clock. it spins in different directions
    // if you look at it from the top or bottom.
    //
    // either way, when i rotate the path by scrap.rotation, it ends up
    // in the correct visible space. it works!
    entireTransform = CGAffineTransformConcat(entireTransform, CGAffineTransformMakeRotation(self.rotation));

    // before this line, the path is in the correct place for a scrap
    // that has (0,0) in it's center. now move everything so that
    // (0,0) is in the bottom/left of the scrap. (this might also
    // help w/ the rotation somehow, since the rotate happens before the
    // translate (?)
    CGPoint recenter = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    return CGAffineTransformConcat(entireTransform, CGAffineTransformMakeTranslation(recenter.x, recenter.y));
}

- (void)blockToFireWhenStateLoads:(void (^)())block {
    if ([self.state isScrapStateLoaded]) {
        block();
    } else {
        @synchronized(blocksToFireWhenStateIsLoaded) {
            [blocksToFireWhenStateIsLoaded addObject:[block copy]];
        }
    }
}

#pragma mark - JotView

- (void)addElements:(NSArray*)elements withTexture:(JotBrushTexture*)texture {
    [scrapState addElements:elements withTexture:texture];
}

- (void)addUndoLevelAndFinishStroke {
    [scrapState addUndoLevelAndFinishStroke];
}


#pragma mark - MMScrapViewStateDelegate

- (void)didLoadScrapViewState:(MMScrapViewState*)state {
    @synchronized(blocksToFireWhenStateIsLoaded) {
        while ([blocksToFireWhenStateIsLoaded count]) {
            void (^block)() = [blocksToFireWhenStateIsLoaded firstObject];
            block();
            [blocksToFireWhenStateIsLoaded removeObjectAtIndex:0];
        }
    }
}


#pragma mark - Ignore Touches

/**
 * these two methods make sure that the ruler view
 * can never intercept any touch input. instead it will
 * effectively pass through this view to the views behind it
 */
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    return nil;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event {
    return NO;
}


#pragma mark - Saving

- (void)saveScrapToDisk:(void (^)(BOOL hadEditsToSave))doneSavingBlock {
    if (scrapState) {
        [scrapState saveScrapStateToDisk:doneSavingBlock];
    } else {
        @throw [NSException exceptionWithName:@"ScrapSaveException" reason:@"saving scrap without a state" userInfo:nil];
        // i think the right answer here is to just call the doneSavingBlock(NO)
        // but i'm having trouble reproducing this code path.
    }
}


#pragma mark - State

- (void)loadScrapStateAsynchronously:(BOOL)async {
    //    DebugLog(@"asking scrap %@ to load async %d", scrapState.uuid, async);
    [scrapState loadScrapStateAsynchronously:async];
}

- (void)unloadState {
    //    DebugLog(@"asking scrap %@ to unload", scrapState.uuid);
    [scrapState unloadState];
}

- (void)unloadStateButKeepThumbnailIfAny {
    [scrapState unloadStateButKeepThumbnailIfAny];
}

- (void)didMoveToSuperview {
    [scrapState.scrapsOnPaperState scrapVisibilityWasUpdated:self];
}

#pragma mark - Properties

- (UIBezierPath*)bezierPath {
    return scrapState.bezierPath;
}

- (CGSize)originalSize {
    return scrapState.originalSize;
}

- (MMScrapViewState*)state {
    return scrapState;
}


#pragma mark - Sub-scrap content


/**
 * this will take self's drawn contents and
 * stamp them onto the input otherScrap in the
 * exact same place they are visually on the page
 */
- (void)stampContentsFrom:(JotView*)otherDrawableView {
    // step 1: generate a gl texture of my entire contents
    CGSize stampSize = otherDrawableView.pagePtSize;
    stampSize.width *= otherDrawableView.scale;
    stampSize.height *= otherDrawableView.scale;
    __block JotGLTexture* otherTexture = nil;
    __block CGPoint p1 = CGPointZero;
    __block CGPoint p2 = CGPointZero;
    __block CGPoint p3 = CGPointZero;
    __block CGPoint p4 = CGPointZero;
    [otherDrawableView.context runBlock:^{
        otherTexture = [otherDrawableView generateTexture];

        // opengl coordinates
        // when a texture is drawn, it's drawn in these coordinates
        // from coregraphics top left counter clockwise around.
        //    { 0.0, fullPixelSize.height},
        //    { fullPixelSize.width, fullPixelSize.height},
        //    { 0.0, 0.0},
        //    { fullPixelSize.width, 0.0}
        //
        // this is equivelant to starting in top left (0,0) in
        // core graphics. and moving clockwise.

        // get the coordinates of the new scrap in the old
        // scrap's coordinate space.
        CGRect bounds = self.state.drawableView.bounds;
        p1 = [otherDrawableView convertPoint:bounds.origin fromView:self.state.drawableView];
        p2 = [otherDrawableView convertPoint:CGPointMake(bounds.size.width, 0) fromView:self.state.drawableView];
        p3 = [otherDrawableView convertPoint:CGPointMake(0, bounds.size.height) fromView:self.state.drawableView];
        p4 = [otherDrawableView convertPoint:CGPointMake(bounds.size.width, bounds.size.height) fromView:self.state.drawableView];

        // normalize the coordinates to get texture
        // coordinate space of 0 to 1
        p1.x /= otherDrawableView.bounds.size.width;
        p2.x /= otherDrawableView.bounds.size.width;
        p3.x /= otherDrawableView.bounds.size.width;
        p4.x /= otherDrawableView.bounds.size.width;
        p1.y /= otherDrawableView.bounds.size.height;
        p2.y /= otherDrawableView.bounds.size.height;
        p3.y /= otherDrawableView.bounds.size.height;
        p4.y /= otherDrawableView.bounds.size.height;

        // now flip from core graphics to opengl coordinates
        CGAffineTransform flipTransform = CGAffineTransformMake(1, 0, 0, -1, 0, 1.0);
        p1 = CGPointApplyAffineTransform(p1, flipTransform);
        p2 = CGPointApplyAffineTransform(p2, flipTransform);
        p3 = CGPointApplyAffineTransform(p3, flipTransform);
        p4 = CGPointApplyAffineTransform(p4, flipTransform);

        // now normalize from the drawable view size
        // vs its texture backing size
        CGFloat widthRatio = (stampSize.width / otherTexture.pixelSize.width);
        CGFloat heightRatio = (stampSize.height / otherTexture.pixelSize.height);
        p1.x *= widthRatio;
        p1.y *= heightRatio;
        p2.x *= widthRatio;
        p2.y *= heightRatio;
        p3.x *= widthRatio;
        p3.y *= heightRatio;
        p4.x *= widthRatio;
        p4.y *= heightRatio;
    }];

    // now stamp our texture onto the other scrap using these
    // texture coordinates
    [self drawTexture:otherTexture atP1:p1 andP2:p2 andP3:p3 andP4:p4 withTextureSize:stampSize];

    [[JotTextureCache sharedManager] returnTextureForReuse:otherTexture];
}

/**
 * this method allows us to stamp an arbitrary texture onto the scrap, using the input
 * texture coordinates
 */
- (void)drawTexture:(JotGLTexture*)texture atP1:(CGPoint)p1 andP2:(CGPoint)p2 andP3:(CGPoint)p3 andP4:(CGPoint)p4 withTextureSize:(CGSize)textureSize {
    [scrapState importTexture:texture atP1:p1 andP2:p2 andP3:p3 andP4:p4 withTextureSize:textureSize];
}

//#pragma mark - dealloc
//
//-(void) dealloc{
//    DebugLog(@"dealloc scrap: %@", scrapState.uuid);
//}

@end
