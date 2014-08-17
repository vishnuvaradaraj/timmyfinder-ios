//
//  PageData.m
//  Parabay
//
//  Created by Vishnu Varadaraj on 09-10-04.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "PageData.h"
#import "MetadataService.h"
#import "JSON.h"

@implementation PageData

@synthesize entityRelations, pageName, editorPageName, listPageMetadata, editorPageMetadata, listLayoutStr, editorLayoutStr, listLayout, editorLayout, defaultEntityName, dataQuery, defaultEntityMetadata, defaultEntityProperties, reportLayoutStr, reportLayout;

-(void) loadPageData {
	
	self.listPageMetadata = [[MetadataService sharedInstance] getPageMetadata: pageName];	
	NSDictionary *listViewDef = [listPageMetadata objectForKey:@"view_definition"];	
	self.listLayoutStr = [listViewDef valueForKey:@"mobile_layout"];
	self.listLayout = [[listLayoutStr JSONValue] copy];
	
	self.editorPageMetadata = [[MetadataService sharedInstance] getPageMetadata: editorPageName];
	NSDictionary *editorViewDef = [editorPageMetadata objectForKey:@"view_definition"];	
	self.editorLayoutStr = [editorViewDef valueForKey:@"mobile_layout"];
	//NSLog(@"Editor layout: %@", editorLayoutStr);
	self.editorLayout = [[editorLayoutStr JSONValue] copy];
		
	self.reportLayoutStr = [listViewDef valueForKey:@"report_layout"];
	if (self.reportLayoutStr && ([NSNull null] != (NSNull *)self.reportLayoutStr)) {
		//NSLog(@"Editor layout: %@", editorLayoutStr);
		self.reportLayout = [[self.reportLayoutStr JSONValue] copy];
	}
	
	self.defaultEntityName = [[listViewDef objectForKey:@"default_entity"] copy];
	self.defaultEntityProperties = [[NSMutableDictionary alloc] init];
	self.entityRelations = [[NSMutableDictionary alloc] init];
	
	NSArray *dataQueries = [listPageMetadata valueForKey:@"data_queries"];
	for(NSDictionary *result in dataQueries) {   
		
		NSString *dqName = [result objectForKey:@"name"];
		self.dataQuery = [[[MetadataService sharedInstance] getDataQuery:dqName] copy];	
		
		NSArray *entityMetadatas = [dataQuery objectForKey:@"entity_metadatas"];	
		for(NSDictionary *em in entityMetadatas) {   
			
			NSString *entityName = [em objectForKey:@"name"];
			if (NSOrderedSame == [entityName compare:self.defaultEntityName]) {
				
				NSArray *entityPropertyMetadatas = [em objectForKey:@"entity_property_metadatas"];	
				for(NSDictionary *ep in entityPropertyMetadatas) {   
					
					NSString *propertyName = [[ep objectForKey:@"name"] copy]; 
					[self.defaultEntityProperties setObject:[ep copy] forKey:propertyName];
				}
				break;
			}
			
		}
		
		NSArray *entityRelationsArr = [dataQuery objectForKey:@"entity_relations"];
		for(NSDictionary *er in entityRelationsArr) {
			
			NSString *relName = [er objectForKey:@"name"];
			[self.entityRelations setObject:er forKey:relName];				
		}
	}		
}

-(NSString *) description {
	return [NSString stringWithFormat:@"listPageMetadata=%@, editorPageMetadata=%@, properties=%@\n",
			listPageMetadata, editorPageMetadata, defaultEntityProperties];
}

@end
