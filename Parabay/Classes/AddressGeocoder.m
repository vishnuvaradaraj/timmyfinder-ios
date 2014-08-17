//
//  AddressGeocoder.m
//  Test
//
//  Created by Bill Dudney on 5/15/09.
//  Copyright 2009 Gala Factory Software LLC. All rights reserved.
//
//
//  Licensed with the Apache 2.0 License
//  http://apache.org/licenses/LICENSE-2.0
//

#import "AddressGeocoder.h"
#import "CXMLNode_XPathExtensions.h"
#import "CXMLDocument.h"

NSString *MAPS_API_KEY = @"ABQIAAAATejoI1-rG9VOa4T5f3ppWRRYQtG-vnXKOEpkBE1rl0xG1xYLZBTYfFQvZDnVp0yQINRy-HPV5AeNaA";

@implementation AddressGeocoder

+ (BOOL)geocodeStreetAddress:(NSString *)street 
                        city:(NSString *)city
                       state:(NSString *)state
                         zip:(NSString *)zip
                     country:(NSString *)country
                intoLocation:(CLLocationCoordinate2D *)location {
  BOOL success = NO;
  NSString *wholeAddress = [NSString stringWithFormat:@"%@ %@ %@ %@ %@", 
                            street, city, state, zip, country];
  NSString *firstHalf = @"http://maps.google.com/maps/geo?q=";
  NSString *secondHalf = @"&output=xml&sensor=false&key=";
  NSString *unEscapedURL = [NSString stringWithFormat:@"%@%@%@%@", 
                            firstHalf, wholeAddress, secondHalf, 
                            MAPS_API_KEY];
  NSString *urlString = [unEscapedURL 
                          stringByAddingPercentEscapesUsingEncoding:
                                NSUTF8StringEncoding];
  NSURL *url = [NSURL URLWithString:urlString];
  NSError *error = nil;
  CXMLDocument *doc = [[CXMLDocument alloc] 
                       initWithContentsOfURL:url 
                       options:CXMLDocumentTidyXML error:&error];
  CXMLElement *element = [doc rootElement];
  NSDictionary *namespaceMappings = 
      [NSDictionary dictionaryWithObject:@"http://earth.google.com/kml/2.0"
                                  forKey:@"kml"];
  NSArray *status = [element nodesForXPath:@"//kml:Status/kml:code" 
                         namespaceMappings:namespaceMappings
                                     error:&error];
  if([@"200" isEqualToString:[[status objectAtIndex:0] stringValue]]) {
    NSArray *coordElements = [element nodesForXPath:@"//kml:coordinates"
                                  namespaceMappings:namespaceMappings
                                              error:&error];
    NSString *coords = [[coordElements objectAtIndex:0] stringValue];
    NSArray *components = [coords componentsSeparatedByString:@","];
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    NSNumber *longitude = 
        [formatter numberFromString:[components objectAtIndex:0]];
    NSNumber *latitude = 
        [formatter numberFromString:[components objectAtIndex:1]];
    location->longitude = [longitude floatValue];
    location->latitude = [latitude floatValue];
    [formatter release];
    success = YES;
  }
  return success;
}

+ (CLLocationCoordinate2D)locationOfAddress:(NSString *)address {
  CLLocationCoordinate2D location = {0.0f, 0.0f};
  NSString *street = address;
  if(nil == street || [street length] == 0) {
    street = @"";
  }
  
  if(![self geocodeStreetAddress:street city:@""
                           state:@"" zip:@"" country:@""
                    intoLocation:&location]) {
	  [self geocodeStreetAddress:@"" city:address
                           state:@"" zip:@"" country:@"" intoLocation:&location];
  }
  
  return location;
}

@end
