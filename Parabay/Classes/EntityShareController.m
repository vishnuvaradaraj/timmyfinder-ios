//
//  EntityShareController.m
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-12-28.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "EntityShareController.h"
#import "JSON.h"
#import "Globals.h"
#import "PageData.h"
#import "ParabayAppDelegate.h"
#import "MetadataService.h"
#import <AVFoundation/AVFoundation.h>

#define AMIPHD_P2P_SESSION_ID @"amiphd-p2p"

@implementation EntityShareController

@synthesize pageName=_pageName,otherPeerID=_otherPeerID, managedObjectContext=_managedObjectContext, entityDescription=_entityDescription, pageData=_pageData, gkSession =_gkSession, peerCount=_peerCount, selectedItems=_selectedItems;

- (id)initWithPage:(NSString*)name query:(NSDictionary*)query {
	
	if (self = [super init]) {
		
		self.pageName = [name copy];
		self.pageData = [[MetadataService sharedInstance] getPageData:name forEditorPage:nil ];
		NSLog(@"Share page: %@", self.pageName);
		
		self.title = @"Share";
		self.variableHeightRows = YES;		
		self.tableViewStyle = UITableViewStyleGrouped;
					
		self.dataSource = [TTSectionedDataSource dataSourceWithObjects:
						   @"Email",
						   [TTTableButton itemWithText:@"Email" URL:@"tt://home/share/email"],
						   @"P2P sharing",
						   [TTTableButton itemWithText:@"Connect to peer" URL:@"tt://home/share/connect"],
						   [TTTableButton itemWithText:@"Send data to peer" URL:@"tt://home/share/send"],						   
						   nil];
	}
	return self;
}

-(void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	
	[[TTNavigator navigator].URLMap from:@"tt://home/share/email" toObject:self selector:@selector(sendEmail)];
	[[TTNavigator navigator].URLMap from:@"tt://home/share/send" toObject:self selector:@selector(sendDataToPeer)];
	[[TTNavigator navigator].URLMap from:@"tt://home/share/connect" toObject:self selector:@selector(connectToPeer)];
	[[TTNavigator navigator].URLMap from:@"tt://home/share/show" toObject:self selector:@selector(showPeers)];	
}

-(void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	
	[[TTNavigator navigator].URLMap removeURL:@"tt://home/share/email"];
	[[TTNavigator navigator].URLMap removeURL:@"tt://home/share/send"];
	[[TTNavigator navigator].URLMap removeURL:@"tt://home/share/connect"];
	[[TTNavigator navigator].URLMap removeURL:@"tt://home/share/show"];	
}

- (void)multiSelectionChanged:(NSArray *) multiSelection inListView: (UIViewController *)entityListController {
	
	if (_selectorAction) {
		self.selectedItems = multiSelection;
		[self performSelector:_selectorAction];
	}	
}

-(void) processEmailSelection {
	
	if (self.selectedItems && [self.selectedItems count]>0 && [MFMailComposeViewController canSendMail]) {
				
		MFMailComposeViewController *picker = [[MFMailComposeViewController alloc] init];
		picker.mailComposeDelegate = self;
		
		[picker setSubject:@"Data from Parabay Inc."];
		[picker setMessageBody:[self dataToHtml:self.selectedItems] isHTML:YES];
		[self presentModalViewController:picker animated:YES];
	}	
}

-(NSString *) dataToHtml: (NSArray *)data {
	
	//NSLog(@"Report layout= %@", self.pageData.reportLayout);
	
	NSString *ret = [self.pageData.reportLayout valueForKey:@"header"]; 
	
	if (data && [data count]>0) {
		for (NSManagedObject *item in data) {
			
			NSString *itemHtml = [self itemToHtml:item];
			ret = [ret stringByAppendingString:itemHtml];
		}
	}
	
	ret = [ret stringByAppendingString:[self.pageData.reportLayout valueForKey:@"footer"]];
	
	return ret;
}

-(NSString *) valueForProperty: (NSString *)propertyName inEntity: (NSManagedObject *)item {

	id value = nil;
	NSString *ret = @"";
	
	NSArray *keyComponents = [propertyName componentsSeparatedByString:@"."];
	if ([keyComponents count]>1) {
		
		NSManagedObject *subItem = [item valueForKey: [keyComponents objectAtIndex:0]];
		value = [subItem valueForKey: [keyComponents objectAtIndex:1]];
	}
	else {
		value = [item valueForKey:propertyName];
	}
	
	if (value) {
		if ([value isKindOfClass:[NSString class]]) {
			ret = value;
		}
		else {
			ret = [NSString stringWithFormat:@"%@", value];
		}		
	}

	return ret;
}

