//
//  SaveLocationService.m
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-12-19.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "ParabayAppDelegate.h"
#import "SaveLocationService.h"
#import "Globals.h"
#import "JSON.h"
#import "PageData.h"

@implementation SaveLocationService

@synthesize items, results, locEntityDescription;

- (BOOL)sendSaveRequest {
	
	BOOL ret = NO;
	
	NSFetchRequest *req = [[NSFetchRequest alloc] init];
	[req setEntity:self.locEntityDescription];
	[req setFetchLimit:10];
	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:
							  @"parabay_status = %d", RecordStatusUpdated];
	[req setPredicate:predicate];
	
	NSError *dataError = nil;
	self.results = [self.insertionContext executeFetchRequest:req error:&dataError];
	if ((dataError != nil) || (self.results == nil)) {
		NSLog(@"Error while fetching\n%@",
			  ([dataError localizedDescription] != nil)
			  ? [dataError localizedDescription] : @"Unknown Error");
	}
	
	if ([self.results count]>0) {
		
		NSLog(@"Found location updates: %d", [results count]);
		
		NSMutableArray *itemsList = [[[NSMutableArray alloc] init] autorelease];
		for (NSManagedObject *item in self.results) {
			[itemsList addObject: [self convertNSManagedObjectToDictionary:item]];
		}
		
		NSLog(@"Location List=%@", itemsList);
		self.items = itemsList;
		
		[self execute];
		ret = YES;
	}
	
	[req release];
	return ret;
}

- (NSMutableDictionary *) convertLocationManagedObjectToDictionary:(NSManagedObject *)loc {
	
	NSMutableDictionary *dict = [[[NSMutableDictionary alloc] init] autorelease];

	[dict setObject:[loc valueForKey:@"address"] forKey:@"address"];
	[dict setObject:@"" forKey:@"state"];
	[dict setObject:@"" forKey:@"city"];
	[dict setObject:@"" forKey:@"zipcode"];
	
	[dict setObject:[loc valueForKey:@"longitude"] forKey:@"longitude"];
	[dict setObject:[loc valueForKey:@"latitude"] forKey:@"latitude"];
		
	[dict setValue:[loc valueForKey:@"parabay_id"]  forKey:@"id"];
	
	return dict;
}

- (id)init {
	
	if (self = [super init]) {
		doneNotification = ServerLocationSavedNotification;		
	}
	return self;
}

- (void)execute
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSString* token = [defaults objectForKey:@"UD_TOKEN"];
	
	//NSLog(@"Saving items=%@", self.items);
	
	NSString *data = [items JSONRepresentation];
	
	if (data && token) {
		
		// Construct the request.http://localhost:8080/api/savearray/ParabayOrg-Outlook/Calendar_Appointment?data=[{"MeetingOrganizer":%20"Varadaraj,%20Vishnu2",%20"Subject":%20"Subaru%20Forrester%20appt2."}]
		NSString *path = [NSString stringWithFormat: @"/api/save_locations/%@", [[Globals sharedInstance] appName]];
		NSDictionary *parameters = [NSDictionary dictionaryWithObjectsAndKeys:
									data, @"data",
									token, @"token",
									kClientVersion, kClientVersionKey,
									nil];
		
		[self queueRequest:path withParameters: parameters];
	}
	else {
		NSLog(@"Failed to convert to json");
	}
}

- (void)loadData:(NSDictionary *)json
{		
	if (results) {
		for(NSManagedObject *item in results) {
			[item setValue:[NSNumber numberWithInt:RecordStatusSynchronized] forKey: @"parabay_status"];
		}
		
		NSError *saveError = nil;
		[insertionContext save:&saveError];
		if (saveError) {
			NSLog(@"Unhandled error saving managed object context in saver thread: %@", [saveError localizedDescription]);	
		}
		
		results = nil;
	}	
	
	[super loadData:json];	
}

- (NSEntityDescription *)locEntityDescription {
	
    if (locEntityDescription == nil) {
        locEntityDescription = [[NSEntityDescription entityForName: @"ParabayLocations" inManagedObjectContext:self.insertionContext] retain];
    }
    return locEntityDescription;
}

@end
