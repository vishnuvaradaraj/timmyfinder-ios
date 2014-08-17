//
//  EntityLocationModel.m
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-12-20.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "EntityLocationModel.h"
#import "ItemAnnotation.h" 
#import "ParabayAppDelegate.h"
#import "EntityListController.h"
#import "PostLocationController.h"
#import "AddressGeocoder.h"

static NSInteger compareManagedObjectLocation(id v1, id v2, void *context)
{
    static CLLocation *loc1 = nil;
	static CLLocation *loc2 = nil;

	CLLocation *referenceLocation = (CLLocation *)context;
	
	NSManagedObject *mo1 = (NSManagedObject *)v1;
	NSManagedObject *mo2 = (NSManagedObject *)v2;
	
	NSManagedObject *locItem1 = [mo1 valueForKey:@"Location"]; 
	NSManagedObject *locItem2 = [mo2 valueForKey:@"Location"]; 

	if (locItem1 && locItem2) {

		if (!loc1 || !loc2) {
			loc1 = [[CLLocation alloc]init];
			loc2 = [[CLLocation alloc]init];			
		}
		
		double latitude1 =  [[locItem1 valueForKey:@"latitude"] doubleValue];
		double longitude1= [[locItem1 valueForKey:@"longitude"] doubleValue];
		[loc1 initWithLatitude:latitude1 longitude:longitude1];

		double latitude2 =  [[locItem2 valueForKey:@"latitude"] doubleValue];
		double longitude2= [[locItem2 valueForKey:@"longitude"] doubleValue];
		[loc2 initWithLatitude:latitude2 longitude:longitude2];

		CLLocationDistance thisDistance = [loc1 getDistanceFrom:referenceLocation];
		CLLocationDistance thatDistance = [loc2 getDistanceFrom:referenceLocation];
		if (thisDistance < thatDistance) { return NSOrderedAscending; }
		if (thisDistance > thatDistance) { return NSOrderedDescending; }		
	}
	
	return NSOrderedSame;    
}

@implementation EntityLocationModel

@synthesize isUpdatingLocation, previousLocationHash, isFromActualSource, locationManager, persistentStoreCoordinator, insertionContext, locEntityDescription, currentLocation, entityListController, useMiles, query;

-(void) startUpdatingLocation {
	
	if (self.locationManager) {
		
		if (!isUpdatingLocation) {
			
			isUpdatingLocation = YES;
			[[self locationManager] startUpdatingLocation];			
		}
	}
}

-(void) stopUpdatingLocation {
	
	if (self.locationManager) {
		
		if (isUpdatingLocation) {
			
			isUpdatingLocation = NO;
			[[self locationManager] stopUpdatingLocation];			
		}
	}
}

-(NSInteger) optimalHashIndex: (CLLocationCoordinate2D) location {
	
	NSInteger ret = 0;
	
	for (NSInteger i=12; i>1; i--) {
		
		NSString *geoHash = [self calculateGeoHash:location];
		
		NSFetchRequest *req = [[NSFetchRequest alloc] init];
		[req setEntity: self.locEntityDescription];
		[req setFetchLimit:10];
		
		NSPredicate *predicate = [NSPredicate predicateWithFormat:
								  @"Location.geohash beginswith[c] %@", [geoHash substringToIndex: i]];
		[req setPredicate:predicate];
		
		NSError *dataError = nil;
		NSArray *array = [self.insertionContext executeFetchRequest:req error:&dataError];
		if ((dataError != nil) || (array == nil)) {
			NSLog(@"Error while fetching\n%@",
				  ([dataError localizedDescription] != nil)
				  ? [dataError localizedDescription] : @"Unknown Error");
		}
		
		if ([array count] >= 10) {
			ret = i;
			NSLog(@"Optimal hashIndex= %d for rows=%d", i, [array count]);
			break;
		}
	}
	
	return ret;
}

- (void)initWithListController: (EntityListController *)listController {
    
	self.isFromActualSource = NO;
	self.query = @"Location.geohash beginswith[c] %@";
	self.entityListController = listController;	
	[self startUpdatingLocation];
}

- (NSPredicate *) predicateForNearbyLocations {
	
	NSPredicate *predicate = nil;
	
	if (self.currentLocation.coordinate.latitude != 0 && self.currentLocation.coordinate.longitude != 0) {
		
		NSString *geoHash = [self calculateGeoHash:self.currentLocation.coordinate];
		NSInteger hashIndex = [self optimalHashIndex: self.currentLocation.coordinate];
		
		predicate = [NSPredicate predicateWithFormat:
						 @"Location.geohash beginswith[c] %@", [geoHash substringToIndex: hashIndex]];			
	}
	
	return predicate;
}