-(NSString *)formatString: (NSString *)str withArgs: (NSArray *)args {
	
	NSString *ret = str;
	
	//NSLog(@"Format=%@, params=%@", str, args);
	
	if ([args count] == 1) {
		ret = [NSString stringWithFormat:str, [args objectAtIndex:0]];
	}
	else if ([args count] == 2) {
		ret = [NSString stringWithFormat:str, [args objectAtIndex:0], [args objectAtIndex:1]];
	}
	else if ([args count] == 3) {
		ret = [NSString stringWithFormat:str, [args objectAtIndex:0], [args objectAtIndex:1], [args objectAtIndex:2]];
	}
	else if ([args count] == 4) {
		ret = [NSString stringWithFormat:str, [args objectAtIndex:0], [args objectAtIndex:1], [args objectAtIndex:2], [args objectAtIndex:3]];
	}
	else if ([args count] == 5) {
		ret = [NSString stringWithFormat:str, [args objectAtIndex:0], [args objectAtIndex:1], [args objectAtIndex:2], [args objectAtIndex:3], [args objectAtIndex:4]];
	}
	else {
		NSLog(@"Error: Unsupported param length in entity report");
	}

	
	return ret;
}

-(NSString *) itemToHtml: (NSManagedObject *)item {
	
	NSString *ret = @"";
	
	NSArray *rows = [self.pageData.reportLayout valueForKey:@"rows"];
	for (NSDictionary *row in rows) {
		
		NSString *type = [row valueForKey:@"type"];
		NSString *format = [row valueForKey:@"format"];
		NSArray *params = [row valueForKey:@"params"];
		NSMutableArray *paramValues = [[[NSMutableArray alloc]init] autorelease];
		
		if (NSOrderedSame == [type compare:@"item"]) {
			
			[paramValues removeAllObjects];
			for(NSDictionary *param in params) {
				
				NSString *value = [self valueForProperty:[param valueForKey:@"column"] inEntity: item];
				[paramValues addObject:value];
			}
			
			ret = [ret stringByAppendingString: [self formatString:format withArgs:paramValues]];			
		}
		else if (NSOrderedSame == [type compare:@"array"]) {
			
			NSString *column = [row valueForKey:@"column"];
			NSSet *relatedItems = [item valueForKey:column];
			
			for(NSManagedObject *rel in relatedItems) {
				
				[paramValues removeAllObjects];
				for(NSDictionary *param in params) {
					
					NSString *value = [self valueForProperty:[param valueForKey:@"column"] inEntity: rel];
					[paramValues addObject:value];
				}
				
				ret = [ret stringByAppendingString: [self formatString:format withArgs:paramValues]];
			}
		}
	}

	return ret;
}
						   
-(void) processSendSelection {
		
	if (self.otherPeerID) {
		[self initDataSender];
	}
}

- (void)sendEmail {
	
	_selectorAction = @selector(processEmailSelection);
	
	NSString *url = [NSString stringWithFormat:@"tt://home/list/%@?selectMode=multi&dismissOnSelection=1&actionButton=Email&selectionDelegate=%@", self.pageName,[[TTNavigator navigator] pathForObject:self]]; 		
	NSLog(@"Share select url: %@", url);
	[[TTNavigator navigator] openURL:url query:nil animated:YES];
	
}

- (void)sendDataToPeer {
	
	if (self.otherPeerID) {
		_selectorAction = @selector(processSendSelection);
		
		NSString *url = [NSString stringWithFormat:@"tt://home/list/%@?selectMode=multi&dismissOnSelection=1&actionButton=Send&selectionDelegate=%@", self.pageName,[[TTNavigator navigator] pathForObject:self]]; 		
		NSLog(@"Share select url: %@", url);
		[[TTNavigator navigator] openURL:url query:nil animated:YES];
	}
	else {
		UIAlertView *currentPopUpView = [[UIAlertView alloc] initWithTitle:@"Error"
																   message:@"Peer not connected"
																  delegate:self
														 cancelButtonTitle:@"Ok"
														 otherButtonTitles:nil];
		[currentPopUpView show];
	}

	
}

