/* SPDX-License-Identifier: MIT */
#import "OrbisIPadWorkspaceGesture.h"
#include <math.h>

@implementation OrbisIPadWorkspaceGesture
{
	OrbisIPadWorkspaceAction _action;
	UIKeyModifierFlags _modifiers;
	BOOL _fired;
}

- (OrbisIPadWorkspaceAction)updateWithTranslation:(CGPoint)translation
	state:(UIGestureRecognizerState)state modifiers:(UIKeyModifierFlags)modifiers enabled:(BOOL)enabled
{
	if (state == UIGestureRecognizerStateBegan)
	{
		_modifiers = modifiers;
		_fired = NO;
		BOOL reserved = (modifiers & (UIKeyModifierControl | UIKeyModifierCommand)) != 0 ||
		    ((modifiers & UIKeyModifierShift) && !(modifiers & UIKeyModifierAlternate));
		_action = enabled && !reserved ? OrbisIPadWorkspacePending : OrbisIPadWorkspaceScroll;
	}
	if (state == UIGestureRecognizerStateCancelled || state == UIGestureRecognizerStateFailed)
	{
		_action = OrbisIPadWorkspacePending;
		_fired = YES;
		return OrbisIPadWorkspacePending;
	}
	if (_action == OrbisIPadWorkspaceScroll) return _action;
	if (_fired) return OrbisIPadWorkspacePending;
	CGFloat x = fabs(translation.x), y = fabs(translation.y);
	if (_action == OrbisIPadWorkspacePending)
	{
		// Lock the direction before sending any wheel or shortcut events.
		if (x >= 10 && x > y * 1.4)
		{
			BOOL move = (_modifiers & (UIKeyModifierAlternate | UIKeyModifierShift)) ==
			    (UIKeyModifierAlternate | UIKeyModifierShift);
			_action = translation.x < 0 ? (move ? OrbisIPadWorkspaceMovePrevious : OrbisIPadWorkspacePrevious)
			    : (move ? OrbisIPadWorkspaceMoveNext : OrbisIPadWorkspaceNext);
		}
		else if (y >= 10 && y > x * 1.4)
		{
			_action = translation.y < 0 && (_modifiers & UIKeyModifierAlternate) &&
			    !(_modifiers & UIKeyModifierShift) ? OrbisIPadWorkspaceActivities : OrbisIPadWorkspaceScroll;
		}
		else if (state == UIGestureRecognizerStateEnded)
			return OrbisIPadWorkspaceScroll;
	}
	if (_action == OrbisIPadWorkspaceScroll) return _action;
	BOOL upward = _action == OrbisIPadWorkspaceActivities;
	CGFloat distance = upward ? -translation.y :
	    ((_action == OrbisIPadWorkspacePrevious || _action == OrbisIPadWorkspaceMovePrevious)
	        ? -translation.x : translation.x);
	if (_action != OrbisIPadWorkspacePending && distance >= 60)
	{
		_fired = YES;
		return _action;
	}
	return OrbisIPadWorkspacePending;
}
@end
