//
//  EntityListController.m
//  Parabay
//
//  Created by Vishnu Varadaraj on 19/08/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "EntityListController.h"
#import <AVFoundation/AVFoundation.h>
#import "EntityDetailsController.h"
#import "ParabayAppDelegate.h"
#import "Globals.h"
#import "MetadataService.h"
#import "PageData.h"
#import "JSON.h"
#import "Reachability.h"
#import <objc/runtime.h>
#import "LoadDataService.h"
#import "LoadLocationService.h"
#import "SaveService.h"
#import "DeleteService.h"
#import "LoadFileService.h"
#import "SaveFileService.h"
#import "EntityLocationModel.h"
#import "MapViewController.h"

#define SAFE_PROPERTY_VALUE(__VALUE) ( (__VALUE) ? __VALUE: @"")
#define TRIM_STR_VALUE(__VALUE, __TRIM) ( ([__VALUE isKindOfClass:[NSString class]] && [__VALUE length] > __TRIM) ? [NSString stringWithFormat:@"%@...", [__VALUE substringToIndex: __TRIM]] : __VALUE)

static NSTimeInterval const kRefreshTimeInterval = 3600;

@implementation EntityListController

@synthesize managedObjectContext, fetchedResultsController, tableView, pageName, pageData, editController, pageMetadata, layout, propertyMetadatas, searchController, searchResultsController, searchFields, privateQueue;
@synthesize mobileLayout, entityMetadata, cellType, sectionKeyPath, sortDescList, toolbar, toolbarItems, statusButtonItem, activityButtonItem, refreshButtonItem, timer, isReadOnly, searchTerm, indexField;
@synthesize selectionDelegate, sectionIndexes, isMultiSelect, selectedItems, isSearchMode, locationModel, mapViewController, loadData, shareData, useLocation;
@synthesize isSingleSelect, multiSelectionButtonTitle, dismissOnSelection, parentId, useFile, saveData, relationPrivateQueue;

- (void) initMetadata {

	self.searchTerm = nil;
	self.pageData = [[MetadataService sharedInstance] getPageData:pageName forEditorPage:nil ];
	
	self.selectedItems = [[NSMutableDictionary alloc] initWithCapacity:255];
	self.sectionIndexes = [[NSMutableDictionary alloc] initWithCapacity:255];
	
	self.sectionKeyPath = PB_SAFE_COPY([pageData.listLayout objectForKey:@"sectionKeyPath"]);
	self.sortDescList = [pageData.listLayout objectForKey:@"sortDescriptors"];
	
	if (!sectionKeyPath || [sectionKeyPath length]==0)  {
		sectionKeyPath = nil;
	}

	if (!sortDescList || [sortDescList count] ==0 ) {
		sortDescList = [NSArray arrayWithObjects: @"name", nil];
	}
	sortDescList = [sortDescList copy];
	
	self.entityMetadata = pageData.defaultEntityName;
	self.pageMetadata = pageData.listPageMetadata;
	self.mobileLayout = pageData.listLayout;
	self.propertyMetadatas = pageData.defaultEntityProperties;
	
	self.cellType = PB_SAFE_COPY([pageData.listLayout objectForKey:@"panel"]);
	self.indexField = PB_SAFE_COPY([pageData.listLayout objectForKey:@"indexfield"]);
	
	NSLog(@"List Layout=%@", self.mobileLayout);
	
	self.isReadOnly = NO;
	NSNumber *readOnly = [pageData.listLayout objectForKey:@"readonly"];
	if (readOnly)  {
		self.isReadOnly = [readOnly boolValue];
	}
	
	self.loadData = NO;
	NSNumber *loadDataSetting = [pageData.listLayout objectForKey:@"loaddata"];
	if (loadDataSetting)  {
		self.loadData = [loadDataSetting boolValue];
	}
	
	self.shareData = NO;
	NSNumber *shareDataSetting = [pageData.listLayout objectForKey:@"sharedata"];
	if (shareDataSetting)  {
		self.shareData = [shareDataSetting boolValue];
	}
	
	self.useLocation = NO;
	NSNumber *locationSetting = [pageData.listLayout objectForKey:@"uselocation"];
	if (locationSetting)  {
		self.useLocation = [locationSetting boolValue];
	}

	self.useFile = NO;
	NSNumber *fileSetting = [pageData.listLayout objectForKey:@"usefile"];
	if (fileSetting)  {
		self.useFile = [fileSetting boolValue];
	}
	
	self.saveData = YES;
	NSNumber *saveDataSetting = [pageData.listLayout objectForKey:@"savedata"];
	if (saveDataSetting)  {
		self.saveData = [saveDataSetting boolValue];
	}
	
	if (self.useLocation) {
		
		self.locationModel = [[EntityLocationModel alloc]init];
		[self.locationModel initWithListController:self];		
	}
}

- (void)didReceiveMemoryWarning   
{  
	NSLog(@"ListView:didReceiveMemoryWarning");
    [super didReceiveMemoryWarning];  
} 

