//
//  MMUndoRedoRemoveScrapItem.m
//  LooseLeaf
//
//  Created by Adam Wulf on 7/5/14.
//  Copyright (c) 2014 Milestone Made, LLC. All rights reserved.
//

#import "MMUndoRedoBezeledScrapItem.h"
#import "MMUndoablePaperView.h"
#import "MMScrapSidebarContainerView.h"


@interface MMUndoRedoBezeledScrapItem (Private)

@property (readonly) NSDictionary* propertiesWhenRemoved;
@property (assign) BOOL sidebarEverDidContainScrap;

@end

@implementation MMUndoRedoBezeledScrapItem{
    NSDictionary* propertiesWhenRemoved;
    NSString* scrapUUID;
    BOOL sidebarEverDidContainScrap;
}

@synthesize scrapUUID;

+(id) itemForPage:(MMUndoablePaperView*)_page andScrapUUID:(NSString*)scrapUUID andProperties:(NSDictionary*)scrapProperties{
    return [[MMUndoRedoBezeledScrapItem alloc] initForPage:_page andScrapUUID:scrapUUID andProperties:scrapProperties];
}

-(id) initForPage:(MMUndoablePaperView*)_page andScrapUUID:(NSString*)_scrapUUID andProperties:(NSDictionary*)scrapProperties{
    __weak MMUndoRedoBezeledScrapItem* weakSelf = self;
    if(self = [super initWithUndoBlock:^{
        MMScrapView* scrap = [weakSelf.page.scrapsOnPaperState scrapForUUID:weakSelf.scrapUUID];
        if([weakSelf.page.bezelContainerView containsScrap:scrap]){
            weakSelf.sidebarEverDidContainScrap = YES;
            [weakSelf.page.bezelContainerView didTapOnScrapFromMenu:scrap withPreferredScrapProperties:weakSelf.propertiesWhenRemoved];
        }else{
            weakSelf.sidebarEverDidContainScrap = NO;
            [weakSelf.page.scrapsOnPaperState showScrap:scrap];
            [scrap setPropertiesDictionary:weakSelf.propertiesWhenRemoved];
            NSUInteger subviewIndex = [[weakSelf.propertiesWhenRemoved objectForKey:@"subviewIndex"] unsignedIntegerValue];
            [scrap.superview insertSubview:scrap atIndex:subviewIndex];
        }
    } andRedoBlock:^{
        MMScrapView* scrap = [weakSelf.page.scrapsOnPaperState scrapForUUID:weakSelf.scrapUUID];
        if(weakSelf.sidebarEverDidContainScrap){
            [weakSelf.page.bezelContainerView addScrapToBezelSidebar:scrap animated:YES];
        }else{
            [weakSelf.page.scrapsOnPaperState hideScrap:scrap];
        }
    } forPage:_page]){
        sidebarEverDidContainScrap = NO;
        scrapUUID = _scrapUUID;
        propertiesWhenRemoved = scrapProperties;
    };
    return self;
}


#pragma mark - Serialize

-(NSDictionary*) asDictionary{
    NSMutableDictionary* propertiesDictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:NSStringFromClass([self class]), @"class",
                                                 [NSNumber numberWithBool:self.canUndo], @"canUndo", nil];
    [propertiesDictionary setObject:propertiesWhenRemoved forKey:@"propertiesWhenRemoved"];
    [propertiesDictionary setObject:scrapUUID forKey:@"scrapUUID"];
    [propertiesDictionary setObject:[NSNumber numberWithBool:sidebarEverDidContainScrap] forKey:@"sidebarEverDidContainScrap"];
    
    return propertiesDictionary;
}

-(id) initFromDictionary:(NSDictionary*)dict forPage:(MMUndoablePaperView*)_page{
    NSDictionary* _properties = [dict objectForKey:@"propertiesWhenRemoved"];
    NSString* _scrapUUID = [dict objectForKey:@"scrapUUID"];
    
    if(self = [self initForPage:_page andScrapUUID:_scrapUUID andProperties:_properties]){
        canUndo = [[dict objectForKey:@"canUndo"] boolValue];
        sidebarEverDidContainScrap = [[dict objectForKey:@"sidebarEverDidContainScrap"] boolValue];
    }
    return self;
}

#pragma mark - Description

-(NSString*) description{
    return [NSString stringWithFormat:@"[%@ %@]", NSStringFromClass([self class]), scrapUUID];
}

#pragma mark - Private Properties

-(BOOL) sidebarEverDidContainScrap{
    return sidebarEverDidContainScrap;
}

-(void) setSidebarEverDidContainScrap:(BOOL)_sidebarEverDidContainScrap{
    sidebarEverDidContainScrap = _sidebarEverDidContainScrap;
}

-(NSDictionary*) propertiesWhenRemoved{
    return propertiesWhenRemoved;
}

@end