- (NSString *)calculateGeoHash: (CLLocationCoordinate2D) location {
	
	char geohash[32];
	
	geohash[0] = '\0';
	encode_geohash(location.latitude, location.longitude, 13, (char *)geohash);
	
	NSString *ret = [NSString stringWithCString:geohash encoding:NSASCIIStringEncoding]; 
	if ([[[UIDevice currentDevice] model] compare:@"iPhone Simulator"] == NSOrderedSame) {
		ret = @"dpwxr9k3qh8us"; 
	}
	
	return ret;
}

-(NSString *) distanceForItem: (NSManagedObject *) item {

	NSManagedObject *locItem = [item valueForKey:@"Location"]; 
	double latitude =  [[locItem valueForKey:@"latitude"] doubleValue];
	double longitude= [[locItem valueForKey:@"longitude"] doubleValue];
	
	double dist = calculateDistance( self.currentLocation.coordinate.latitude, self.currentLocation.coordinate.longitude, latitude, longitude, [self radiusOfEarth]);
	NSString *ret = [NSString stringWithFormat: (self.useMiles ? @"(%.2fmi)" : @"(%.2fkm)" ), dist];
	return ret;
}

- (BOOL) addAnnotationsForMapView: (MKMapView *)mapView {
	
	BOOL ret = YES;
	
	NSString *geoHash = [self calculateGeoHash:self.currentLocation.coordinate];
	NSInteger hashIndex = [self optimalHashIndex: self.currentLocation.coordinate];
	
	NSFetchRequest *req = [[NSFetchRequest alloc] init];
	[req setEntity: self.locEntityDescription];
	[req setFetchBatchSize: 100];
	[req setFetchLimit:100];
	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:
							  @"Location.geohash beginswith[c] %@", [geoHash substringToIndex: hashIndex]];
	[req setPredicate:predicate];
	
	NSError *dataError = nil;
	NSArray *array = [self.insertionContext executeFetchRequest:req error:&dataError];
	if ((dataError != nil) || (array == nil)) {
		NSLog(@"Error while fetching\n%@",
			  ([dataError localizedDescription] != nil)
			  ? [dataError localizedDescription] : @"Unknown Error");
	}
		
	NSLog(@"Found %d rows", [array count]);
	if ([array count]< 10) {
		NSLog(@"No annotations near: %@", geoHash);
		ret = NO;
	}
	
	NSArray *annotationArrs = mapView.annotations;
	if(annotationArrs!=nil) {
		[mapView removeAnnotations:annotationArrs];
	}	
	
	NSInteger annCount = 0;
	NSArray *sortedArray = [array sortedArrayUsingFunction:compareManagedObjectLocation context:self.currentLocation];
	
	for(NSManagedObject *item in sortedArray) {
		
		NSManagedObject *locItem = [item valueForKey:@"Location"]; 
		if (locItem) {
			
			CLLocationCoordinate2D coordinate = {0.0f, 0.0f}; // start in the ocean
			coordinate.latitude =  [[locItem valueForKey:@"latitude"] doubleValue];
			coordinate.longitude= [[locItem valueForKey:@"longitude"] doubleValue];
			
			ItemAnnotation *newAnnotation = (ItemAnnotation *)[ItemAnnotation annotationWithCoordinate:coordinate];
			NSString *title = [NSString stringWithFormat:@"%@ %@", [self distanceForItem:item], [item valueForKey:@"Title"]];
			newAnnotation.title = title;
			newAnnotation.key = [item valueForKey:@"parabay_id"];
			
			[mapView addAnnotation:newAnnotation];
			if (++annCount > 10) {
				break;
			}
		}
	}
	
	if (!self.isFromActualSource) {
		
		ItemAnnotation *newAnnotation = (ItemAnnotation *)[ItemAnnotation annotationWithCoordinate:self.currentLocation.coordinate];
		NSString *title = @"Current position";
		newAnnotation.isCurrentPosition = YES;
		newAnnotation.title = title;		
		[mapView addAnnotation:newAnnotation];		
	}
	
	[req release];
	
	return ret;
}

-(double) radiusOfEarth { 
	
	double ret = 6371;
	if (self.useMiles) {
		ret = 3963.19;
	}
	return ret;
}