- (id)initWithViewMap:(NSString*)name query:(NSDictionary*)query {

	if (self = [super init]) {
				
		NSLog(@"ListView:init(%@), query=%@", name, query);
		self.pageName = name;				
				
		self.parentId = [query valueForKey:@"parentId"];
		
		NSString *selectMode = [query valueForKey:@"selectMode"];
		if (selectMode) {
			if (NSOrderedSame == [selectMode compare:@"multi"]) {
				self.isMultiSelect = YES;
				
				self.multiSelectionButtonTitle = [query valueForKey:@"actionButton"];		
				if (!self.multiSelectionButtonTitle) {
					self.multiSelectionButtonTitle = @"Send";
				}
			}
			else if (NSOrderedSame == [selectMode compare:@"single"]) {
				self.isSingleSelect = YES;
			}
		}
													
		NSNumber *dismissOnSel = [query valueForKey:@"dismissOnSelection"];
		if (dismissOnSel) {
		  self.dismissOnSelection = [dismissOnSel boolValue];
		}
						
		NSString *selDelegate = [query valueForKey:@"selectionDelegate"];
		if (selDelegate) {
			self.selectionDelegate = [[TTNavigator navigator] objectForPath:selDelegate];
		}
		
		ParabayAppDelegate *delegate = (ParabayAppDelegate *) [[UIApplication sharedApplication] delegate];
		self.managedObjectContext = [delegate managedObjectContext];
		
		[self initMetadata];
		
		// Create the tableview.
		self.view = [[[UIView alloc] initWithFrame:TTApplicationFrame()] autorelease];
		self.tableView = [[[UITableView alloc] initWithFrame:TTApplicationFrame() style:UITableViewStylePlain] autorelease];
		self.tableView.delegate = self;
		self.tableView.dataSource = self;
		//self.variableHeightRows = YES;  
		self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[self.view addSubview:self.tableView];
		
		NSArray *nameComponents = [name componentsSeparatedByString:@"_"];
		self.title = [nameComponents objectAtIndex:1];
		
		NSString *heading = [self.pageData.listLayout valueForKey:@"heading"];
		if (heading) {
			self.title = heading;
		}
		
		if (!self.isReadOnly) {
			self.navigationItem.rightBarButtonItem =[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add:)];
		}
		
		// create the UIToolbar at the bottom of the view controller
		//
		toolbar = [UIToolbar new];
		
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
									 CGRectGetMinY(mainViewBounds) + CGRectGetHeight(mainViewBounds) - (toolbarHeight * 2.0) + 2.0,
									 CGRectGetWidth(mainViewBounds),
									 toolbarHeight)];
		
		UILabel* label = [[[UILabel alloc] init] autorelease];
		label.font = [UIFont systemFontOfSize:12];
		label.backgroundColor = [UIColor clearColor];
		label.textColor = [UIColor whiteColor];
		label.shadowColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:.35];
		label.shadowOffset = CGSizeMake(0, -1.0);		
		
		TTActivityLabel* activity = [[[TTActivityLabel alloc] initWithStyle:TTActivityLabelStyleWhite] autorelease];
		activity.text = @"Loading...";
		activity.width = 120;
		[activity sizeToFit];		
		
		//Create the segmented control
		NSArray *itemArray = [NSArray arrayWithObjects: @"List", @"Map", nil];
		UISegmentedControl *segmentedControl = [[UISegmentedControl alloc] initWithItems:itemArray];
		segmentedControl.frame = CGRectMake(5, 130, 150, 30);
		segmentedControl.segmentedControlStyle = UISegmentedControlStyleBar;
		segmentedControl.selectedSegmentIndex = 0;
		[segmentedControl addTarget:self
							 action:@selector(pickOne:)
				   forControlEvents:UIControlEventValueChanged];
		
		self.refreshButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
																			   target:self action:@selector(popupActionSheet:)];
		if (self.useLocation) {
			self.statusButtonItem = [[UIBarButtonItem alloc] initWithCustomView:segmentedControl];	
		}
		else {
			self.statusButtonItem = [[UIBarButtonItem alloc] initWithCustomView:label];					
			[self updateStatusText];			
		}

		self.activityButtonItem = [[UIBarButtonItem alloc] initWithCustomView:activity];	
				
		self.toolbarItems = [NSMutableArray arrayWithObjects:	self.refreshButtonItem, 
							 [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
																		   target:nil  action:nil],
							 statusButtonItem,
							 [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
																		   target:nil  action:nil],
							 self.editButtonItem,
							 nil];
		
		if (self.isReadOnly) {
			[self.toolbarItems removeLastObject];
		}
		
		if (![self showActionButton]) {
			self.refreshButtonItem.enabled = NO;
		}
		else {
			self.refreshButtonItem.enabled = YES;
		}

		[self.toolbar setItems:self.toolbarItems animated:NO];
		[self.view addSubview:toolbar];
				
		self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 50)];
		
		[self refreshIfNecessary];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dataListLoadedNotificationReceived:) name:DataListLoadedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loginNotificationReceived:) name:LoginDoneNotification object:nil];	
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadNotificationReceived:) name:DataListReloadNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userLocationChanged:) name:UserLocationChangedNotification object:nil];
		
		self.searchFields = PB_SAFE_COPY([pageData.listLayout objectForKey:@"searchfields"]);
		if (searchFields) {
			
			UISearchBar* searchBar = [[[UISearchBar alloc] init] autorelease];
			[searchBar sizeToFit];
			
			searchController = [[UISearchDisplayController alloc]
								initWithSearchBar:searchBar contentsController:self];
			searchController.delegate = self;
			searchController.searchResultsDataSource = self;
			searchController.searchResultsDelegate = self;
			searchController.searchResultsTableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;		
			self.tableView.tableHeaderView = searchController.searchBar;
		}

		[self fetch]; 

	}
	return self;
}

- (void)userLocationChanged:(NSNotification *)aNotification {
	
	NSLog(@"User location changed");
	self.fetchedResultsController = nil;
	[self fetch];
}

- (void) pickOne:(id)sender{
	
	UISegmentedControl *segmentedControl = (UISegmentedControl *)sender;
	
	if (segmentedControl.selectedSegmentIndex == 1) {
		segmentedControl.selectedSegmentIndex = 0;

		self.mapViewController.locationModel = self.locationModel;
		[self.navigationController pushViewController:mapViewController animated:NO];
	}
	
} 

- (void) updateStatusText {

	if (!self.useLocation && [self.statusButtonItem.customView isKindOfClass:[UILabel class]]) {
		UILabel* label = (UILabel *)self.statusButtonItem.customView;
		
		label.text = @"Not updated";
		NSString *key = [NSString stringWithFormat:kLastStoreUpdateKey, self.pageName];
		NSDate *lastUpdate = [[NSUserDefaults standardUserDefaults] objectForKey:key];		
		if (lastUpdate) {
			NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
			[dateFormatter setDateStyle:kCFDateFormatterShortStyle];
			[dateFormatter setTimeStyle:kCFDateFormatterShortStyle];		
			label.text = [NSString stringWithFormat:@"Updated %@", [dateFormatter stringFromDate:lastUpdate]];
		}
		[label sizeToFit];		
	}	
}

- (void)dataListLoadedNotificationReceived:(NSNotification *)aNotification {
	
	NSString *page = [[aNotification userInfo] valueForKey:@"pageName"];
	
	if (page) {
		if (NSOrderedSame == [page compare:self.pageName]) {
			
			if ([NSThread isMainThread]) {
				self.refreshButtonItem.enabled = YES;
				[self updateStatusText];
				[toolbarItems replaceObjectAtIndex:2 withObject:self.statusButtonItem];
				
				self.toolbar.items = self.toolbarItems;
				[self fetch];
				
			} else {
				[self performSelectorOnMainThread:@selector(dataListLoadedNotificationReceived:) withObject:aNotification waitUntilDone:NO];
				
			}			
		}
	}
}

- (void)reloadNotificationReceived:(NSNotification *)aNotification {
	
	NSLog(@"Reloading UI");	
	[self fetch];
}

- (void)loginNotificationReceived:(NSNotification *)aNotification {
	
	NSString *token = [[aNotification userInfo] valueForKey:@"UD_TOKEN"];
	
	if (token) {
		
		[self refresh];
	}
}

