/* SPDX-License-Identifier: MIT */

#include "OrbisSessionEndPolicy.h"

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
	failures += expect(
	    OrbisSessionEndDispositionForErrorInfo(ORBIS_ERRINFO_NONE) ==
	        OrbisSessionEndDispositionIgnore,
	    "the no-error sentinel is not ignored");
	failures += expect(
	    OrbisSessionEndDispositionForErrorInfo(ORBIS_ERRINFO_LOGOFF_BY_USER) ==
	        OrbisSessionEndDispositionEnded,
	    "a user logoff is not treated as a normal session end");
	failures += expect(
	    OrbisSessionEndDispositionForErrorInfo(0x00000001U) ==
	        OrbisSessionEndDispositionFailed,
	    "a protocol error is not reported as a failure");

	if (failures != 0)
		return 1;
	printf("PASS: Orbis macOS session-end policy\n");
	return 0;
}
