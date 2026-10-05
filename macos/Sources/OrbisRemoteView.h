/* SPDX-License-Identifier: MIT */
#import "MRDPView.h"
@class OrbisSessionController;

@interface OrbisRemoteView : MRDPView
@property(nonatomic, assign) OrbisSessionController *sessionController;
@end
