/* SPDX-License-Identifier: MIT */

#include "OrbisConnectionRetryPolicy.h"

#include <stdio.h>

static int expect(int condition, const char *message)
{
	if (condition)
		return 0;
	fprintf(stderr, "FAIL: %s\n", message);
	return 1;
}

int main(void)
{
	int failures = 0;
	OrbisRetryDecision first =
	    OrbisConnectionRetryDecisionForError(ORBIS_FREERDP_CONNECT_FAILED, 0);
	failures += expect(first.shouldRetry, "0x00020006 is not retried on its first occurrence");
	failures += expect(first.delayMilliseconds == 4000,
	                   "the first transient retry does not wait four seconds");

	OrbisRetryDecision second =
	    OrbisConnectionRetryDecisionForError(ORBIS_FREERDP_CONNECT_FAILED, 1);
	failures += expect(second.shouldRetry, "0x00020006 is not retried a second time");
	failures += expect(second.delayMilliseconds == 6000,
	                   "the second transient retry does not cover GNOME's ten-second handover");

	OrbisRetryDecision exhausted =
	    OrbisConnectionRetryDecisionForError(ORBIS_FREERDP_CONNECT_FAILED, 2);
	failures += expect(!exhausted.shouldRetry, "transient retries are not bounded");

	OrbisRetryDecision unrelated = OrbisConnectionRetryDecisionForError(0x00020009U, 0);
	failures += expect(!unrelated.shouldRetry, "an unrelated connection error is hidden by retries");

	if (failures != 0)
		return 1;
	printf("PASS: Orbis macOS transient connection retry policy\n");
	return 0;
}