- (void)refresh {		
	NetworkStatus status = [[Reachability sharedReachability] internetConnectionStatus];
	
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSString* token = [defaults objectForKey:@"UD_TOKEN"];
	
	if (self.loadData && NotReachable != status) {
		if (!token) {
		
			TTOpenURL(@"tt://login");
		}
		else {
		
			self.refreshButtonItem.enabled = NO;
			
			[toolbarItems replaceObjectAtIndex:2 withObject:self.activityButtonItem];
			self.toolbar.items = self.toolbarItems;
				
			if (self.useFile) {
				
				NSLog(@"ELC:Saving/loading file data...");
				
				if (self.saveData) {
					
					SaveFileService *dataLoader = [[[SaveFileService alloc] init] autorelease];
					dataLoader.privateQueue = self.relationPrivateQueue;
					[dataLoader sendSaveRequest];						
				}
				
				
				//TODO: order the dependent record load sequence, currently they overlap each other.
				LoadFileService *fileLoader = [[[LoadFileService alloc]init]autorelease];
				fileLoader.privateQueue = self.relationPrivateQueue;
				[fileLoader sendLoadRequestWithOffset:0];
			}
			
			if (useLocation) {

				NSLog(@"ELC:Saving/loading location data...");
				
				if (self.saveData) {
				}
				
				//TODO: order the dependent record load sequence, currently they overlap each other.
				LoadLocationService *locLoader = [[[LoadLocationService alloc] init] autorelease];
				locLoader.privateQueue = self.relationPrivateQueue;
				[locLoader sendLoadRequest];
			}
			
			if (self.saveData) {
				
				NSLog(@"ELC:Saving/deleting data...");
				SaveService *saver = [[[SaveService alloc] init] autorelease];
				saver.privateQueue = self.privateQueue;
				[saver sendSaveRequest:self.pageName];
				
				DeleteService *remover = [[[DeleteService alloc]init] autorelease];
				remover.privateQueue = self.privateQueue;
				[remover sendDeleteRequest:self.pageName];				
			}			
			
			if (self.loadData) {

				NSLog(@"ELC:Loading data...");
				LoadDataService *loader = [[[LoadDataService alloc] init] autorelease];
				loader.privateQueue = self.privateQueue;
				[loader sendLoadRequest:self.pageName];
			}			
			
			if ([self.relationPrivateQueue requestsCount]>0 ) {
				
				NSLog(@"Loading relations first...");
				[self.relationPrivateQueue go];
			}
			else {
				[self.privateQueue go];
			}
		}
	}
}

- (void)queueDidFinish:(ASINetworkQueue *)queue
{
	NSLog(@"queueDidFinish: %d", [NSThread isMainThread]);
	self.refreshButtonItem.enabled = YES;
	[self updateStatusText];
	[toolbarItems replaceObjectAtIndex:2 withObject:self.statusButtonItem];
	
	self.toolbar.items = self.toolbarItems;	
	[self fetch];
}

- (void)relationQueueDidFinish:(ASINetworkQueue *)queue
{
	NSLog(@"relationQueueDidFinish: %d", [NSThread isMainThread]);
	[self.privateQueue go];
}

- (void)refreshIfNecessary
{	
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSString* token = [defaults objectForKey:@"UD_TOKEN"];
    BOOL disableAutoSync = [defaults boolForKey:@"disable_autosync_preference"];

	NetworkStatus status = [[Reachability sharedReachability] internetConnectionStatus];
	if (self.loadData && token && !disableAutoSync && NotReachable != status) {
		
		NSString *key = [NSString stringWithFormat:kLastStoreUpdateKey, self.pageName];
		NSDate *lastUpdate = [defaults objectForKey:key];
		
		NSNumber *refreshDelayNum = [self.pageData.listLayout valueForKey:@"refreshdelay"];
		NSInteger refreshDelay = kRefreshTimeInterval;
		if (refreshDelayNum) {
			refreshDelay = [refreshDelayNum intValue];
		}
		if (lastUpdate == nil || -[lastUpdate timeIntervalSinceNow] > refreshDelay)  {
			[self refresh];
		}		
	}
}

- (NSString *)stringUniqueID {
	
	NSString *  result;
	CFUUIDRef   uuid;
	CFStringRef uuidStr;
	
	uuid = CFUUIDCreate(NULL);
	assert(uuid != NULL);
	uuidStr = CFUUIDCreateString(NULL, uuid);
	assert(uuidStr != NULL);
	result = [NSString stringWithFormat:@"%@", uuidStr];
	assert(result != nil);
	NSLog(@"UNIQUE ID %@", result);
	
	CFRelease(uuidStr);
	CFRelease(uuid);
	return result;
}

- (void)add:(id)sender {
	
	NSString *url = [self.pageData.listLayout valueForKey:@"addItemTemplateUrl"]; 
	NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys: [[TTNavigator navigator] pathForObject:self], @"selectionDelegate", nil];

	if (!url) {
		
		NSManagedObject *data = [NSEntityDescription insertNewObjectForEntityForName: self.entityMetadata inManagedObjectContext:self.managedObjectContext];
		NSString *name = [self stringUniqueID];
		[data setValue:name forKey:@"name"];
		[data setValue:name forKey:@"parabay_id"];
		
		url = [NSString stringWithFormat:@"tt://home/edit/%@", [self.pageName substringToIndex:([self.pageName length]-1) ] ];
		query = [NSDictionary dictionaryWithObjectsAndKeys:data, @"data", name, @"id", nil];

	}
	
	[[TTNavigator navigator] openURL:url query:query animated:YES];
	
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    
    [super setEditing:editing animated:animated];
	[self.navigationItem setHidesBackButton:editing animated:YES];
	
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	
    // The table view should not be re-orderable.
    return NO;
}

- (void)tableView:(UITableView *)tblView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	
    if (editingStyle == UITableViewCellEditingStyleDelete) {
		
		NSFetchedResultsController *frc = self.fetchedResultsController;
		if (tblView == self.searchDisplayController.searchResultsTableView)
		{
			frc = self.searchResultsController;
		}
		
		NSManagedObject *obj = [frc objectAtIndexPath:indexPath];

		ParabayAppDelegate *delegate = (ParabayAppDelegate *)[[UIApplication sharedApplication] delegate];
		[delegate auditDeletion:self.entityMetadata withId:[obj valueForKey:@"parabay_id"]];
		
        // Delete the managed object for the given index path
		[self.managedObjectContext deleteObject: obj];		
		NSLog(@"del=%@", indexPath);
		
		// Save the context.
		NSError *error = nil;
		if (![self.managedObjectContext save:&error]) {
			// Handle error
			NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
			exit(-1);  // Fail
		}
		
		//required to avoid crash on delete.
		[tblView reloadData];
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
}	

