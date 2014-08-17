//
//  PostLocationController.h
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-12-23.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Three20/Three20.h"

@class CLLocationManager;

@interface PostLocationController : TTPostController {

	CLLocationManager *locationManager;
}

@end
