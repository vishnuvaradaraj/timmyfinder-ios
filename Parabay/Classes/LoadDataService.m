//
//  LoadDataService.m
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-11-27.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "LoadDataService.h"
#import "ParabayAppDelegate.h"
#import "Globals.h"
#import "JSON.h"
#import "PageData.h"
#import "SyncService.h"

@implementation LoadDataService

- (id)init {
	if (self = [super init]) {
		doneNotification = DataListLoadedNotification;	
	}
	return self;
}

- (void)dealloc {
	[super dealloc];
}

- (BOOL) sendLoadRequest: (NSString *)page  {
	
	self.pageName = page;	
	[self execute];
	
	return YES;
}

/*
 http://parabaydata.appspot.com/api/list/ParabayOrg-Outlook?client_version=1.0&offset=10&query={"kind":"Calendar_Appointment","include_deleted_items":true,"orders":[],"columns":[],
 "filters":[{"condition":"updated >=","param":"2009-12-10T02:24:44.710102","type":"timestamp"}]}
 */
- (void)execute {
	
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSString* token = [defaults objectForKey:@"UD_TOKEN"];
	
	if (token) {
	
		NSLog(@"Start EntityLoader %@", self.pageName);	
		
		NSDictionary *dataQueryObject = [self.pageData.dataQuery objectForKey:@"data_query"];
		NSString *query = [self queryToSynch: dataQueryObject];
		
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		[formatter setDateFormat: @"dd/MM/yyyy"]; 
		NSString *today = [formatter stringFromDate: [NSDate date]];	
		
		NSString *path = [NSString stringWithFormat: @"/api/list/%@", [[Globals sharedInstance] appName]];
		NSDictionary *parameters = [NSDictionary dictionaryWithObjectsAndKeys:
									[query stringByReplacingOccurrencesOfString:@"@@today@@" withString:today], @"query",
									token, @"token",
									kClientVersion, kClientVersionKey,
									@"", @"bookmark",
									nil];
		
		[self queueRequest:path withParameters: parameters];
	}
}

- (void)loadData:(NSDictionary *)json
{			
	NSUInteger batchTotal = 0; //total read so far
	NSUInteger countForCurrentBatch = 0; //current total, reset after save
		
	NSArray *results = [json objectForKey:@"data"];
		
	for(NSDictionary *result in results) {   
		
		batchTotal++;
		
		NSString *key = [result objectForKey:@"id"];		
		//NSLog(@"Server data(%d): %@", batchTotal, [result valueForKey:@"Subject"]);
		
		NSFetchRequest *req = [[NSFetchRequest alloc] init];
		[req setEntity:self.entityDescription];
		NSPredicate *predicate = [NSPredicate predicateWithFormat:
								  @"name = %@", key];
		[req setPredicate:predicate];
		
		NSError *dataError = nil;
		NSArray *array = [self.insertionContext executeFetchRequest:req error:&dataError];
		if ((dataError != nil) || (array == nil)) {
			NSLog(@"Error while fetching\n%@",
				  ([dataError localizedDescription] != nil)
				  ? [dataError localizedDescription] : @"Unknown Error");
		}
		
		[req release];
		
		NSUInteger isDeleted = [[result objectForKey:@"is_deleted"] integerValue];
		
		NSManagedObject *item = nil;
		if ([array count] > 0) {
			item = [array objectAtIndex:0];
			//NSLog(@"Found existing item: %@", [item valueForKey:@"Subject"]);
			
			if (isDeleted) {
				NSLog(@"Deleting local item=%@", key);
				[insertionContext deleteObject:item];				
			}
			
		}
		
		if (!isDeleted) {
			
			if (!item) {
				item = [[NSManagedObject alloc] initWithEntity:self.entityDescription insertIntoManagedObjectContext:self.insertionContext];
			}
						
			[[Globals sharedInstance] convertDictionaryToNSManagedObject:result withManagedObject: item andPageData:pageData];
						
			//NSLog(@"Saving: %@ === %@", item, result);
		}
		
		countForCurrentBatch++;
		
		if (countForCurrentBatch >= 10) {
			NSError *saveError = nil;
			NSAssert1([insertionContext save:&saveError], @"Unhandled error saving managed object context in import thread: %@", [saveError localizedDescription]);
			countForCurrentBatch = 0;			
		}
		
	}
	
	NSLog(@"Loaded data rows: %d", batchTotal);
	
	//save data if necessary.
	if (countForCurrentBatch > 0) {
		NSError *saveError = nil;
		NSAssert1([insertionContext save:&saveError], @"Unhandled error saving managed object context in import thread: %@", [saveError localizedDescription]);
	}
			
	NSString *serverSyncToken = [json objectForKey:@"sync_token"];
	if (serverSyncToken && ([serverSyncToken length] > 0)) {
		
		[[SyncService sharedInstance] updateServerToken:serverSyncToken forKind:[self.pageData defaultEntityName]];
	
		LoadDataService *dataLoader = [[[LoadDataService alloc] init] autorelease];
		dataLoader.privateQueue = self.privateQueue;
		[dataLoader sendLoadRequest:self.pageName];
	}
	else {
		
		NSLog(@"Sync done: %@", self.pageName);
		
		NSString *key = [NSString stringWithFormat:kLastStoreUpdateKey, self.pageName];
		[[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:key];
					
		NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
							  self.pageName, @"pageName", nil];
		[self forwardResult:dict];		
	}	
}

- (NSString *) queryToSynch: (NSDictionary *)dataQueryObject {
	
	NSString *serverSyncToken = nil;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL fullResync = [defaults boolForKey:@"slow_sync_preference"];	
	if (!fullResync) {
		serverSyncToken = [[SyncService sharedInstance] fetchServerTokenForKind:[self.pageData defaultEntityName]];					
	}
	
	//ensure we start from the beginning
	if (!serverSyncToken) {
		serverSyncToken = @"";
	}
	
	NSString *syncQuery = [dataQueryObject objectForKey:@"syncQuery"];
	if (!syncQuery || [syncQuery length]==0) {
		syncQuery = @"{\"columns\":[],\"kind\":\"%@\",\"filters\":[{\"condition\":\"bookmark >= \",\"param\":\"%@\",\"type\":\"string\"}],\"orders\":[\"bookmark\"]}";
	}
	
	NSString *queryString = [NSString stringWithFormat: syncQuery, [self.pageData defaultEntityName],  serverSyncToken];
	
	NSDictionary *json = [queryString JSONValue]; 
	[json setValue:[NSNumber numberWithBool:YES ] forKey:@"include_deleted_items"];
	
	NSString *ret = [json JSONRepresentation];
	NSLog(@"Query=%@", ret);
	
	return ret;
}

@end
