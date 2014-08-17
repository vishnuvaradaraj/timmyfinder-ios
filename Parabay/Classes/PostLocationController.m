//
//  PostLocationController.m
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-12-23.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "PostLocationController.h"
#import "AddressGeocoder.h"
#import <MapKit/MapKit.h>

@implementation PostLocationController

- (BOOL)willPostText:(NSString*)text {
	return YES;
}

- (NSString*)titleForActivity {
	return @"Reverse geocoding...";
}


@end
