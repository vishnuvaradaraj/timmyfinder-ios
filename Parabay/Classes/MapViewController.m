//
//  MapViewController.m
//  Parabay
//
//  Created by Vishnu Varadaraj on 01/09/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "MapViewController.h"
#import "ItemAnnotation.h" 
#import "ParabayAppDelegate.h"
#import "EntityLocationModel.h"
#import "Reachability.h"

@implementation MapViewController

@synthesize mapView, toolbar, toolbarItems, refreshButtonItem, statusButtonItem, locationModel;


- (void)viewDidLoad {
    
	[super viewDidLoad];
	self.title = @"Map";
	
	self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
	self.mapView.showsUserLocation = NO;
	
	self.mapView.mapType = MKMapTypeStandard;
	self.mapView.delegate = self;
	
	//Create the segmented control
	NSArray *mapItemArray = [NSArray arrayWithObjects: @"Map", @"Satellite", @"Hybrid", nil];
	UISegmentedControl *mapSegmentedControl = [[UISegmentedControl alloc] initWithItems:mapItemArray];
	//mapSegmentedControl.frame = CGRectMake(5, 130, 150, 30);
	mapSegmentedControl.segmentedControlStyle = UISegmentedControlStyleBar;
	mapSegmentedControl.selectedSegmentIndex = 0;
	[mapSegmentedControl addTarget:self
						 action:@selector(pickOne:)
			   forControlEvents:UIControlEventValueChanged];
	
	// create the UIToolbar at the bottom of the view controller
	//
	self.toolbar = [UIToolbar new];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSInteger theme = [defaults integerForKey:@"theme_preference"];
	
	if (theme == 2) {			
		toolbar.barStyle = UIBarStyleBlackTranslucent;
	}
	
	// size up the toolbar and set its frame
	[toolbar sizeToFit];
	CGFloat toolbarHeight = [toolbar frame].size.height;
	CGRect mainViewBounds = self.view.bounds;
	[toolbar setFrame:CGRectMake(CGRectGetMinX(mainViewBounds),
								 CGRectGetMinY(mainViewBounds) + CGRectGetHeight(mainViewBounds) - (toolbarHeight) + 2.0,
								 CGRectGetWidth(mainViewBounds),
								 toolbarHeight)];
	
	//Create the segmented control
	NSArray *itemArray = [NSArray arrayWithObjects: @"List", @"Map", nil];
	UISegmentedControl *segmentedControl = [[UISegmentedControl alloc] initWithItems:itemArray];
	segmentedControl.frame = CGRectMake(5, 130, 150, 30);
	segmentedControl.segmentedControlStyle = UISegmentedControlStyleBar;
	segmentedControl.selectedSegmentIndex = 1;
	[segmentedControl addTarget:self
						 action:@selector(pickOneView:)
			   forControlEvents:UIControlEventValueChanged];
	
	self.refreshButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"location.png"] style:UIBarButtonItemStyleBordered 
																		   target:self action:@selector(showCurrentLocation:)];
	self.statusButtonItem = [[UIBarButtonItem alloc] initWithCustomView:segmentedControl];		
	
	self.toolbarItems = [NSMutableArray arrayWithObjects:	self.refreshButtonItem, 
						 [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
																	   target:nil  action:nil],
						 statusButtonItem,
						 [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
																	   target:nil  action:nil],
						 [[UIBarButtonItem alloc] initWithTitle:@"Move to" style:UIBarButtonItemStyleBordered 
														 target:self action:@selector(pickCurrentLocation:)],
						 nil];
	
	NetworkStatus status = [[Reachability sharedReachability] internetConnectionStatus];
	if (NotReachable == status) {
		[self.toolbarItems removeObjectAtIndex: 0];
	}
	
	[self.toolbar setItems:self.toolbarItems animated:NO];
	
	[self.view insertSubview:mapView atIndex:0];
	[self.view insertSubview:mapSegmentedControl atIndex:1];
	[self.view addSubview:toolbar];
	
	self.navigationItem.rightBarButtonItem =[[UIBarButtonItem alloc] initWithTitle:@"Refresh" style:UIBarButtonItemStyleDone target:self action:@selector(refreshLocation:)];
											 
	if (self.locationModel) {
		[self.locationModel startUpdatingLocation];
		//[self setCurrentLocation:self.locationModel.currentLocation];
	}	
}