- (void)connectToPeer {
	
	NSLog(@"Connecting to peer...");
	
	[self cleanupSession];

	GKPeerPickerController *peerPickerController = [[GKPeerPickerController alloc] init];
	peerPickerController.delegate = self;
	peerPickerController.connectionTypesMask = GKPeerPickerConnectionTypeNearby;
	[peerPickerController show];						
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error {	
	switch (result)
	{
		case MFMailComposeResultCancelled:
			NSLog(@"Result: sent email");
			break;
		default:
			NSLog(@"Result: email not sent");
			break;
	}	
	[self dismissModalViewControllerAnimated:YES];
}

#pragma mark GKPeerPickerControllerDelegate methods

-(GKSession*) peerPickerController: (GKPeerPickerController*) controller 
		  sessionForConnectionType: (GKPeerPickerConnectionType) type {
	
	NSLog (@"peerPickerController:sessionForConnectionType(Create NEW session)");
	
	if (!self.gkSession) {
		self.gkSession = [[GKSession alloc]
					 initWithSessionID:AMIPHD_P2P_SESSION_ID
					 displayName:nil
					 sessionMode: GKSessionModePeer];
		self.gkSession.delegate = self;
		self.gkSession.available = YES;
		
	}
	return self.gkSession;
}

- (void)peerPickerController:(GKPeerPickerController *)picker
			  didConnectPeer:(NSString *)peerIDParam toSession:(GKSession *)session {
	
	NSLog ( @"peerPickerController: connected to peer %@", peerIDParam);
	
	//take ownership
	[session retain]; 	 // TODO: who releases this?
	
	[picker dismiss];
	[picker release];

}

- (void)peerPickerControllerDidCancel:(GKPeerPickerController *)picker {
	
	NSLog ( @"peer picker cancelled");
	[picker release];
}

#pragma mark GKSessionDelegate methods

- (void)session:(GKSession *)session peer:(NSString *)peerID
 didChangeState:(GKPeerConnectionState)state {
	
    switch (state) 
    { 
        case GKPeerStateConnected: 
			NSLog(@"GKPeerStateConnected");
			[session setDataReceiveHandler: self withContext: nil]; 
			self.otherPeerID = peerID;
			break; 
		case GKPeerStateDisconnected:
			NSLog(@"GKPeerStateDisconnected");
			self.otherPeerID = nil;
			break;
    } 
}

- (void)session:(GKSession *)session
didReceiveConnectionRequestFromPeer:(NSString *)peerID {
	
	NSLog(@"didReceiveConnectionRequestFromPeer: (Other peer initiated the connection) %@", peerID);
}

- (void)session:(GKSession *)session connectionWithPeerFailed:(NSString *)peerID withError:(NSError *)error {
	NSLog (@"session:connectionWithPeerFailed:withError:");	
}

- (void)session:(GKSession *)session didFailWithError:(NSError *)error {
	NSLog (@"session:didFailWithError:");		
}

# pragma mark receive data from session

/* receive data from a peer. callbacks here are set by calling
 [session setDataHandler: self context: whatever];
 when accepting a connection from another peer (ie, when didChangeState sends GKPeerStateConnected)
 */
- (void) receiveData: (NSData*) data fromPeer: (NSString*) peerID
		   inSession: (GKSession*) session context: (void*) context {
	
	//[[GKVoiceChatService defaultVoiceChatService] receivedData:data fromParticipantID:peer];	
	[self initDataReceiver: data];
}

-(NSString *)serializeDataArray: (NSArray *)dataArray withPageData: (PageData *)metadata  {
	
	NSMutableArray *array = [[[NSMutableArray alloc] init] autorelease];	
	for (NSManagedObject *mo in dataArray) {
		
		NSDictionary *dict = [[Globals sharedInstance] convertNSManagedObjectToDictionary: mo withPageData: metadata];
		[array addObject:dict];
	}
	
	NSMutableDictionary *dataBlob = [[[NSMutableDictionary alloc] init]autorelease];
	[dataBlob setObject:array forKey:@"data"];
	[dataBlob setObject:metadata.pageName	forKey:@"pageName"];
	[dataBlob setObject:metadata.defaultEntityName forKey:@"kind"];
	
	return [dataBlob JSONRepresentation];
}

-(NSString *)serializeRelation: (NSString *)relation inDataArray: (NSArray *)dataArray withPageData: (PageData *)metadata  {
	
	NSDictionary *rel = [metadata.entityRelations valueForKey:relation];
	
	NSString *relColumn = [rel valueForKey:@"parent_column"];
	NSString *childEntity = [rel valueForKey:@"child_entity"];
	if (NSOrderedSame != [childEntity compare:metadata.defaultEntityName]) {
		
		//reverse the parent-child relation if related metadata is for parent. 
		relColumn = [rel valueForKey:@"child_column"];
	}
	
	NSMutableArray *array = [[[NSMutableArray alloc] init] autorelease];	
	for (NSManagedObject *mo in dataArray) {
		
		NSSet *relatedItems = [mo valueForKey:relColumn];
		for(NSManagedObject *ri in relatedItems) {
			
			NSDictionary *dict = [[Globals sharedInstance] convertNSManagedObjectToDictionary: ri withPageData: metadata];
			[array addObject:dict];
		}
	}
	
	NSMutableDictionary *dataBlob = [[[NSMutableDictionary alloc] init]autorelease];
	[dataBlob setObject:array forKey:@"data"];
	[dataBlob setObject:metadata.pageName	forKey:@"pageName"];
	[dataBlob setObject:metadata.defaultEntityName forKey:@"kind"];
	[dataBlob setObject:relation forKey:@"relation"];
	
	return [dataBlob JSONRepresentation];
}

-(void) initDataSender {
	
	NSLog(@"Sending data");
		
	NSString *data = [self serializeDataArray:self.selectedItems withPageData:self.pageData ];
			
	NSMutableData *message = [[NSMutableData alloc] init];
	NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc]
								 initForWritingWithMutableData:message];
	[archiver encodeObject: data forKey:@"data"];
	
	NSArray *dependencies = [self.pageData.listLayout valueForKey:@"dependencies"];
	NSString *dependeciesStr = [dependencies JSONRepresentation];
	[archiver encodeObject:dependeciesStr forKey:@"dependencies"];

	for (NSDictionary *dep in dependencies) {
		
		NSString *relPageName = [dep valueForKey:@"pageData"];
		NSString *relName = [dep valueForKey:@"relation"];
		
		PageData *relatedPageData = [[MetadataService sharedInstance] getPageData:relPageName forEditorPage:nil ];
		NSString *relatedData = [self serializeRelation:relName inDataArray:self.selectedItems withPageData:relatedPageData ];		

		[archiver encodeObject: relatedData	forKey:relPageName];
	}
	
	[archiver finishEncoding];
	
	NSLog(@"Sending data(%@): %@", self.pageData.defaultEntityName,  data);
	
	NSString *statusTitle = @"Success";
	NSArray *nameComponents = [self.pageData.defaultEntityName componentsSeparatedByString:@"_"];
	NSString *statusMessage = [NSString stringWithFormat: @"Sent %d %@(s).", [self.selectedItems count], [nameComponents objectAtIndex:1]];
	
	NSError *sendErr = nil;
	[self.gkSession sendDataToAllPeers: message
					 withDataMode:GKSendDataReliable error:&sendErr];
	if (sendErr) {
		
		NSLog (@"Send data failed: %@", sendErr);
		statusTitle = @"Error";
		statusMessage = [sendErr localizedDescription];
	}
	
	UIAlertView *currentPopUpView = [[UIAlertView alloc] initWithTitle:statusTitle
															   message:statusMessage
															  delegate:self
													 cancelButtonTitle:@"Ok"
													 otherButtonTitles:nil];
	[currentPopUpView show];
	
	[message release];
	[archiver release];
}

