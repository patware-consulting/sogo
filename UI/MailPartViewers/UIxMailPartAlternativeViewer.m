/*
  Copyright (C) 2007-2018 Inverse inc.
  Copyright (C) 2004 SKYRIX Software AG

  This file is part of SOGo.

  SOGo is free software; you can redistribute it and/or modify it under
  the terms of the GNU Lesser General Public License as published by the
  Free Software Foundation; either version 2, or (at your option) any
  later version.

  SOGo is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
  License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with SOGo; see the file COPYING.  If not, write to the
  Free Software Foundation, 59 Temple Place - Suite 330, Boston, MA
  02111-1307, USA.
*/

#import <Foundation/NSDictionary.h>
#import <Foundation/NSNull.h>

#import <SOGo/NSObject+Utilities.h>

#import <NGExtensions/NSObject+Logs.h>
#import <NGMail/NGMimeMessageParser.h>
#import <NGMime/NGMimeBodyPart.h>
#import <NGMime/NGMimeMultipartBody.h>
#import <NGMime/NGMimeType.h>

#import <UI/MailerUI/WOContext+UIxMailer.h>

#import "UIxMailPartMixedViewer.h"
#import "UIxMailRenderingContext.h"

/*
  UIxMailPartAlternativeViewer

  Display multipart/alternative parts. Most common application is for messages
  which contain text/html and text/plain, but it is also used in other
  contexts, eg in SOGo appointment mails.

  TODO: We might want to give the user the possibility to access all parts
        of the alternative set.
*/

@interface UIxMailPartAlternativeViewer : UIxMailPartMixedViewer

@end

@implementation UIxMailPartAlternativeViewer

- (void) dealloc
{
  [super dealloc];
}

/* part selection */

- (NSArray *) childPartTypes
{
  NSMutableArray *types;
  NSArray  *childParts;
  NSString *mt, *st;

  NSUInteger i, count;

  if ([self decodedFlatContent])
    childParts = [[self decodedFlatContent] parts];
  else
    childParts = [[self bodyInfo] valueForKey: @"parts"];

  count = [childParts count];
  types = [NSMutableArray arrayWithCapacity: count];

  for (i = 0; i < count; i++)
    {
      if ([self decodedFlatContent])
        {
          mt = [[[childParts objectAtIndex: i] contentType] type];
          st = [[[childParts objectAtIndex: i] contentType] subType];
        }
      else
        {
          mt = [[[childParts objectAtIndex: i] valueForKey: @"type"] lowercaseString];
          st = [[[childParts objectAtIndex: i] valueForKey: @"subtype"] lowercaseString];
        }
      mt = [[mt stringByAppendingString: @"/"] stringByAppendingString: st];
      [types addObject: (mt ? (id)mt : (id)[NSNull null])];
    }

  return types;
}

- (NSUInteger) _preferredTypesPart: (NSArray *) types
{
  NSUInteger count, max;
  NSUInteger part;
  const NSString *priorities[] = { @"multipart/related", @"multipart/mixed",
				   @"text/calendar", @"text/html",
				   @"text/plain" };

  part = NSNotFound;

  max = sizeof (priorities) / sizeof (NSString *);
  for (count = 0; count < max; count++)
    {
      part = [types indexOfObject: priorities[count]];
      if (part != NSNotFound)
	break;
    }

  return part;
}

- (int) _selectPartIndexFromTypes: (NSArray *) _types
{
  /* returns the index of the selected part or NSNotFound */
  NSUInteger count, max, part;

  part = [self _preferredTypesPart: _types];
  if (part == NSNotFound)
    {
      max = [_types count];
      /* then we scan for other text types and choose the first one found */
      for (count = 0; count < max; count++)
	if ([[_types objectAtIndex: count] hasPrefix:@"text/"])
	  {
	    part = count;
	    break;
	  }
    }

  if (part == NSNotFound)
    part = 0; /* as a fallback, we select the first available part */

  return part;
}

- (void) selectChildInfo
{
  NSUInteger idx;

  DESTROY(childInfo);
  childIndex = 0;

  idx = [self _selectPartIndexFromTypes: [self childPartTypes]];
  if (idx == NSNotFound)
    {
      [self errorWithFormat:@"could not select a part of types: %@", [self childPartTypes]];
      return;
    }

  childIndex = idx + 1;

  if ([self decodedFlatContent])
    childInfo = [[[[self decodedFlatContent] parts] objectAtIndex: idx] bodyInfo];
  else
    childInfo = [[[self bodyInfo] valueForKey:@"parts"] objectAtIndex: idx];

  [childInfo retain];
}

/* nested viewers */

- (id) contentViewerComponent
{
  id info;

  info = [self childInfo];
  return [[[self context] mailRenderingContext] viewerForBodyInfo: info];
}

- (id) renderedPart
{
  id info, viewer;
  NSArray *parts;
  NSMutableArray *renderedParts;
  NSString *preferredType, *htmlNoTags;
  NSUInteger i, max;
  BOOL fallbackNeeded, hasTextPlain;

  if ([self decodedFlatContent])
    parts = [[self decodedFlatContent] parts];
  else
    parts = [[self bodyInfo] valueForKey: @"parts"];

  max = [parts count];
  renderedParts = [NSMutableArray arrayWithCapacity: max];
  for (i = 0; i < max; i++)
    {
      [self setChildIndex: i];

      if ([self decodedFlatContent])
        [self setChildInfo: [[parts objectAtIndex: i] bodyInfo]];
      else
        [self setChildInfo: [parts objectAtIndex: i]];

      info = [self childInfo];
      viewer = [[[self context] mailRenderingContext] viewerForBodyInfo: info];
      [viewer setBodyInfo: info];
      [viewer setPartPath: [self childPartPath]];
      [viewer setAttachmentIds: attachmentIds];
      if ([self decodedFlatContent])
        [viewer setDecodedContent: [parts objectAtIndex: i]];
      [renderedParts addObject: [viewer renderedPart]];
    }

  // Identity a preferred type
  [self selectChildInfo];
  preferredType = [NSString stringWithFormat: @"%@/%@",
                            [[self childInfo] objectForKey: @"type"],
                            [[self childInfo] objectForKey: @"subtype"]];

  // Check if the HTML part is good
  // If no, try to fallback on text/plain
  fallbackNeeded = NO;
  hasTextPlain = NO;
  for (i = 0 ; i < [renderedParts length] ; i++) {
    if ([[[[renderedParts objectAtIndex: i] objectForKey: @"contentType"] lowercaseString] isEqualToString: @"text/html"]
        && [[preferredType lowercaseString] isEqualToString: @"text/html"]) {
      if ([[renderedParts objectAtIndex: i] objectForKey:@"exception"]) {
        fallbackNeeded = YES;
      }
    }

    if ([[[[renderedParts objectAtIndex: i] objectForKey: @"contentType"] lowercaseString] isEqualToString: @"text/plain"]) {
      hasTextPlain = YES;
    }
  }

  if (fallbackNeeded && hasTextPlain) {
    preferredType = @"text/plain";
  }

  return [NSDictionary dictionaryWithObjectsAndKeys:
                         [self className], @"type",
                       preferredType, @"preferredPart",
                       renderedParts, @"content",
                       nil];
}

@end /* UIxMailPartAlternativeViewer */
