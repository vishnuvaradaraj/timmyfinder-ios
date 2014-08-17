//
//  SaveFileService.h
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-12-06.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BaseService.h"

@interface SaveFileService : BaseService<TTURLRequestDelegate, TTURLResponse> {
	
	NSManagedObject *item;
	NSEntityDescription *imgEntityDescription;	
}

@property (nonatomic, retain, readonly) NSEntityDescription *imgEntityDescription;
@property (nonatomic, retain) NSManagedObject *item;

- (BOOL) sendSaveRequest;
- (void)sendRequest: (NSString *)path withParameters: (NSDictionary *)parameters;

@end

