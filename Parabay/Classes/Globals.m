//
//  Globals.m
//  Parabay
//
//  Created by Vishnu Varadaraj on 17/08/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "Globals.h"
#import "ParabayAppDelegate.h"
#import "PageData.h"
#import <CommonCrypto/CommonDigest.h>

static Globals* SharedInstance;

@implementation Globals

@synthesize dateFormatter, timeFormatter, photoDefault, appName, appStarted;

+ (Globals*)sharedInstance {
	if (!SharedInstance)
        SharedInstance = [[Globals alloc] init]; 
	
    return SharedInstance;
}

- (id)init {
	if (self = [super init]) {
		
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		appName = [defaults stringForKey:@"app_preference"];
		if (!appName) {
			appName = kParabayApp;
		}
	}
	return self;
}

- (NSDateFormatter *)dateFormatter {
    if (dateFormatter == nil) {
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
        [dateFormatter setTimeStyle:NSDateFormatterNoStyle];
    }
    return dateFormatter;
}

- (NSDateFormatter *)timeFormatter {
    if (timeFormatter == nil) {
        timeFormatter = [[NSDateFormatter alloc] init];
        [timeFormatter setDateStyle:NSDateFormatterNoStyle];
        [timeFormatter setTimeStyle:NSDateFormatterMediumStyle];
    }
    return timeFormatter;
}

- (void)addProgressIndicator:(UIView *)view {
	
	ParabayAppDelegate *appDelegate = (ParabayAppDelegate *)[[UIApplication sharedApplication] delegate];
	
    [view addSubview:appDelegate.progressOverlay];
    appDelegate.progressOverlay.alpha = 0.0;
    [view bringSubviewToFront:appDelegate.progressOverlay];
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:0.5];
    [UIView setAnimationTransition:UIViewAnimationTransitionNone forView:view cache:YES];
    appDelegate.progressOverlay.alpha = 0.7;
    [UIView commitAnimations];	
}

- (void)removeProgressIndicator:(UIView *)view {
	
	ParabayAppDelegate *appDelegate = (ParabayAppDelegate *)[[UIApplication sharedApplication] delegate];
	
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:0.5];
    [UIView setAnimationTransition:UIViewAnimationTransitionNone forView:view cache:YES];
    [UIView setAnimationDelegate:self];
    appDelegate.progressOverlay.alpha = 0.0;
    [UIView commitAnimations];
	
    [appDelegate.progressOverlay removeFromSuperview];	
}

- (void)showSpinner:(UIView *)view {
    [self performSelectorInBackground:@selector(addProgressIndicator:) withObject:view];
}

- (void)hideSpinner:(UIView *)view {
    [self performSelectorInBackground:@selector(removeProgressIndicator:) withObject:view];
}


- (void)displayError:(NSString *)error {
	
	UIAlertView* errorAlertView = [[[UIAlertView alloc] initWithTitle:
									@"Error"
															  message:error
															 delegate:self
													cancelButtonTitle:@"Cancel"
													otherButtonTitles:nil, nil] autorelease];
	[errorAlertView show];
}

- (void)displayInfo:(NSString *)msg {
	
	UIAlertView* infoAlertView = [[[UIAlertView alloc] initWithTitle:
								   @"Information"
															 message:msg
															delegate:self
												   cancelButtonTitle:@"Ok"
												   otherButtonTitles:nil, nil] autorelease];
	[infoAlertView show];
}

- (void)logout {
	
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	
	LogoutService *logout = [[LogoutService alloc] init];
	logout.token = [defaults objectForKey:@"UD_TOKEN"];
	[logout execute];
		
	TTOpenURL(@"tt://login");
}

