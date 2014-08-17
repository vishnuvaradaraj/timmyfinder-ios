//
//  EntityDetailsController.h
//  Parabay
//
//  Created by Vishnu Varadaraj on 19/08/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Three20/Three20.h"
#import "Globals.h"

@class PageData;

@interface EntityDetailsDelegate: TTTableViewVarHeightDelegate  {
	UIView *footerView;
	BOOL isReadOnly;
}
@property (nonatomic) BOOL isReadOnly;

@end

@interface EntityDetailsController : TTTableViewController<UIAlertViewDelegate,EntitySelectionDelegate> {
	NSManagedObject *item;
	
	NSString *pageName;
	PageData *pageData;
	
	NSMutableDictionary *propertyEditors;
	NSManagedObjectContext *managedObjectContext;
	NSEntityDescription *entityDescription;
	BOOL isReadOnly;
	
	UIToolbar	*toolbar;
	NSMutableArray *toolbarItems;
	
	NSDictionary *queryParams;
}

@property (nonatomic, retain) NSManagedObject *item;

@property (nonatomic, retain) NSString *pageName;
@property (nonatomic, retain) PageData *pageData;
@property (nonatomic, retain) NSMutableDictionary *propertyEditors;
@property (nonatomic, retain, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, retain, readonly) NSEntityDescription *entityDescription;

@property (nonatomic) BOOL isReadOnly;

@property (nonatomic, retain) UIToolbar	*toolbar;
@property (nonatomic, retain) NSMutableArray *toolbarItems;

@property (nonatomic, retain) NSDictionary *queryParams;

- (void)edit:(id)sender;
- (NSManagedObject *)itemWithKey: (NSString *)name;
- (void)setItem:(NSManagedObject*)aValue;
- (id)initWithViewMap:(NSString*)name query:(NSDictionary*)query;
- (void)processDelete;

@end
