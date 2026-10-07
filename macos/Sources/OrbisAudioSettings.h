/* SPDX-License-Identifier: MIT */
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const OrbisMicrophoneEnabledKey;
FOUNDATION_EXPORT NSString *const OrbisAudioSettingsDidChangeNotification;

// Microphone sharing starts off. Both settings and the session menu use the
// same preference so changes also apply to future connections.
BOOL OrbisMicrophoneIsEnabled(NSUserDefaults *defaults);
void OrbisSetMicrophoneEnabled(NSUserDefaults *defaults, BOOL enabled);
