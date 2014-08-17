//
//  LoadLocationService.h
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-11-24.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BaseService.h"

@interface LoadLocationService : BaseService {
	
	NSEntityDescription *locEntityDescription;
	
}

@property (nonatomic, retain, readonly) NSEntityDescription *locEntityDescription;

- (BOOL) sendLoadRequest;

@end