-(BOOL)deSerializeData: (NSString *)data withPageData: (PageData *)metadata  {
		
	BOOL ret = NO;
	
	NSMutableDictionary *dataBlob = [data JSONValue];
	
	NSString *dataPageName = [dataBlob valueForKey:@"pageName"];
	if (NSOrderedSame == [metadata.pageName compare:dataPageName]) {
		
		NSArray *array = [dataBlob valueForKey:@"data"];
		for (NSDictionary *result in array) {
			
			NSLog(@"Storing data: %@", result);
			
			NSString *key = [result objectForKey:@"id"];	
			NSManagedObject *item = [[Globals sharedInstance] objectWithId:key andKind:metadata.defaultEntityName inContext:self.managedObjectContext];
			if (!item) {
				
				item = [[NSManagedObject alloc] initWithEntity:self.entityDescription insertIntoManagedObjectContext:self.managedObjectContext];
			}
			
			[[Globals sharedInstance] convertDictionaryToNSManagedObject:result withManagedObject: item andPageData:metadata];
		}
		
		NSError *saveError = nil;
		[self.managedObjectContext save:&saveError];
		if (saveError) {
			NSLog(@"Unhandled error saving managed object context in import thread: %@", [saveError localizedDescription]);
		}	
		else {
			ret = YES;
		}
	}
	
	return ret;
}


