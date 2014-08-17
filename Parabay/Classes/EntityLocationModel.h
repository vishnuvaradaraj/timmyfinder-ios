//
//  EntityLocationModel.h
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-12-20.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "Three20/Three20.h"
#import "MBProgressHUD.h"

@class EntityListController;

@interface EntityLocationModel : NSObject<CLLocationManagerDelegate, TTPostControllerDelegate, MBProgressHUDDelegate> {

	CLLocationManager *locationManager;
	EntityListController * entityListController;
	
	BOOL isFromActualSource;
	CLLocation *currentLocation;
	
	NSPersistentStoreCoordinator *persistentStoreCoordinator;
	NSManagedObjectContext *insertionContext;
	NSEntityDescription *locEntityDescription;	
	
	NSString *query;
	BOOL useMiles;
	
	NSString *previousLocationHash;
	BOOL isUpdatingLocation;
	
	MBProgressHUD *HUD;
	
}

@property (nonatomic, retain) CLLocationManager *locationManager;
@property (nonatomic, retain) EntityListController * entityListController;
@property (nonatomic, retain) CLLocation *currentLocation;

@property (nonatomic, retain, readonly) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (nonatomic, retain, readonly) NSManagedObjectContext *insertionContext;
@property (nonatomic, retain, readonly) NSEntityDescription *locEntityDescription;

@property (nonatomic, retain) NSString *query;
@property (nonatomic) BOOL useMiles;
@property (nonatomic) BOOL isFromActualSource;
@property (nonatomic, retain) NSString *previousLocationHash;
@property (nonatomic) BOOL isUpdatingLocation;

- (void)updateCurrentLocation:(CLLocation *)location  fromActualSource: (BOOL)isActual;
-(NSString *) distanceForItem: (NSManagedObject *) item;
- (NSPredicate *) predicateForNearbyLocations;
- (void)initWithListController: (EntityListController *)listController;
- (BOOL) addAnnotationsForMapView: (MKMapView *)mapView;

-(NSInteger) optimalHashIndex: (CLLocationCoordinate2D) location ;
- (NSString *)calculateGeoHash: (CLLocationCoordinate2D) location;
-(double) radiusOfEarth;
-(void) showLocationPopup: (UIView *)inView;

-(void) startUpdatingLocation;
-(void) stopUpdatingLocation;

- (void) showReverseGeocodingProgress:(NSString *)address;

@end

double calculateDistance( double nLat1, double nLon1, double nLat2, double nLon2, double radius );
void encode_geohash(double latitude, double longitude, int precision, char *geohash);
