/* SPDX-License-Identifier: MIT */

#ifndef ORBIS_CONNECTION_RETRY_POLICY_H
#define ORBIS_CONNECTION_RETRY_POLICY_H

#include <stdbool.h>
#include <stdint.h>

#define ORBIS_FREERDP_CONNECT_FAILED 0x00020006U

typedef struct
{
	bool shouldRetry;
	uint32_t delayMilliseconds;
} OrbisRetryDecision;

OrbisRetryDecision OrbisConnectionRetryDecisionForError(uint32_t errorCode,
                                                         unsigned int completedRetries);

#endif