- (void) refreshLocation:(id)sender{

	self.navigationItem.rightBarButtonItem.enabled = NO;
	[self.locationModel startUpdatingLocation];
	
}

- (void) showCurrentLocation:(id)sender{
	
	[self zoomToLocation:self.locationModel.currentLocation];
}

- (void)userLocationChanged:(NSNotification *)aNotification {
	
	NSLog(@"User location changed");
	
	if ([NSThread isMainThread]) {
		
		BOOL isActualSource = NO;
		NSNumber *isActualSourceValue = [[aNotification userInfo] valueForKey:@"isActual"];
		if (isActualSourceValue) {
			isActualSource = [isActualSourceValue boolValue];
		}
		
		if ([[[UIDevice currentDevice] model] compare:@"iPhone Simulator"] != NSOrderedSame) {
			self.mapView.showsUserLocation = isActualSource;
		}
		
		CLLocation *location = [[aNotification userInfo] valueForKey:@"location"];	
		[self setCurrentLocation: location];
		
		self.navigationItem.rightBarButtonItem.enabled = YES;

	} else {
		[self performSelectorOnMainThread:@selector(userLocationChanged:) withObject:aNotification waitUntilDone:NO];
		
	}	


}

- (void) pickOne:(id)sender{
	
	UISegmentedControl *segmentedControl = (UISegmentedControl *)sender;
	NSLog(@"Selected segment: %@", [segmentedControl titleForSegmentAtIndex: [segmentedControl selectedSegmentIndex]]);
	
	NSInteger selIndex = [segmentedControl selectedSegmentIndex];
	if (selIndex == 0) {
		mapView.mapType = MKMapTypeStandard;
	}
	else if (selIndex == 1) {
		mapView.mapType = MKMapTypeSatellite;
	}
	else if (selIndex == 2) {
		mapView.mapType = MKMapTypeHybrid;
	}

} 

- (void) pickOneView:(id)sender{

	UISegmentedControl *segmentedControl = (UISegmentedControl *)sender;
	
	if (segmentedControl.selectedSegmentIndex == 0) {
		segmentedControl.selectedSegmentIndex = 1;
	
		[self.navigationController popViewControllerAnimated:YES];
	}
} 

- (void)viewWillAppear:(BOOL)animated {
	
	[super viewWillAppear:animated];	
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSInteger theme = [defaults integerForKey:@"theme_preference"];
	
	if (theme == 2) {
		UIApplication* app = [UIApplication sharedApplication];
		[app setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:NO];
		
		self.navigationController.navigationBar.tintColor = [UIColor 
															 blackColor]; 			
	}
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userLocationChanged:) name:UserLocationChangedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userLocationChanged:) name:UserLocationErrorNotification object:nil];
	
}

- (void) viewDidAppear:(BOOL)animated {

	[super viewDidAppear:animated];
	
	if(self.mapView.annotations.count > 1) {
		[self recenterMap];
	}	
}

-(void) viewDidDisappear:(BOOL)animated {
	
	[super viewDidDisappear:animated];
	
	[self.locationModel stopUpdatingLocation];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UserLocationChangedNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UserLocationErrorNotification object:nil];
}

- (void)setCurrentLocation:(CLLocation *)location{
		
	if (self.locationModel) {
		[self.locationModel addAnnotationsForMapView:self.mapView];		
	}
	
	if(self.mapView.annotations.count > 1) {
		[self recenterMap];
	}	
	else {
		[self zoomToLocation:location];
	}
	
	self.mapView.showsUserLocation = self.locationModel.isFromActualSource;
}

- (void)zoomToLocation: (CLLocation *)location {
	
	MKCoordinateRegion region = {{0.0f, 0.0f}, {0.0f, 0.0f}};
	region.center = location.coordinate;
	region.span.longitudeDelta = 0.15f;
	region.span.latitudeDelta = 0.15f;
	[self.mapView setRegion:region animated:YES];
}