- (NSMutableDictionary *) convertNSManagedObjectToDictionary: (NSManagedObject *)managedObject withPageData: (PageData *)pageData {
	
	NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
	
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat: @"yyyy-MM-dd'T'HH:mm"]; // 2009-02-01 19:50:41 PST		
	
	for(NSString *propertyName in pageData.defaultEntityProperties) {
		
		id value = [managedObject valueForKey:propertyName];
		if (value) {
			if ([value isKindOfClass:[NSDate class]]) {
				value = [formatter stringFromDate:value];
			}
			else if ([value isKindOfClass:[NSManagedObject class]]) {
				value = [value valueForKey:@"parabay_id"];
			}

			NSLog(@"Property=%@", propertyName);
			//skip images
			if (![value isKindOfClass:[NSData class]] && ![value isKindOfClass:[UIImage class]] && ![value isKindOfClass:[NSSet class]]) {
				
				[dict setObject:value forKey:propertyName];
			}
			else {
				NSLog(@"Skipping unsupported types");
			}
		}	
	}
	
	[dict setObject:[managedObject valueForKey:@"parabay_id"] forKey:@"id"];
	[formatter release];
	
	return dict;
}

- (NSManagedObject *) convertDictionaryToNSManagedObject: (NSDictionary *)result withManagedObject: (NSManagedObject *)item andPageData: (PageData *)pageData  {	
	
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat: @"yyyy-MM-dd'T'HH:mm"]; // 2009-02-01 19:50:41 PST		
	
	NSString *key = [result objectForKey:@"id"];			
	for(NSString *propertyName in pageData.defaultEntityProperties) {
		
		NSDictionary *entityPropertyMetadata = [pageData.defaultEntityProperties objectForKey:propertyName];
		
		NSString *propertyValue = [result objectForKey:propertyName];
		//special handling for name property
		if (NSOrderedSame == [propertyName compare:@"name"]) {
			propertyValue = key;
		}
		
		@try {
			
			NSString *dataType = [entityPropertyMetadata objectForKey:@"type_info"];				
			if (propertyValue) {				
				if (NSOrderedSame == [dataType compare:@"date"] || NSOrderedSame == [dataType compare:@"time"]) {
					NSDate *value = [formatter dateFromString:propertyValue];
					[item setValue: value  forKey: propertyName];
				}
				else if (NSOrderedSame == [dataType compare:@"boolean"]) {
					NSNumber *value = [NSNumber numberWithBool:NO];
					if ([propertyValue isKindOfClass:[NSNumber class]] ) {
						value = (NSNumber *)propertyValue;
					}
					[item setValue: value  forKey: propertyName];
				}
				else if (NSOrderedSame == [dataType compare:@"integer"]) {
					NSNumber *value = [NSNumber numberWithInt:0];
					if ([propertyValue isKindOfClass:[NSNumber class]] ) {
						value = (NSNumber *)propertyValue;
					}
					[item setValue: value  forKey: propertyName];
				}
				else if (NSOrderedSame == [dataType compare:@"float"]) {
					NSNumber *value = [NSNumber numberWithFloat:0.0];
					if ([propertyValue isKindOfClass:[NSNumber class]] ) {
						value = (NSNumber *)propertyValue;
					}
					[item setValue: value  forKey: propertyName];
				}
				else if (NSOrderedSame == [dataType compare:@"image"]) {
										
					NSManagedObject *imgItem = [[Globals sharedInstance] objectWithId:propertyValue andKind:@"ParabayImages" inContext:[item managedObjectContext]];
					if (imgItem) {
						[item setValue: imgItem forKey: propertyName];		
					}
					
				}
				else if (NSOrderedSame == [dataType compare:@"location"]) {
					
					NSManagedObject *locItem = [[Globals sharedInstance] objectWithId:propertyValue andKind:@"ParabayLocations" inContext:[item managedObjectContext]];
					if (locItem) {
						[item setValue: locItem forKey: propertyName];		
					}	
				}
				else if (NSOrderedSame == [dataType compare:@"fk"]) {
					
					NSString *relatedEntityName = [entityPropertyMetadata valueForKey:@"ref_type"];
					NSManagedObject *relatedItem = [[Globals sharedInstance] objectWithId:propertyValue andKind:relatedEntityName inContext:[item managedObjectContext]];
					if (relatedItem) {
						[item setValue: relatedItem forKey: propertyName];		
					}					
						
				}
				else {		
					//NSLog(@"Property(%@):%@", propertyName, dataType);
					if ((NSNull *)propertyValue != [NSNull null]) {
						[item setValue:[propertyValue description] forKey:propertyName];
					}
					else {
						NSLog(@"%@ is NULL", propertyName);
					}
					
				}
			}
		}
		@catch (NSException *exception) {
			NSLog(@"main: Caught %@: %@", [exception name], [exception reason]);
		}
		
	}
	
	[item setValue:key forKey:@"parabay_id"];
	[item setValue:[NSDate date] forKey:@"parabay_updated"];
	[item setValue:[NSNumber numberWithInt:RecordStatusSynchronized] forKey:@"parabay_status"];
	
	//NSLog(@"convert dict to MO result: %@", item);
	
	[formatter release];
	
	return item;
}