- (void)viewDidAppear:(BOOL)animated {
	
	//NSLog(@"ListView:DidAppear");
    [super viewDidAppear: animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSaveNotification:) name:NSManagedObjectContextDidSaveNotification object:self.managedObjectContext];
    [self fetch];
	
	if ([Globals sharedInstance].appStarted) {
		if (self.useLocation) {
			[Globals sharedInstance].appStarted = NO;
			
			self.mapViewController.locationModel = self.locationModel;
			[self.navigationController pushViewController:mapViewController animated:NO];			
		}
	}  
}

- (void)viewDidDisappear:(BOOL)animated {
	
	//NSLog(@"ListView:DidDisAppear");
    [super viewDidDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:self.managedObjectContext];
	
}

- (void)handleSaveNotification:(NSNotification *)aNotification {
	NSLog(@"handleSaveNotification");
    [self.managedObjectContext mergeChangesFromContextDidSaveNotification:aNotification];
    [self fetch];
}

- (void)dealloc {
	
	NSLog(@"ListView:Dealloc");
	
	[self.relationPrivateQueue cancelAllOperations];
	[self.privateQueue cancelAllOperations];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:DataListLoadedNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:DataListReloadNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:LoginDoneNotification object:nil];		
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:self.managedObjectContext];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UserLocationChangedNotification object:nil];
	
	[self.locationModel release];
	[self.toolbar release];	
	[self.toolbarItems release];
    [self.fetchedResultsController release];
    [self.managedObjectContext release];
    [super dealloc];
}

- (void)fetch {
		
	@synchronized(self) { 
		NSLog(@"Fetching data");

		NSError *error = nil;
		BOOL success = [self.fetchedResultsController performFetch:&error];
		NSAssert2(success, @"Unhandled error performing fetch at EntityListController.m, line %d: %@", __LINE__, [error localizedDescription]);
		[self.tableView reloadData];		

		[searchController.searchResultsTableView reloadData];
	}
}

- (NSFetchedResultsController *)fetchedResultsController {
	
	if (fetchedResultsController == nil) {
				
		NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
		NSEntityDescription *entity = [NSEntityDescription entityForName:self.entityMetadata inManagedObjectContext:self.managedObjectContext];
		[fetchRequest setEntity: entity];
		[fetchRequest setPredicate: [self.locationModel predicateForNearbyLocations]];
		
		NSString *filter = PB_SAFE_COPY([pageData.listLayout objectForKey:@"filter"]);
		if (filter) {
			
			NSPredicate *predicate = nil;
			if ([filter rangeOfString:@"@@today@@"].location != NSNotFound) {
				NSString *format = [filter stringByReplacingOccurrencesOfString:@"@@today@@" withString: @" %@"];
				NSTimeInterval secondsPerDay = 24 * 60 * 60;
				NSDate *yesterday = [[NSDate alloc]
									 initWithTimeIntervalSinceNow:-secondsPerDay];
				predicate =[NSPredicate predicateWithFormat:format, yesterday];
			}
			else if ([filter rangeOfString:@"nearby@@"].location != NSNotFound){
				predicate = [self.locationModel predicateForNearbyLocations];
			}
			else {
				
				if ([filter rangeOfString:@"@@parentId@@"].location != NSNotFound) {
					NSString *format = [filter stringByReplacingOccurrencesOfString:@"@@parentId@@" withString: @"%@"];
					filter = [NSString stringWithFormat:format, parentId];
				}
				if ([filter rangeOfString:@"@@parentKind@@"].location != NSNotFound) {
					NSString *parentKind = [self.pageData.listLayout valueForKey:@"parentKind"];
					NSString *format = [filter stringByReplacingOccurrencesOfString:@"@@parentKind@@" withString: @"%@"];
					filter = [NSString stringWithFormat:format, parentKind];
				}
				
				NSLog(@"Predicate = %@", filter);
				
				predicate = [NSPredicate predicateWithFormat:filter];
				
			}
			[fetchRequest setPredicate:predicate];
		}
		
		NSMutableArray *sortDescriptors = [[NSMutableArray alloc] init];
		NSString *sectionNameKeyPath = nil;
		if (sectionKeyPath && [sectionKeyPath length] > 0) {
			sectionNameKeyPath = sectionKeyPath;
		}
		
		for (NSString *descName in self.sortDescList) {
			NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:descName ascending:YES];
			[sortDescriptors addObject:sortDescriptor];
		}
		
		[fetchRequest setSortDescriptors:sortDescriptors];
		fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:managedObjectContext sectionNameKeyPath:sectionNameKeyPath
																				  cacheName: self.pageName];
		
		//note: this causes crashes during save on 3.0 sdk during save
		//fetchedResultsController.delegate = self;
				
	}  
    return fetchedResultsController;
}    

- (NSFetchedResultsController *)searchResultsController {
	
	if (searchResultsController == nil) {
		
		NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
		NSEntityDescription *entity = [NSEntityDescription entityForName:self.entityMetadata inManagedObjectContext:managedObjectContext];
		[fetchRequest setEntity: entity];
		
		NSString *filter = PB_SAFE_COPY([pageData.listLayout objectForKey:@"filter"]);
		if (filter) {
			
			NSPredicate *predicate = nil;
			if ([filter rangeOfString:@"@@today@@"].location != NSNotFound) {
				NSString *format = [filter stringByReplacingOccurrencesOfString:@"@@today@@" withString: @" %@"];
				NSTimeInterval secondsPerDay = 24 * 60 * 60;
				NSDate *yesterday = [[NSDate alloc]
									 initWithTimeIntervalSinceNow:-secondsPerDay];
				predicate =[NSPredicate predicateWithFormat:format, yesterday];
			}
			else if ([filter rangeOfString:@"nearby@@"].location != NSNotFound){
				predicate = [self.locationModel predicateForNearbyLocations];
			}
			else {
				
				if ([filter rangeOfString:@"@@parentId@@"].location != NSNotFound) {
					NSString *format = [filter stringByReplacingOccurrencesOfString:@"@@parentId@@" withString: @"%@"];
					filter = [NSString stringWithFormat:format, parentId];
				}
				if ([filter rangeOfString:@"@@parentKind@@"].location != NSNotFound) {
					NSString *parentKind = [self.pageData.listLayout valueForKey:@"parentKind"];
					NSString *format = [filter stringByReplacingOccurrencesOfString:@"@@parentKind@@" withString: @"%@"];
					filter = [NSString stringWithFormat:format, parentKind];
				}
				
				NSLog(@"Predicate = %@", filter);
				predicate = [NSPredicate predicateWithFormat:filter];
				
			}
			[fetchRequest setPredicate:predicate];
		}
		
		NSMutableArray *sortDescriptors = [[NSMutableArray alloc] init];
		NSString *sectionNameKeyPath = nil;
		if (sectionKeyPath && [sectionKeyPath length] > 0) {
			sectionNameKeyPath = sectionKeyPath;
		}
				
		for (NSString *descName in self.sortDescList) {
			NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:descName ascending:YES];
			[sortDescriptors addObject:sortDescriptor];
		}
		
		[fetchRequest setSortDescriptors:sortDescriptors];
		searchResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:managedObjectContext sectionNameKeyPath:sectionNameKeyPath
																				  cacheName: self.pageName];
		//do not uncomment this - unexpected crashes during save
		//searchResultsController.delegate = self;
		
		if (self.searchTerm !=nil) {
			
			NSMutableString *format = [NSMutableString stringWithFormat:@"%@ contains[cd] ", self.searchFields];
			[format appendString:@"%@"];
			NSPredicate *predicate =[NSPredicate predicateWithFormat:format, self.searchTerm];
			NSLog(@"Predicate = %@", [predicate description]);			

			[searchResultsController.fetchRequest setPredicate:predicate];
		}
		
		
	}  
    return searchResultsController;
} 

