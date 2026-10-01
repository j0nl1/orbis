/* SPDX-License-Identifier: MIT */

#ifndef ORBIS_RDP_TRANSPORT_ROUTE_H
#define ORBIS_RDP_TRANSPORT_ROUTE_H

#include <freerdp/transport_io.h>

typedef struct OrbisRDPTransportRoute OrbisRDPTransportRoute;

// Install before starting the client. All connections, including redirections,
// reach the same adapter destination; server and certificate identity stay intact.
OrbisRDPTransportRoute *OrbisRDPTransportRouteInstall(rdpContext *context, const char *hostname, UINT16 port);
// Stop the FreeRDP client before freeing its route, then free the client context.
void OrbisRDPTransportRouteFree(OrbisRDPTransportRoute *route);

#endif