- (void)updateCurrentLocation:(CLLocation *)location fromActualSource: (BOOL)isActual {
	
	BOOL updateLocation = YES;	
	NSString *locationHash = [self calculateGeoHash:location.coordinate];
	
	if (self.previousLocationHash) {
		
		if (self.isFromActualSource == isActual && 
				(NSOrderedSame == [self.previousLocationHash compare:locationHash])) {
			updateLocation = NO;
			NSLog(@"No change in location from update");
		}
	}
	else {
		self.previousLocationHash = locationHash;
		self.isFromActualSource = isActual;
	}

	if (updateLocation) {
		
		self.currentLocation = location;
		self.isFromActualSource = isActual;
		
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSDictionary *locDict = [NSDictionary dictionaryWithObjectsAndKeys: 
							  [NSNumber numberWithDouble: location.coordinate.latitude], @"latitude", 
							  [NSNumber numberWithDouble: location.coordinate.longitude], @"longitude", nil];
		[defaults setValue:locDict forKey:@"UD_LOCATION"];
		[defaults synchronize];
		
		NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
							  location, @"location", [NSNumber numberWithBool:isActual], @"isActual", nil];		
		[[NSNotificationCenter defaultCenter] postNotificationName:UserLocationChangedNotification object:nil userInfo:dict];
	}
}

- (CLLocation *)currentLocation {
	
	if (!currentLocation) {
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSDictionary *dict = [defaults valueForKey:@"UD_LOCATION"];
		
		if (dict) {
			double latitude =  [[dict valueForKey:@"latitude"] doubleValue];
			double longitude= [[dict valueForKey:@"longitude"] doubleValue];
			
			currentLocation = [[CLLocation alloc]init];
			[currentLocation initWithLatitude:latitude longitude:longitude];
			self.isFromActualSource  = NO;
			
 		}
	}
	return currentLocation;
}

-(void) showLocationPopup: (UIView *)inView {
	
	TTPostController *postController = [[[TTPostController alloc] init] autorelease];
	postController.title = @"Enter address";
	postController.delegate = self;
	[postController showInView:inView animated:YES];
}

- (void)postController:(TTPostController*)postController didPostText:(NSString*)text
			withResult:(id)result {
	
	[self showReverseGeocodingProgress:text];
	
}
	 
- (void) showReverseGeocodingProgress:(NSString *)address {
	
	UIWindow *window = [UIApplication sharedApplication].keyWindow;
	
	// Should be initialized with the windows frame so the HUD disables all user input by covering the entire screen
	HUD = [[MBProgressHUD alloc] initWithWindow:window];
	
	// Add HUD to screen
	[window addSubview:HUD];
	
	// Regisete for HUD callbacks so we can remove it from the window at the right time
	HUD.delegate = self;
	
	HUD.labelText = @"Loading";
	
	// Show the HUD while the provided method executes in a new thread
	[HUD showWhileExecuting:@selector(reverseGeocode:) onTarget:self withObject:address animated:YES];
	
}

- (void) reverseGeocode: (NSString *)address {
	
	CLLocationCoordinate2D coordinate = [AddressGeocoder locationOfAddress:address];
	CLLocation *location = [[CLLocation alloc] init];
	[location initWithLatitude:coordinate.latitude longitude:coordinate.longitude];
	
	[self updateCurrentLocation:location fromActualSource:NO];
	
}

- (void)hudWasHidden {
	// Remove HUD from screen when the HUD was hidded
	[HUD removeFromSuperview];
	[HUD release];
}

#pragma mark -
#pragma mark Location manager

/**
 Return a location manager -- create one if necessary.
 */
- (CLLocationManager *)locationManager {
	
    if (locationManager != nil) {
		return locationManager;
	}
	
	locationManager = [[CLLocationManager alloc] init];
	[locationManager setDesiredAccuracy:kCLLocationAccuracyHundredMeters];
	[locationManager setDelegate:self];
	
	return locationManager;
}


/**
 If the location manager is generating updates, then enable the button;
 If the location manager is failing, then disable the button.
 */
- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation {
	
	[self updateCurrentLocation: newLocation fromActualSource: YES];	
}


- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error {
	NSLog(@"Failed to get location: %@", [error localizedDescription]);
}

- (NSManagedObjectContext *)insertionContext {
	
    return [entityListController managedObjectContext];
}

- (NSEntityDescription *)locEntityDescription {
	
    if (locEntityDescription == nil) {
        locEntityDescription = [[NSEntityDescription entityForName: entityListController.entityMetadata inManagedObjectContext:self.insertionContext] retain];
    }
    return locEntityDescription;
}


- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
	
	if (persistentStoreCoordinator == nil) {
		ParabayAppDelegate *appDelegate = (ParabayAppDelegate *)[[UIApplication sharedApplication] delegate];
		persistentStoreCoordinator = appDelegate.persistentStoreCoordinator;
	}
	
	return persistentStoreCoordinator;
}

