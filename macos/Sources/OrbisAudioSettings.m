/* SPDX-License-Identifier: MIT */
#import "OrbisAudioSettings.h"

NSString *const OrbisMicrophoneEnabledKey = @"OrbisMicrophoneEnabled.v1";
NSString *const OrbisAudioSettingsDidChangeNotification = @"OrbisAudioSettingsDidChange";

BOOL OrbisMicrophoneIsEnabled(NSUserDefaults *defaults)
{
    return [defaults boolForKey:OrbisMicrophoneEnabledKey];
}

void OrbisSetMicrophoneEnabled(NSUserDefaults *defaults, BOOL enabled)
{
    if (OrbisMicrophoneIsEnabled(defaults) == enabled) return;
    [defaults setBool:enabled forKey:OrbisMicrophoneEnabledKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:OrbisAudioSettingsDidChangeNotification object:defaults];
}
