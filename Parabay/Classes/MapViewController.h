//
//  MapViewController.h
//  Parabay
//
//  Created by Vishnu Varadaraj on 01/09/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "Three20/Three20.h"

@class EntityLocationModel;

@interface MapViewController : TTViewController<MKMapViewDelegate, UIActionSheetDelegate> {

	MKMapView *mapView;
	UIToolbar	*toolbar;
	NSMutableArray *toolbarItems;
	
	UIBarButtonItem *refreshButtonItem;
	UIBarButtonItem *statusButtonItem;	
	
	EntityLocationModel *locationModel;
}

@property (nonatomic, retain) MKMapView *mapView;
@property (nonatomic, retain) UIToolbar	*toolbar;
@property (nonatomic, retain) NSMutableArray *toolbarItems;

@property (nonatomic, retain) UIBarButtonItem *refreshButtonItem;
@property (nonatomic, retain) UIBarButtonItem *statusButtonItem;

@property (nonatomic, retain) EntityLocationModel *locationModel;

- (void)recenterMap;
- (void)zoomToLocation: (CLLocation *)location;
- (void)setCurrentLocation:(CLLocation *)location;

- (void) refreshLocation:(id)sender;
- (void) showCurrentLocation:(id)sender;

@end
