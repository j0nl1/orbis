/* SPDX-License-Identifier: MIT */

#import <AppKit/AppKit.h>

#import "OrbisAppDelegate.h"

int main(int argc, const char *argv[])
{
	(void)argc;
	(void)argv;
	@autoreleasepool
	{
		NSApplication *application = [NSApplication sharedApplication];
		OrbisAppDelegate *delegate = [[[OrbisAppDelegate alloc] init] autorelease];
		[application setDelegate:delegate];
		[application setActivationPolicy:NSApplicationActivationPolicyRegular];
		[application run];
	}
	return 0;
}
