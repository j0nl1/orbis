/* SPDX-License-Identifier: MIT */
#import "MRDPView.h"
@class OrbisSessionController;

@interface OrbisRemoteView : MRDPView
{ NSMutableSet *_workspaceConsumedKeys; }
@property(nonatomic, assign) OrbisSessionController *sessionController;
@end