- (void)multiSelectionChanged:(NSArray *) multiSelection inListView: (UIViewController *)entityListController {
	//NSLog(@"Array selection= %@", multiSelection);
	
	for (NSManagedObject *item in multiSelection) {
		
		NSManagedObject *data = [NSEntityDescription insertNewObjectForEntityForName: self.entityMetadata inManagedObjectContext:self.managedObjectContext];
		NSString *name = [self stringUniqueID];
		[data setValue:name forKey:@"name"];
		[data setValue:name forKey:@"parabay_id"];
		
		if (NSOrderedSame == [self.pageData.defaultEntityName compare:@"Timmy_Order_Item"]) {
			//TODO: set default values in a generic way
			[data setValue:[NSNumber numberWithInt:1] forKey:@"quantity"];
		}
		
		NSString *childLink = [self.pageData.listLayout valueForKey:@"childLink"];
		if (childLink) {
			[data setValue:item forKey:childLink];
		}
		
		NSString *parentLink = [self.pageData.listLayout valueForKey:@"parentLink"];
		NSString *parentKind = [self.pageData.listLayout valueForKey:@"parentKind"];
		if (parentLink && parentId && parentKind) {
			NSManagedObject *parent = [[Globals sharedInstance] objectWithId:parentId andKind:parentKind inContext:self.managedObjectContext];
			[data setValue:parent forKey:parentLink];
		}		
		
		NSLog(@"Create multi: %@", data);
	}
	
	NSError *error = nil;
	if (![self.managedObjectContext save:&error]) {
		// Handle error
		NSLog(@"Unresolved error saving entities %@, %@", error, [error userInfo]);
	}
	
}

//////////////////////////////////////////////////////////////////////////////////////////////////
// UIViewController (TTCategory)

- (BOOL)persistView:(NSMutableDictionary*)state {
	NSString* selectionDelegateStr = [[TTNavigator navigator] pathForObject:self.selectionDelegate];
	if (selectionDelegateStr) {
		[state setObject:selectionDelegateStr forKey:@"selectionDelegate"];
	}
	return [super persistView:state];
}

- (void)restoreView:(NSDictionary*)state {
	[super restoreView:state];
	NSString* selectionDelegateStr = [state objectForKey:@"selectionDelegate"];
	if (selectionDelegateStr) {
		self.selectionDelegate = [[TTNavigator navigator] objectForPath:selectionDelegateStr];
	}
}

#pragma mark Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
	
	NSFetchedResultsController *frc = self.fetchedResultsController;
	if (table == self.searchDisplayController.searchResultsTableView)
	{
        frc = self.searchResultsController;
    }
	
    NSInteger count = [[frc sections] count];	
	if (!sectionKeyPath || [sectionKeyPath length] == 0) {
		if (count == 0) {
			count = 1;
		}
	}
	
	//NSLog(@"Number of sections:%d", count);
    return count;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    NSInteger numberOfRows = 0;
	
	NSFetchedResultsController *frc = self.fetchedResultsController;
	if (table == self.searchDisplayController.searchResultsTableView)
	{
        frc = self.searchResultsController;
    }
	
	NSArray *sections = [frc sections];
    if ([sections count] > 0) {
        id <NSFetchedResultsSectionInfo> sectionInfo = [sections objectAtIndex:section];
        numberOfRows = [sectionInfo numberOfObjects];
    }
    
	//NSLog(@"Number of rows in section:%d = %d", section, numberOfRows);
    return numberOfRows;
}

- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { 
	NSString *title = nil;
	
	NSFetchedResultsController *frc = self.fetchedResultsController;
	if (table == self.searchDisplayController.searchResultsTableView)
	{
        frc = self.searchResultsController;
    }
	
	if ([ [frc sections] count] > 0) {
		id <NSFetchedResultsSectionInfo> sectionInfo = [[frc sections] objectAtIndex:section];
		
		title = [sectionInfo name];
		if ([title length] > 10) 
			title = [title substringToIndex:10];
		else if ([title length] == 0)
			title = nil; 
	}
	
	return title;
}


- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)table {
	
	if (self.indexField) {
		
		[sectionIndexes removeAllObjects];
		NSArray *sectionTitles = [fetchedResultsController sectionIndexTitles];
		
		NSUInteger i = 0;
		for (NSString *index in sectionTitles) {
			[sectionIndexes setObject:[NSNumber numberWithInt:i++] forKey:index];
		}
		return [TTTableViewDataSource lettersForSectionsWithSearch:NO summary:NO];
	}

    return nil; 
}

- (NSInteger)tableView:(UITableView *)table sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
	
	NSLog(@"sectionForSectionIndexTitle=%@ @ %d", title, index);
	
	NSInteger section = 0;
	
	NSNumber *sectionIndex = [sectionIndexes valueForKey:title];
	if (sectionIndex) {
		section = [fetchedResultsController sectionForSectionIndexTitle:title atIndex:[sectionIndex intValue]];
	}
    return section;
}

