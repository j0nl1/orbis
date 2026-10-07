/* SPDX-License-Identifier: MIT */
#ifndef ORBIS_MICROPHONE_CONTROL_H
#define ORBIS_MICROPHONE_CONTROL_H

#include <freerdp/freerdp.h>

/* Set the initial state before starting the client; changes also apply live. */
FREERDP_API UINT orbis_audin_set_enabled(rdpContext *context, BOOL enabled);

/* Stop the client first, then remove its audio state before freeing the context. */
FREERDP_API void orbis_audin_remove_context(rdpContext *context);

#endif
