//
//  LoadDataQuery.m
//  LoginApp
//
//  Created by Vishnu Varadaraj on 16/08/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "LoadDataQuery.h"
#import "JSON.h"

@implementation LoadDataQuery

- (void)loadData:(NSDictionary *)json
{
	TTLOG(@"Loaded dataQuery.");
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
						  [NSNumber numberWithInt:0], @"status", [json JSONRepresentation], @"value", name, @"key", nil];
	[[NSNotificationCenter defaultCenter] postNotificationName: doneNotification object:nil userInfo:dict];				
}

@end
