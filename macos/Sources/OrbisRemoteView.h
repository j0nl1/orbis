/* SPDX-License-Identifier: MIT */
#import "MRDPView.h"
@class OrbisSessionController;

@interface OrbisRemoteView : MRDPView
{ NSMutableSet *_workspaceConsumedKeys, *_workspaceConsumedButtons, *_workspaceSuppressedButtonReleases; }
@property(nonatomic, assign) OrbisSessionController *sessionController;
@end