-(void)dealloc {
	
	if (locationManager) {
		[locationManager stopUpdatingLocation];
		locationManager.delegate = nil;
	}
	
	[super dealloc];
}

@end

// Convert our passed value to Radians
double ToRad( double nVal )
{
	return nVal * (M_PI/180);
}

/*
 Haversine Formula
 */
double calculateDistance( double nLat1, double nLon1, double nLat2, double nLon2, double radius )
{
	double nRadius = radius; // Earth's radius 
	
	// Get the difference between our two points then convert the difference into radians
	double nDLat = ToRad(nLat2 - nLat1);  
	double nDLon = ToRad(nLon2 - nLon1); 
	
	nLat1 =  ToRad(nLat1);
	nLat2 =  ToRad(nLat2);
	
	double nA =	pow ( sin(nDLat/2), 2 ) +
	cos(nLat1) * cos(nLat2) * 
	pow ( sin(nDLon/2), 2 );
	
	double nC = 2 * atan2( sqrt(nA), sqrt( 1 - nA ));
	double nD = nRadius * nC;
	
	return nD; // Return our calculated distance
}

/*
 Geohash
 */
#define BASE32	"0123456789bcdefghjkmnpqrstuvwxyz"

void decode_geohash_bbox(char *geohash, double *lat, double *lon) {
	int i, j, hashlen;
	double lat_err, lon_err;
	char c, cd, mask, is_even=1;
	static char bits[] = {16,8,4,2,1};
	
	lat[0] = -90.0;  lat[1] = 90.0;
	lon[0] = -180.0; lon[1] = 180.0;
	lat_err = 90.0;  lon_err = 180.0;
	hashlen = strlen(geohash);
	
	for (i=0; i<hashlen; i++) {
		c = tolower(geohash[i]);
		cd = strchr(BASE32, c)-BASE32;
		for (j=0; j<5; j++) {
			mask = bits[j];
			if (is_even) {
				lon_err /= 2;
				lon[!(cd&mask)] = (lon[0] + lon[1])/2;
			} else {
				lat_err /= 2;
				lat[!(cd&mask)] = (lat[0] + lat[1])/2;
			}
			is_even = !is_even;
		}
	}
}

void decode_geohash(char *geohash, double *point) {
	double lat[2], lon[2];
	
	decode_geohash_bbox(geohash, lat, lon);
	
	point[0] = (lat[0] + lat[1]) / 2;
	point[1] = (lon[0] + lon[1]) / 2;
}

void encode_geohash(double latitude, double longitude, int precision, char *geohash) {
	int is_even=1, i=0;
	double lat[2], lon[2], mid;
	char bits[] = {16,8,4,2,1};
	int bit=0, ch=0;
	
	lat[0] = -90.0;  lat[1] = 90.0;
	lon[0] = -180.0; lon[1] = 180.0;
	
	while (i < precision) {
		if (is_even) {
			mid = (lon[0] + lon[1]) / 2;
			if (longitude > mid) {
				ch |= bits[bit];
				lon[0] = mid;
			} else
				lon[1] = mid;
		} else {
			mid = (lat[0] + lat[1]) / 2;
			if (latitude > mid) {
				ch |= bits[bit];
				lat[0] = mid;
			} else
				lat[1] = mid;
		}
		
		is_even = !is_even;
		if (bit < 4)
			bit++;
		else {
			geohash[i++] = BASE32[ch];
			bit = 0;
			ch = 0;
		}
	}
	geohash[i] = 0;
}

void get_neighbor(char *str, int dir, int hashlen)
{
	/* Right, Left, Top, Bottom */
	
	static char *neighbors[] = { "bc01fg45238967deuvhjyznpkmstqrwx",
		"238967debc01fg45kmstqrwxuvhjyznp",
		"p0r21436x8zb9dcf5h7kjnmqesgutwvy",
		"14365h7k9dcfesgujnmqp0r2twvyx8zb" };
	
	static char *borders[] = { "bcfguvyz", "0145hjnp", "prxz", "028b" };
	
	char last_chr, *border, *neighbor;
	int index = ( 2 * (hashlen % 2) + dir) % 4;
	neighbor = neighbors[index];
	border = borders[index];
	last_chr = str[hashlen-1];
	if (strchr(border,last_chr))
		get_neighbor(str, dir, hashlen-1);
	str[hashlen-1] = BASE32[strchr(neighbor, last_chr)-neighbor];
}

