//
//  SaveLocationService.h
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-12-19.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BaseService.h"

@interface SaveLocationService : BaseService {
	
	NSMutableArray *items;
	NSArray *results;
	NSEntityDescription *locEntityDescription;
}

@property (nonatomic, retain) NSMutableArray *items;
@property (nonatomic, retain) NSArray *results;
@property (nonatomic, retain, readonly) NSEntityDescription *locEntityDescription;

- (BOOL)sendSaveRequest;
- (NSMutableDictionary *) convertLocationManagedObjectToDictionary:(NSManagedObject *)loc;

@end
