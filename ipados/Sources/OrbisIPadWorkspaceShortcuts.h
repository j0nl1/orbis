/* SPDX-License-Identifier: MIT */
#import <Foundation/Foundation.h>

// Keep action identifiers stable in exported diagnostics.
typedef NS_ENUM(NSInteger, OrbisIPadWorkspaceAction) {
	OrbisIPadWorkspacePrevious = 1,
	OrbisIPadWorkspaceNext = 2,
	OrbisIPadWorkspaceActivities = 5,
	OrbisIPadWorkspaceCloseActivities = 6,
};
