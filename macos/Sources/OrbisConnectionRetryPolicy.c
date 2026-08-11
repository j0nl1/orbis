/* SPDX-License-Identifier: MIT */

#include "OrbisConnectionRetryPolicy.h"

OrbisRetryDecision OrbisConnectionRetryDecisionForError(uint32_t errorCode,
                                                         unsigned int completedRetries)
{
	OrbisRetryDecision decision = { false, 0 };
	if (errorCode != ORBIS_FREERDP_CONNECT_FAILED || completedRetries >= 2)
		return decision;

	decision.shouldRetry = true;
	decision.delayMilliseconds = completedRetries == 0 ? 4000U : 6000U;
	return decision;
}
