//
//  SaveFileService.m
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-12-06.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "SaveFileService.h"
#import "ParabayAppDelegate.h"
#import "SaveService.h"
#import "Globals.h"
#import "JSON.h"

@implementation SaveFileService

@synthesize item, imgEntityDescription;

- (BOOL)sendSaveRequest {
	
	BOOL ret = NO;
	
	NSFetchRequest *req = [[NSFetchRequest alloc] init];
	[req setEntity:self.imgEntityDescription];
	[req setFetchLimit:1];
	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:
							  @"parabay_status = %d", RecordStatusUpdated];
	[req setPredicate:predicate];
	
	NSError *dataError = nil;
	NSArray *results = [self.insertionContext executeFetchRequest:req error:&dataError];
	if ((dataError != nil) || (results == nil)) {
		NSLog(@"Error while fetching\n%@",
			  ([dataError localizedDescription] != nil)
			  ? [dataError localizedDescription] : @"Unknown Error");
	}
	
	if ([results count]>0) {
		
		NSLog(@"Found file updates: %d", [results count]);
		self.item = [results objectAtIndex:0];
		
		[self execute];
		ret = YES;
	}
	else {
		NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
							  [NSNumber numberWithInt:0], @"status", nil];
		[self forwardResult: dict];
	}
	
	[req release];
	return ret;
}

- (id)init {
	
	if (self = [super init]) {
		doneNotification = ServerFileSavedNotification;		
	}
	return self;
}

- (void)execute
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSString* token = [defaults objectForKey:@"UD_TOKEN"];
			
	if (self.item && token) {
		
		// Construct the request.http://localhost:8080/api/savearray/ParabayOrg-Outlook/Calendar_Appointment?data=[{"MeetingOrganizer":%20"Varadaraj,%20Vishnu2",%20"Subject":%20"Subaru%20Forrester%20appt2."}]
		NSString *path = @"/assets"; 
		NSString *key = [self.item valueForKey:@"cacheFilePath"];
		
		NSString *imageFilePath = [[Globals sharedInstance] imageFilePath:key];		
		UIImage *imageData = [UIImage imageWithContentsOfFile: imageFilePath];
		
		NSDictionary *parameters = [NSDictionary dictionaryWithObjectsAndKeys:
									token, @"token",
									key, @"id",
									imageData, @"upload",
									kClientVersion, kClientVersionKey,
									nil];
		
		[self sendRequest: path withParameters: parameters];
		
	}
	else {
		NSLog(@"Invalid item in save file request.");
	}
}

- (void)loadData:(NSDictionary *)json
{		
	if (self.item) {
		[self.item setValue:[NSNumber numberWithInt:RecordStatusSynchronized] forKey: @"parabay_status"];
		
		NSError *saveError = nil;
		NSAssert1([insertionContext save:&saveError], @"Unhandled error saving managed object context in saver thread: %@", [saveError localizedDescription]);	
		
		self.item = nil;
	}	
	
	/*
	SaveFileService *dataLoader = [[[SaveFileService alloc] init] autorelease];
	dataLoader.privateQueue = self.privateQueue;
	[dataLoader sendSaveRequest];	
	*/
}

- (void)sendRequest: (NSString *)path withParameters: (NSDictionary *)parameters {
	
	NSString *serviceUrl = [host stringByAppendingFormat:@"%@", path];
	
	NSLog(@"Sending TTURL Request: %@", serviceUrl);
	
	TTURLRequest *urlRequest = [TTURLRequest requestWithURL:serviceUrl delegate:self];
	urlRequest.cachePolicy = TTURLRequestCachePolicyNone;
	[urlRequest.parameters addEntriesFromDictionary:parameters];
	urlRequest.response = self;
	urlRequest.httpMethod = @"POST";
	
	// Dispatch the request.
	[urlRequest send];
	
}

/* Three20 library callbacks */
- (NSError*)request:(TTURLRequest*)request processResponse:(NSHTTPURLResponse*)response
			   data:(id)data
{
    NSString *responseBody = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSDictionary *json = [responseBody JSONValue];    
	
	if (json) {
		
		NSUInteger status = [[json objectForKey:@"status"] integerValue];		
		if (0 == status) {
			
			[self loadData:json];	
			
		}
		else {		
			
			NSString *errorMessage = [json objectForKey:@"error_message"];
			if (!errorMessage) {
				errorMessage = [NSString stringWithFormat: @"Server error: %d", status];
			}
			
			NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
								  [NSNumber numberWithInt:status], @"status", [errorMessage copy], NSLocalizedDescriptionKey, nil];	
			[self forwardResult: dict];
		}		
	}
	
    [responseBody release];
	return nil;
}

- (void)request:(TTURLRequest*)requestParam didFailLoadWithError:(NSError*)errorParam 
{
	
	NSLog(@"Error: request failed: %@", [errorParam localizedDescription]);
	
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
						  [NSNumber numberWithInt:-1], @"status", nil];			
	[self forwardResult: dict];	
}

- (void)requestDidCancelLoad:(TTURLRequest*)requestParam 
{
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
						  [NSNumber numberWithInt:-2], @"status", nil];			
	[self forwardResult: dict];	
}


- (NSEntityDescription *)imgEntityDescription {
	
    if (imgEntityDescription == nil) {
        imgEntityDescription = [[NSEntityDescription entityForName: @"ParabayImages" inManagedObjectContext:self.insertionContext] retain];
    }
    return imgEntityDescription;
}

@end
