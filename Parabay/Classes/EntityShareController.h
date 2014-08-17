//
//  EntityShareController.h
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-12-28.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Three20/Three20.h"
#import <MessageUI/MessageUI.h>
#import <MessageUI/MFMailComposeViewController.h>
#import <GameKit/GameKit.h>

@class PageData;

@interface EntityShareController : TTTableViewController<MFMailComposeViewControllerDelegate, GKSessionDelegate, GKPeerPickerControllerDelegate, GKVoiceChatClient> {

	NSString *_pageName;
	PageData *_pageData;

	GKSession *_gkSession;	
	NSInteger _peerCount;		
	NSString *_otherPeerID;
	NSManagedObjectContext *_managedObjectContext;
	NSEntityDescription *_entityDescription;

	SEL _selectorAction;
	NSArray *_selectedItems;
	
}

@property (nonatomic, retain) NSArray *selectedItems;
@property (nonatomic, retain) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, retain) PageData *pageData;
@property (nonatomic, retain) NSEntityDescription *entityDescription;
@property (nonatomic, retain) GKSession *gkSession;	
@property (nonatomic, retain) NSString *otherPeerID;
@property (nonatomic) NSInteger peerCount;	
@property (nonatomic, retain) NSString *pageName;

-(void) initDataSender;
-(void) initDataReceiver: (NSData*) data;
-(void) cleanupSession;
-(NSString *) dataToHtml: (NSArray *)data;
-(NSString *) itemToHtml: (NSManagedObject *)item;
-(NSString *)serializeDataArray: (NSArray *)dataArray withPageData: (PageData *)metadata;
-(NSString *)serializeRelation: (NSString *)relation inDataArray: (NSArray *)dataArray withPageData: (PageData *)metadata;
-(BOOL)deSerializeData: (NSString *)data withPageData: (PageData *)metadata;
-(NSString *) valueForProperty: (NSString *)propertyName inEntity: (NSManagedObject *)mo;
-(NSString *)formatString: (NSString *)str withArgs: (NSArray *)args;

@end