-(void) initDataReceiver: (NSData*) data {
	
	NSLog(@"Receiving data...");
	
	NSKeyedUnarchiver *unarchiver =
		[[NSKeyedUnarchiver alloc] initForReadingWithData:data];
	
	if ([unarchiver containsValueForKey:@"data"]) {
		
		NSString *data = [unarchiver decodeObjectForKey:@"data"];
		NSString *dependsStr = [unarchiver decodeObjectForKey:@"dependencies"];
		
		NSString *statusTitle = @"Error";
		NSString *statusMessage = @"Unexpected data received";
		
		BOOL statusSummary = YES;
		if (dependsStr) {
			
			NSDictionary *depends = [dependsStr JSONValue];
			for (NSDictionary *dep in depends) {
				
				NSString *relPageName = [dep valueForKey:@"pageData"];				
				NSString *relatedDataStr = [unarchiver decodeObjectForKey:relPageName];
				
				PageData *relatedPageData = [[MetadataService sharedInstance] getPageData:relPageName forEditorPage:nil ];
				BOOL relStatus = [self deSerializeData:relatedDataStr withPageData:relatedPageData];
				if (!relStatus) {
					
					statusSummary = relStatus;
				}
			}			
		}
		
		BOOL status = [self deSerializeData:data withPageData:self.pageData];
		if (!status) {
			statusSummary = status;
		}
		
		if (statusSummary) {
			
			statusTitle = @"Success";
			
			NSArray *nameComponents = [self.pageData.defaultEntityName componentsSeparatedByString:@"_"];
			statusMessage = [NSString stringWithFormat:@"Received %@(s).", [nameComponents objectAtIndex:1]];
		}
		
		UIAlertView *currentPopUpView = [[UIAlertView alloc] initWithTitle:statusTitle
																   message:statusMessage
																  delegate:self
														 cancelButtonTitle:@"Ok"
														 otherButtonTitles:nil];
		[currentPopUpView show];		
		
	}
	
	[unarchiver release];
}

#pragma mark GKVoiceChatService methods

- (NSString *)participantID
{
	NSString *ret = nil;
	
	if (self.gkSession) {
		ret = self.gkSession.peerID;
	}
	return ret;
}

- (void)voiceChatService:(GKVoiceChatService *)voiceChatService sendData:(NSData *)data toParticipantID:(NSString *)participantID
{
	[self.gkSession sendData: data toPeers:[NSArray arrayWithObject: participantID] withDataMode: GKSendDataReliable error: nil];
}

-(void) startTalking {
	
	NSError *error = nil;
	AVAudioSession *audioSession = [AVAudioSession sharedInstance];
	
	if (![audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&error]) {
		NSLog(@"Error setting the play/record category: %@", [error localizedDescription]);
		return;
	}
	if (![audioSession setActive: YES error: &error]) {
		NSLog(@"Error activating the audio session: %@", [error localizedDescription]);
		return;
	}
	
	[GKVoiceChatService defaultVoiceChatService].client = self;
	if (![[GKVoiceChatService defaultVoiceChatService] startVoiceChatWithParticipantID: self.otherPeerID error: &error]) {
		NSLog(@"Error starting voice chat: %@", [error userInfo]);
	}
	
	return;
}

-(void) cleanupSession {
	
	if (self.gkSession) {
		
		NSLog(@"Cleanup Session");
		
		[self.gkSession disconnectFromAllPeers]; 
		self.gkSession.available = NO; 
		[self.gkSession setDataReceiveHandler: nil withContext: nil]; 
		self.gkSession.delegate = nil; 
		self.gkSession = nil;
	}
}

- (NSManagedObjectContext *)managedObjectContext {
	
    if (_managedObjectContext == nil) {
		ParabayAppDelegate *delegate = (ParabayAppDelegate *) [[UIApplication sharedApplication] delegate];
        _managedObjectContext = [delegate managedObjectContext];
    }
    return _managedObjectContext;
}

- (NSEntityDescription *)entityDescription {
	
    if (_entityDescription == nil) {		
		_entityDescription = [NSEntityDescription entityForName:self.pageData.defaultEntityName inManagedObjectContext:self.managedObjectContext];		
    }
    return _entityDescription;
}

- (void)dealloc {
			
	[self cleanupSession];
	[super dealloc];
}

@end
