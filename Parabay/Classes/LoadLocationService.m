//
//  LoadLocationService.m
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-11-24.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "LoadLocationService.h"
#import "ParabayAppDelegate.h"
#import "SaveService.h"
#import "Globals.h"
#import "JSON.h"
#import "SyncService.h"

@implementation LoadLocationService

@synthesize locEntityDescription;

- (id)init {
	if (self = [super init]) {
		doneNotification = ServerLocationSavedNotification;		
	}
	return self;
}

- (BOOL) sendLoadRequest {
	
	[self execute];
	
	return YES;
}

- (void)execute
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSString* token = [defaults objectForKey:@"UD_TOKEN"];
			
	NSString *queryFormat = @"{\"columns\":[],\"kind\":\"UserLocations\",\"filters\":[{\"condition\":\"bookmark >= \",\"param\":\"%@\",\"type\":\"string\"}],\"orders\":[\"bookmark\"]}";
	NSString *serverSyncToken = [[SyncService sharedInstance] fetchServerTokenForKind: kParabayLocations];		
	if (!serverSyncToken) {
		serverSyncToken = @"";
	}
	
	// Construct the request.http://localhost:8080/api/locations/ParabayOrg-Outlook
	NSString *path = [NSString stringWithFormat: @"/api/locations/%@", [[Globals sharedInstance] appName]];
	NSDictionary *parameters = [NSDictionary dictionaryWithObjectsAndKeys:
								token, @"token",
								[NSString stringWithFormat:queryFormat, serverSyncToken], @"query",
								nil];
	
	[self queueRequest:path withParameters:parameters];
}

- (void)loadData:(NSDictionary *)json
{			
	NSUInteger batchTotal = 0;
	
	NSDictionary *resultSet = [json objectForKey:@"ResultSet"];
	NSArray *results = [resultSet objectForKey:@"Result"];
		
	for(NSDictionary *result in results) {   
				
		batchTotal++;
		
		NSString *key = [result objectForKey:@"name"];		
		//NSLog(@"Loaded location row=%@", key);
		
		NSFetchRequest *req = [[NSFetchRequest alloc] init];
		[req setEntity:self.locEntityDescription];
		NSPredicate *predicate = [NSPredicate predicateWithFormat:
								  @"parabay_id = %@", key];
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
			
			if (isDeleted) {
				NSLog(@"Deleting local item=%@", key);
				[insertionContext deleteObject:item];				
			}
			
		}
		
		if (!isDeleted) {
			
			if (!item) {
				item = [[NSManagedObject alloc] initWithEntity:self.locEntityDescription insertIntoManagedObjectContext:self.insertionContext];
			}
			
			NSString *address = [NSString stringWithFormat:@"%@, %@, %@ %@", [result objectForKey:@"address"], [result objectForKey:@"city"], [result objectForKey:@"state"], [result objectForKey:@"zipcode"]];
			[item setValue:address forKey:@"address"];
			[item setValue:[result objectForKey:@"city"] forKey:@"city"];
			[item setValue:[result objectForKey:@"state"] forKey:@"state"];
			[item setValue:[result objectForKey:@"zipcode"] forKey:@"zipcode"];
			
			NSString *longitude = [result objectForKey:@"longitude"];
			NSNumber *longitudeNumber = [NSNumber numberWithDouble:[longitude doubleValue]];
			[item setValue:longitudeNumber forKey:@"longitude"];
			NSString *latitude = [result objectForKey:@"latitude"];
			NSNumber *latitudeNumber = [NSNumber numberWithDouble:[latitude doubleValue]];
			[item setValue:latitudeNumber forKey:@"latitude"];
			[item setValue:[result objectForKey:@"geohash"] forKey:@"geohash"];
			
			[item setValue:key forKey:@"parabay_id"];
			[item setValue:[NSDate date] forKey:@"parabay_updated"];
			[item setValue:[NSNumber numberWithInt:RecordStatusSynchronized] forKey:@"parabay_status"];
			
		}
				
	}
		
	if (batchTotal > 0) {
		NSError *saveError = nil;
		NSAssert1([insertionContext save:&saveError], @"Unhandled error saving managed object context in import location thread: %@", [saveError localizedDescription]);		
	}	

	NSString *serverSyncToken = [json objectForKey:@"sync_token"];
	if (serverSyncToken && ([serverSyncToken length] > 0)) {
		
		[[SyncService sharedInstance] updateServerToken:serverSyncToken forKind:kParabayLocations];
		
		LoadLocationService *dataLoader = [[[LoadLocationService alloc] init] autorelease];
		dataLoader.privateQueue = self.privateQueue;
		[dataLoader sendLoadRequest];	
	}
	else {
		NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
							  [NSNumber numberWithInt:0], @"status", nil];
		[self forwardResult: dict];
	}
	
}

- (NSEntityDescription *)locEntityDescription {
	
    if (locEntityDescription == nil) {
        locEntityDescription = [[NSEntityDescription entityForName: @"ParabayLocations" inManagedObjectContext:self.insertionContext] retain];
    }
    return locEntityDescription;
}

@end
