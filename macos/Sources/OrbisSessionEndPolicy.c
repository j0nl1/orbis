/* SPDX-License-Identifier: MIT */

#include "OrbisSessionEndPolicy.h"

OrbisSessionEndDisposition OrbisSessionEndDispositionForErrorInfo(uint32_t errorCode)
{
	if (errorCode == ORBIS_ERRINFO_NONE)
		return OrbisSessionEndDispositionIgnore;
	if (errorCode == ORBIS_ERRINFO_LOGOFF_BY_USER)
		return OrbisSessionEndDispositionEnded;
	return OrbisSessionEndDispositionFailed;
}