- (Class)tableView:(UITableView*)tableView cellClassForObject:(id)object {
	
	if (NSOrderedSame == [self.cellType compare:@"TTTableSubtextItem"]) {
		return [TTTableSubtextItemCell class];
	}
	else if (NSOrderedSame == [self.cellType compare:@"TTTableRightCaptionItem"]) {
		return [TTTableRightCaptionItemCell class];
	}
	else if (NSOrderedSame == [self.cellType compare:@"TTTableCaptionItem"]) {
		return [TTTableCaptionItemCell class];
	}
	else if (NSOrderedSame == [self.cellType compare:@"TTTableSubtitleItem"]) {
		return [TTTableSubtitleItemCell class];
	}
	else if (NSOrderedSame == [self.cellType compare:@"TTTableMessageItem"]) {
		return [TTTableMessageItemCell class];
	}
	else if (NSOrderedSame == [self.cellType compare:@"TTTableImageItem"]) {
		return [TTTableImageItemCell class];
	}
	else if (NSOrderedSame == [self.cellType compare:@"TTStyledTextTableItem"]) {
		return [TTStyledTextTableItemCell class];
	}
	else if (NSOrderedSame == [self.cellType compare:@"TTTableLinkedItem"]) {
		return [TTTableTextItemCell class];
	}
	else if (NSOrderedSame == [self.cellType compare:@"TTTableControl"]) {
		return [TTTableControlCell class];
	} else {
		return [TTTableTextItemCell class];
	}

	return [TTTableViewCell class];
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	
	NSFetchedResultsController *frc = self.fetchedResultsController;
	if (table == self.searchDisplayController.searchResultsTableView)
	{
        frc = self.searchResultsController;
    }
	
	NSManagedObject *data = [frc objectAtIndexPath:indexPath];
	
	Class cellClass = [self tableView:tableView cellClassForObject:data];
	const char* className = class_getName(cellClass);
	NSString* identifier = [[NSString alloc] initWithBytesNoCopy:(char*)className
														  length:strlen(className)
														encoding:NSASCIIStringEncoding freeWhenDone:NO];
	
	UITableViewCell* cell = (UITableViewCell*)[tableView dequeueReusableCellWithIdentifier:identifier];
	if (cell == nil) {
		cell = [[[cellClass alloc] initWithStyle:UITableViewCellStyleDefault
								 reuseIdentifier:identifier] autorelease];		
	}
	[identifier release];
	
	[self configureCell:cell atIndexPath: indexPath forTableView: table];	
    return cell;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath forTableView:(UITableView *)table {
	
	NSFetchedResultsController *frc = self.fetchedResultsController;
	if (table == self.searchDisplayController.searchResultsTableView)
	{
        frc = self.searchResultsController;
    }
	
    // Configure the cell
	NSManagedObject *data = (NSManagedObject *)[frc objectAtIndexPath:indexPath];
	//NSLog(@"configureCell: %@", data);
	
	if ([cell isKindOfClass:[TTTableViewCell class]]) {
		
		TTTableItem *object = [self  tableItemForCellClass:[cell class] withData: data];		
		if (object)
			[(TTTableViewCell*)cell setObject:object];		
		
		if (self.isMultiSelect) {
			
			BOOL checked = NO;
			
			NSString *key = [data valueForKey:@"parabay_id"];
			if ([self.selectedItems objectForKey:key]) {
				checked = YES;
			}
			
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
			
			UIImage *image = (checked) ? [UIImage imageNamed:@"selected.png"] : [UIImage imageNamed:@"unselected.png"];
			
			UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
			CGRect frame = CGRectMake(0.0, 0.0, image.size.width, image.size.height);
			button.frame = frame;	// match the button's size with the image size
			
			[button setBackgroundImage:image forState:UIControlStateNormal];
			
			// set the button's target to this table view controller so we can interpret touch events and map that to a NSIndexSet
			[button addTarget:self action:@selector(checkButtonTapped:event:) forControlEvents:UIControlEventTouchUpInside];
			button.backgroundColor = [UIColor clearColor];
			cell.accessoryView = button;
			
		}		
		else {
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;	
			cell.accessoryView = nil;
		}

	}	
}


- (void)checkButtonTapped:(id)sender event:(id)event
{
	NSSet *touches = [event allTouches];
	UITouch *touch = [touches anyObject];
	
	UITableView *table = self.tableView;
	if (self.isSearchMode) {
		table = self.searchDisplayController.searchResultsTableView;
	}
	
	CGPoint currentTouchPosition = [touch locationInView:table];
	NSIndexPath *indexPath = [table indexPathForRowAtPoint: currentTouchPosition];
	if (indexPath != nil){
		
		[self tableView: table accessoryButtonTappedForRowWithIndexPath: indexPath];
	}

}


- (void)tableView:(UITableView *)tableViewParam accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{		
	BOOL checked = NO;
	
	UITableViewCell *cell = [tableViewParam cellForRowAtIndexPath:indexPath];
	UIButton *button = (UIButton *)cell.accessoryView;
	
	if ([cell isKindOfClass:[TTTableViewCell class]]) {
		
		TTTableItem *object =[(TTTableViewCell*)cell object];
		if (object && object.userInfo) {
			
			NSManagedObject *item = object.userInfo;
			NSString *key = [item valueForKey:@"parabay_id"];
			
			//NSLog(@"item = %@ : %@", [indexPath description], [item valueForKey:@"parabay_id"]);
			
			if ([self.selectedItems objectForKey:key]) {
				[self.selectedItems removeObjectForKey:key];
			}
			else {
				[self.selectedItems setObject:item forKey:key];
				checked = YES;
			}

		}
	}
		
	UIImage *newImage = (checked) ? [UIImage imageNamed:@"selected.png"] : [UIImage imageNamed:@"unselected.png"];
	[button setBackgroundImage:newImage forState:UIControlStateNormal];
	
	NSString *sendTitle = [NSString stringWithFormat:@"%@(%d)", self.multiSelectionButtonTitle, [self.selectedItems count]];
	UIBarButtonItem *sendDataButtonItem = [[UIBarButtonItem alloc] initWithTitle:sendTitle style:UIBarButtonItemStyleDone 
															  target:self action:@selector(processSelection:)];
	[self.toolbarItems replaceObjectAtIndex:0 withObject:sendDataButtonItem];
	[self.toolbar setItems:self.toolbarItems animated:NO];


}

- (TTTableItem *)tableItemForCellClass:(Class)klazz withData: (NSManagedObject *)data {
	
	TTTableItem *object = nil;
	
	if (data) {
		
		NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];		
		NSArray *fields = [self.mobileLayout objectForKey:@"fields"];		
		
		for(NSDictionary *field in fields) {
			
			id value = nil;			
			NSString *type = [field objectForKey:@"type"];
			
			NSDictionary *params = [field objectForKey:@"params"];
			NSString *propertyName = [params objectForKey:@"data"];
				
			NSArray *keyComponents = [propertyName componentsSeparatedByString:@"."];
			if ([keyComponents count]>1) {
				
				if (NSOrderedSame == [propertyName compare:@"Location.distance"]) {
					
					NSString *dist = [[Globals sharedInstance] distanceForProperty:propertyName inItem: data];
					value = dist;				
				}
				else {
					
					NSManagedObject *subItem = [data valueForKey: [keyComponents objectAtIndex:0]];
					value = [subItem valueForKey: [keyComponents objectAtIndex:1]];					
				}
			}
			else {
				
				NSDictionary *entityPropertyMetadata = [self.propertyMetadatas valueForKey:propertyName];
				if (!entityPropertyMetadata)
					continue;
				
				NSString *dataType = [entityPropertyMetadata objectForKey:@"type_info"];				
				if (NSOrderedSame == [dataType compare:@"date"]) {
					
					NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
					[dateFormatter setDateStyle:kCFDateFormatterShortStyle];
					[dateFormatter setTimeStyle:NSDateFormatterNoStyle];
					
					value = [dateFormatter stringFromDate:[data valueForKey: propertyName]];
				} else if (NSOrderedSame == [dataType compare:@"time"]) {
					
					NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
					[dateFormatter setDateStyle:NSDateFormatterNoStyle];
					[dateFormatter setTimeStyle: kCFDateFormatterShortStyle];
					
					value = [dateFormatter stringFromDate:[data valueForKey: propertyName]];
				} else if (NSOrderedSame == [dataType compare:@"image"]) {
					UIImage *image = [[Globals sharedInstance] thumbnailForProperty:propertyName inItem: data];
					[dict setObject:image forKey:type];
					continue;
				}
				else {
					value = [[data valueForKey:propertyName] description];
				}
				
			}
			
			//NSLog(@"Property=%@, dataType=%@", propertyName, dataType);
			
			NSString *oldValue = [dict valueForKey:type];
			if (oldValue) 
				value = [oldValue stringByAppendingFormat:@" %@", value];
			
			if (value) {
				[dict setObject:SAFE_PROPERTY_VALUE(value) forKey:type];
			}
		}
		
		NSString *defaultURL = @"";
		if (self.isReadOnly) {
			defaultURL = nil;
		}
		
		//NSLog(@"dict=%@", dict);
		if ([klazz isEqual:[TTTableMessageItemCell class]]) {
			TTTableMessageItem *item = [[[TTTableMessageItem alloc] init] autorelease];
			item.title = SAFE_PROPERTY_VALUE([NSString stringWithFormat: [dict valueForKey:@"title"]]);
			item.caption = TRIM_STR_VALUE(SAFE_PROPERTY_VALUE([dict valueForKey:@"caption"]), 32);
			item.timestamp = [NSDate date]; //SAFE_PROPERTY_VALUE([dict valueForKey:@"timestamp"]);
			item.text = TRIM_STR_VALUE(SAFE_PROPERTY_VALUE([dict valueForKey:@"text"]), 80);
			item.URL = defaultURL;		
			item.userInfo = data;
			object = item;
		}
		else if ([klazz isEqual:[TTTableCaptionItemCell class]]) {
			TTTableCaptionItem *item = [[[TTTableCaptionItem alloc] init] autorelease];
			item.caption = SAFE_PROPERTY_VALUE([dict valueForKey:@"caption"]);
			item.text = SAFE_PROPERTY_VALUE([dict valueForKey:@"title"]);
			item.URL = defaultURL;
			item.userInfo = data;
			object = item;
		}
		else if ([klazz isEqual:[TTTableSubtitleItemCell class]]) {
			TTTableSubtitleItem *item = [[[TTTableSubtitleItem alloc] init] autorelease];
			item.subtitle = SAFE_PROPERTY_VALUE([dict valueForKey:@"subtitle"]);
			item.text = TRIM_STR_VALUE(SAFE_PROPERTY_VALUE([dict valueForKey:@"text"]), 32);
			item.URL = defaultURL;
			item.userInfo = data;
			object = item;
		}
		else if ([klazz isEqual:[TTTableSubtextItemCell class]]) {
			TTTableSubtextItem *item = [[[TTTableSubtextItem alloc] init] autorelease];
			item.caption = SAFE_PROPERTY_VALUE([dict valueForKey:@"caption"]);
			item.text = SAFE_PROPERTY_VALUE([dict valueForKey:@"title"]);
			item.URL = defaultURL;
			item.userInfo = data;
			object = item;
		}
		else if ([klazz isEqual:[TTTableImageItemCell class]]) {

			NSString *text = TRIM_STR_VALUE(SAFE_PROPERTY_VALUE([dict valueForKey:@"title"]), 32);
			UIImage *image = [dict valueForKey:@"image"];
			
			TTTableImageItem *item = [TTTableImageItem itemWithText:text imageURL:@""
							  defaultImage:image imageStyle:TTSTYLE(rounded)
									   URL:nil];
			item.userInfo = data;
			object = item;
		}
		else if ([klazz isEqual:[TTTableTextItemCell class]]) {
			TTTableTextItem *item = [[[TTTableTextItem alloc] init] autorelease];
			item.text = TRIM_STR_VALUE(SAFE_PROPERTY_VALUE([dict valueForKey:@"title"]), 32);
			item.URL = defaultURL;
			item.userInfo = data;
			object = item;
		}
		[dict release];
	}
	
	return object;
}

