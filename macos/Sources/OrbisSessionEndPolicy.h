/* SPDX-License-Identifier: MIT */

#ifndef ORBIS_SESSION_END_POLICY_H
#define ORBIS_SESSION_END_POLICY_H

#include <stdint.h>

#define ORBIS_ERRINFO_LOGOFF_BY_USER 0x0000000CU
#define ORBIS_ERRINFO_NONE 0xFFFFFFFFU

typedef enum
{
	OrbisSessionEndDispositionIgnore,
	OrbisSessionEndDispositionEnded,
	OrbisSessionEndDispositionFailed
} OrbisSessionEndDisposition;

OrbisSessionEndDisposition OrbisSessionEndDispositionForErrorInfo(uint32_t errorCode);

#endif