- (UIImage *)resizeImage: (UIImage *)selectedImage withMaxSize:(float)maxSize {
	
	// Create a thumbnail version of the image.
	CGSize size = selectedImage.size;
	if (size.width > maxSize || size.height > maxSize) {
		CGFloat ratio = 0;
		if (size.width > size.height) {
			ratio = maxSize / size.width;
		} else {
			ratio = maxSize / size.height;
		}
		CGRect rect = CGRectMake(0.0, 0.0, ratio * size.width, ratio * size.height);
		
		UIGraphicsBeginImageContext(rect.size);
		[selectedImage drawInRect:rect];
		UIImage *thumbNail = UIGraphicsGetImageFromCurrentImageContext();
		return thumbNail;
	}
	else {
		return selectedImage;
	}

}

- (UIImage *)defaultImage {
	
	if (!photoDefault) {
		photoDefault = [[self resizeImage:[UIImage imageNamed:@"photoDefault.png"] withMaxSize:44.0] retain];
	}
	return photoDefault;
}

- (UIImage *)thumbnailForProperty:(NSString *)propertyName inItem: (NSManagedObject *)item {
	
	UIImage *ret = [[Globals sharedInstance] defaultImage];
	NSManagedObject *imageRow = [item valueForKey:propertyName];
	
	if (imageRow && ([NSNull null] != (NSNull *)imageRow) ) {
		
		ret = [imageRow valueForKey:@"thumbnail"];		
	}
	
	return ret;
}

- (UIImage *)imageForProperty:(NSString *)propertyName inItem: (NSManagedObject *)item {
	
	UIImage *ret = [[Globals sharedInstance] defaultImage];
	NSManagedObject *imageRow = [item valueForKey:propertyName];
	
	if (imageRow && ([NSNull null] != (NSNull *)imageRow) ) {
		
		NSString *cacheFilePath = [imageRow valueForKey:@"cacheFilePath"];
		NSLog(@"Retrieved path: %@", cacheFilePath);
		
		UIImage *imageData = [UIImage imageWithContentsOfFile: [self imageFilePath: cacheFilePath]];
		if (imageData) {
			ret = imageData;
		}		
	}
	
	return ret;
}

- (NSString *)applicationDocumentsDirectory {
	
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return [basePath copy];
}

- (NSString *)fileCacheDirectory {
	
	BOOL isDir;
	NSError *error = nil;
	
	NSString *documentsDirectory = [self applicationDocumentsDirectory];
	NSString *fileCachePath = [ documentsDirectory stringByAppendingPathComponent: @"FileCache"];
			
	if (!([[NSFileManager defaultManager]  fileExistsAtPath: fileCachePath isDirectory:&isDir] && isDir)) {
		
		BOOL result = [[NSFileManager defaultManager] createDirectoryAtPath:fileCachePath withIntermediateDirectories:YES attributes:nil error: &error];
		if (!result)
			NSLog(@"Unhandled error creating folder %s at line %d: %@", __FUNCTION__, __LINE__, [error localizedDescription]);
	}
		
    return fileCachePath;
}