- (CGFloat)tableView:(UITableView*)tblView heightForRowAtIndexPath:(NSIndexPath*)indexPath {

	NSFetchedResultsController *frc = self.fetchedResultsController;
	if (tblView == self.searchDisplayController.searchResultsTableView)
	{
        frc = self.searchResultsController;
    }
	
	NSManagedObject *data = [frc objectAtIndexPath:indexPath];
	
	Class cls = [self tableView:tblView cellClassForObject:data];
	TTTableItem *object = [self tableItemForCellClass: cls withData:data];
	return [cls tableView:tblView rowHeightForObject:object];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	
	NSFetchedResultsController *frc = self.fetchedResultsController;
	if (table == self.searchDisplayController.searchResultsTableView)
	{
        frc = self.searchResultsController;
    }
	
    [table deselectRowAtIndexPath:indexPath animated:YES];
	
	if (!self.isMultiSelect) {
		
		NSManagedObject *data = [frc objectAtIndexPath:indexPath];
		
		if (self.isSingleSelect) {
			
			if (self.selectionDelegate != nil && [self.selectionDelegate respondsToSelector:@selector(selectionChanged:inListView:)]) {
				[self.selectionDelegate selectionChanged:data inListView:self];
			}
			
			if (self.dismissOnSelection) {
				[self.navigationController popViewControllerAnimated:NO];		
			}
		}
		else {
			NSString *name = [data valueForKey:@"name"];
			NSString *url = [NSString stringWithFormat:@"tt://home/view/%@?id=%@", [self.pageName substringToIndex:([self.pageName length]-1) ], name ];
			NSMutableDictionary *query = [NSMutableDictionary dictionaryWithObjectsAndKeys:data, @"data", name, @"id", nil];
			if (self.parentId && [self.parentId length]>0) {
				[query setValue:self.parentId forKey:@"parentId"];
			}
			[[TTNavigator navigator] openURL:url query:query animated:YES];			
		}

	}
	else {
		
		[self tableView: table accessoryButtonTappedForRowWithIndexPath: indexPath];
	}

	
}