- (void)recenterMap {
	
	NSArray *coordinates = [mapView valueForKeyPath:@"annotations.coordinate"];
	
	CLLocationCoordinate2D maxCoord = {-90.0f, -180.0f};
	CLLocationCoordinate2D minCoord = {90.0f, 180.0f};
	for(NSValue *value in coordinates) {
		CLLocationCoordinate2D coord = {0.0f, 0.0f};
		[value getValue:&coord];
		if(coord.longitude > maxCoord.longitude) {
			maxCoord.longitude = coord.longitude;
		}
		if(coord.latitude > maxCoord.latitude) {
			maxCoord.latitude = coord.latitude;
		}
		if(coord.longitude < minCoord.longitude) {
			minCoord.longitude = coord.longitude;
		}
		if(coord.latitude < minCoord.latitude) {
			minCoord.latitude = coord.latitude;
		}
	}
	MKCoordinateRegion region = {{0.0f, 0.0f}, {0.0f, 0.0f}};
	region.center.longitude = (minCoord.longitude + maxCoord.longitude) / 2.0;
	region.center.latitude = (minCoord.latitude + maxCoord.latitude) / 2.0;
	region.span.longitudeDelta = maxCoord.longitude - minCoord.longitude;
	region.span.latitudeDelta = maxCoord.latitude - minCoord.latitude;
	
	[self.mapView setRegion:region animated:YES];
}

#pragma mark Map View Delegate Methods

- (MKAnnotationView *)mapView:(MKMapView *)mView 
            viewForAnnotation:(id <MKAnnotation>)annotation {
	
	MKPinAnnotationView *view = nil; // return nil for the current user location
	if(annotation != mView.userLocation) {
		
		ItemAnnotation *annItem = nil;
		if ([annotation isKindOfClass:[ItemAnnotation class]]) {
			annItem = (ItemAnnotation *)annotation;
		}
		
		view = (MKPinAnnotationView *)[mView
									   dequeueReusableAnnotationViewWithIdentifier:@"identifier"];
		if(nil == view) {
			view = [[[MKPinAnnotationView alloc]
					 initWithAnnotation:annotation reuseIdentifier:@"identifier"]
					autorelease];
			view.rightCalloutAccessoryView = 
			[UIButton buttonWithType:UIButtonTypeDetailDisclosure];
		}
		if (annItem && annItem.isCurrentPosition) {
			[view setPinColor:MKPinAnnotationColorRed];
		}
		else {
			[view setPinColor:MKPinAnnotationColorGreen];
			[view setCanShowCallout:YES];			
		}

		[view setAnimatesDrop:YES];
	} 
	/*else {
		CLLocation *location = [[CLLocation alloc] 
								initWithLatitude:annotation.coordinate.latitude
								longitude:annotation.coordinate.longitude];
		[self setCurrentLocation:location];
	}*/
	return view;
}

- (void)mapView:(MKMapView *)mapView 
 annotationView:(MKAnnotationView *)view
calloutAccessoryControlTapped:(UIControl *)control {
	
	ItemAnnotation *ann = (ItemAnnotation *)view.annotation;
	
	NSString *pageName = @"Timmy_Stores";
	NSString *name = ann.key;
	NSString *url = [NSString stringWithFormat:@"tt://home/view/%@?id=%@", [pageName substringToIndex:([pageName length]-1) ], name ];
	
	NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:name, @"id", nil];
	[[TTNavigator navigator] openURL:url query:query animated:YES];
		
}

- (void)mapView:(MKMapView *)mapView // there is a bug in the map view in beta 5
// that makes this method required, the map view is nto checking if we 
// respond before invoking so it blows up if we don't
didSelectSearchResult:(id)result
  userInitiated:(BOOL)userInitiated {
}

-(void)pickCurrentLocation:(id)sender {
		
	NetworkStatus status = [[Reachability sharedReachability] internetConnectionStatus];
	if (NotReachable != status) {
		[self.locationModel stopUpdatingLocation];
		[self.locationModel showLocationPopup:self.view];
	}
}


- (void) dealloc {
	
	[super dealloc];
}

@end