- (NSString *)imageFilePath: (NSString *)key {

	NSString *imagePath = [self fileCacheDirectory];
	return [imagePath stringByAppendingPathComponent: key];
}
	
- (NSString *) md5:(NSString *)str {
	const char *cStr = [str UTF8String];
	unsigned char result[16];
	CC_MD5( cStr, strlen(cStr), result );
	return [NSString stringWithFormat:
			@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
			result[0], result[1], result[2], result[3], 
			result[4], result[5], result[6], result[7],
			result[8], result[9], result[10], result[11],
			result[12], result[13], result[14], result[15]
			];	
}

-(unsigned int) indexOf:(char) searchChar inString: (NSString *)str {
	NSRange searchRange;
	searchRange.location=(unsigned int)searchChar;
	searchRange.length=1;
	NSRange foundRange = [str rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:searchRange]];
	return foundRange.location;
}

- (id) valueForProperty: (NSString *)propName inItem: (NSManagedObject *) item {
	
	id value;
	
	NSArray *keyComponents = [propName componentsSeparatedByString:@"."];
	if ([keyComponents count]>1) {
		NSManagedObject *subItem = [item valueForKey: [keyComponents objectAtIndex:0]];
		value = [subItem valueForKey: [keyComponents objectAtIndex:1]];
	}
	else {
		value = [item valueForKey:propName];
	}
	
	return value;
}

- (NSString *) distanceForProperty: (NSString *)propName inItem: (NSManagedObject *) item {
	
	NSString *ret = @"0.0km";
	
	NSArray *keyComponents = [propName componentsSeparatedByString:@"."];
	if ([keyComponents count]>1) {
		NSManagedObject *subItem = [item valueForKey: [keyComponents objectAtIndex:0]];
		
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSDictionary *dict = [defaults valueForKey:@"UD_LOCATION"];
		
		if (dict) {
			double latitude1 =  [[dict valueForKey:@"latitude"] doubleValue];
			double longitude1= [[dict valueForKey:@"longitude"] doubleValue];
			
			CLLocation *currentLocation = [[CLLocation alloc]init];
			[currentLocation initWithLatitude:latitude1 longitude:longitude1];
			
			double latitude2	=  [[subItem valueForKey:@"latitude"] doubleValue];
			double longitude2	=  [[subItem valueForKey:@"longitude"] doubleValue];
			
			CLLocation *thisLocation = [[CLLocation alloc]init];
			[thisLocation initWithLatitude:latitude2 longitude:longitude2];
			
			CLLocationDistance distance = [currentLocation getDistanceFrom:thisLocation];					
			ret = [NSString stringWithFormat:@"%.2fkm", distance/1000];
			
			[currentLocation release];
			[thisLocation release];
		}
	}	
	
	return ret;
}

- (NSManagedObject *)objectWithId: (NSString *)key andKind:(NSString *)kind inContext: (NSManagedObjectContext *)moc {
	
	NSManagedObject *ret = nil;
	NSEntityDescription *entityDescription = [NSEntityDescription entityForName:kind inManagedObjectContext: moc];
	
	NSFetchRequest *req = [[NSFetchRequest alloc] init];
	[req setEntity:entityDescription];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:
							  @"parabay_id = %@", key];
	[req setPredicate:predicate];
	
	NSError *error = nil;
	NSArray *array = [moc executeFetchRequest:req error:&error];
	if ((error != nil) || (array == nil)) {
		NSLog(@"Error while fetching\n%@", error);
	}
	
	if ([array count] > 0) {
		ret = [array objectAtIndex:0];
	}
	
	[req release];
	
	return ret;
}

- (void)dealloc {
	
	[super dealloc];
}

@end