#pragma mark -
#pragma mark UISearchDisplayController Delegate Methods

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchString:(NSString *)searchString
{    
	self.searchTerm = searchString;
	self.searchResultsController = nil;
	
	NSError *error = nil;
	BOOL success = [self.searchResultsController performFetch:&error];
	NSAssert2(success, @"Unhandled error performing fetch at EntityListController.m, line %d: %@", __LINE__, [error localizedDescription]);		
	
	// Return YES to cause the search result table view to be reloaded.
	return YES;
}


- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchScope:(NSInteger)searchOption
{    
    // Return YES to cause the search result table view to be reloaded.
    return YES;
}

- (void)searchDisplayController:(UISearchDisplayController *)controller willShowSearchResultsTableView:(UITableView *)tableView {
	NSLog(@"willShowSearchResultsTableView");
	self.isSearchMode = YES;
}


- (void)searchDisplayController:(UISearchDisplayController *)controller willUnloadSearchResultsTableView:(UITableView *)tableView {
	NSLog(@"willHideSearchResultsTableView");
	self.isSearchMode = NO;
	[self.tableView reloadData];
}

/**
 Delegate methods of NSFetchedResultsController to respond to additions, removals and so on.
 */

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
	
	UITableView *table = self.tableView;
	if (controller != self.fetchedResultsController) {
		table = self.searchDisplayController.searchResultsTableView;
	}
	
	// The fetch controller is about to start sending change notifications, so prepare the table view for updates.
	//[table beginUpdates];
}

/*
 enum {
 NSFetchedResultsChangeInsert = 1,
 NSFetchedResultsChangeDelete = 2,
 NSFetchedResultsChangeMove = 3,
 NSFetchedResultsChangeUpdate = 4
 
 }; 
*/
- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type newIndexPath:(NSIndexPath *)newIndexPath {
	
	UITableView *table = self.tableView;
	if (controller != self.fetchedResultsController) {
		table = self.searchDisplayController.searchResultsTableView;
	}
	
	NSLog(@"changed row=%@->%@, type=%d", indexPath, newIndexPath, type);
	
	switch(type) {
		case NSFetchedResultsChangeInsert:
			[table insertRowsAtIndexPaths:[NSArray arrayWithObject:newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
			break;
			
		case NSFetchedResultsChangeDelete:
			[table deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
			break;
			
		case NSFetchedResultsChangeUpdate: 
			[self configureCell:[table cellForRowAtIndexPath:indexPath] atIndexPath:indexPath forTableView:table];
			break;
			
		case NSFetchedResultsChangeMove:
			[table deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
			// Reloading the section inserts a new row and ensures that titles are updated appropriately.
			[table reloadSections:[NSIndexSet indexSetWithIndex:newIndexPath.section] withRowAnimation:UITableViewRowAnimationFade];
			break;
	}
}


- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type {
	
	UITableView *table = self.tableView;
	if (controller != self.fetchedResultsController) {
		table = self.searchDisplayController.searchResultsTableView;
	}	
	
	NSLog(@"changed section=%d, type=%d", sectionIndex, type);
	
	switch(type) {
		case NSFetchedResultsChangeInsert:
			[table insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
			break;
			
		case NSFetchedResultsChangeDelete:
			[table deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
			break;
	}
}


- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
	
	UITableView *table = self.tableView;
	if (controller != self.fetchedResultsController) {
		table = self.searchDisplayController.searchResultsTableView;
	}
	
	// The fetch controller has sent all current change notifications, so tell the table view to process all updates.
	//[table endUpdates];
}

- (ASINetworkQueue *)privateQueue {
	
	if (privateQueue == nil) {
		privateQueue = [[ASINetworkQueue alloc] init]; 
		[privateQueue setMaxConcurrentOperationCount:1];
		[privateQueue setShouldCancelAllRequestsOnFailure:NO];
		[privateQueue setDelegate:self];
		[privateQueue setQueueDidFinishSelector:@selector(queueDidFinish:)];
	}
	return privateQueue;
}

- (ASINetworkQueue *)relationPrivateQueue {
	
	if (relationPrivateQueue == nil) {
		relationPrivateQueue = [[ASINetworkQueue alloc] init]; 
		[relationPrivateQueue setMaxConcurrentOperationCount:1];
		[relationPrivateQueue setShouldCancelAllRequestsOnFailure:NO];
		[relationPrivateQueue setDelegate:self];
		[relationPrivateQueue setQueueDidFinishSelector:@selector(relationQueueDidFinish:)];
	}
	return relationPrivateQueue;
}

-(BOOL)showActionButton {
	
	BOOL ret = YES;
	if (!self.loadData && !self.shareData) {
		ret = NO;
	}
	if (isMultiSelect || isSingleSelect) {
		ret = NO;
	}
	
	return ret;
}

-(void)popupActionSheet:(id)sender {
	
    UIActionSheet *popupQuery = [[UIActionSheet alloc]
								 initWithTitle:nil
								 delegate:self
								 cancelButtonTitle:NSLocalizedString(@"Cancel", @"Image picker")
								 destructiveButtonTitle:nil
								 otherButtonTitles:nil];
	
	if (self.loadData) {
		[popupQuery addButtonWithTitle:NSLocalizedString(@"Sync Now", @"Sync now")];
	}
	if (self.shareData) {
		[popupQuery addButtonWithTitle:NSLocalizedString(@"Share data", @"Share data")];
	}
	
    [popupQuery showInView:self.view];
    [popupQuery release];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
		
	if (buttonIndex == 0) {
		NSLog(@"Cancel");
	}
	if (self.loadData && buttonIndex == 1) {
		[self refresh];
		
	}
	if ((self.loadData && self.shareData && buttonIndex == 2) || (!self.loadData && self.shareData && buttonIndex == 1) ) {
		NSString *url = [NSString stringWithFormat:@"tt://home/share/%@", self.pageName];
		TTOpenURL(url);
	}
}

-(void)processSelection:(id)sender {
	
	if (self.dismissOnSelection) {
		[self.navigationController popViewControllerAnimated:NO];		
	}
	
	if (self.selectionDelegate != nil && [self.selectionDelegate respondsToSelector:@selector(multiSelectionChanged:inListView:)]) {
        [self.selectionDelegate multiSelectionChanged:[self.selectedItems allValues] inListView:self];
    }
}

- (MapViewController *)mapViewController {
	
	if (!mapViewController) {
		mapViewController = [[MapViewController alloc]init];
	}
	return mapViewController;
}

@end