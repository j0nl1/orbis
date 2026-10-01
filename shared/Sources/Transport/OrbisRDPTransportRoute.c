/* SPDX-License-Identifier: MIT */

#include "OrbisRDPTransportRoute.h"

#include <stdlib.h>
#include <string.h>

struct OrbisRDPTransportRoute
{
	rdpContext *context;
	rdpTransportIo original;
	UINT16 port;
	char *hostname;
};

static rdpTransportLayer *OrbisRDPTransportConnectLayer(rdpTransport *transport, const char *hostname,
                                                 int port, DWORD timeout)
{
	(void)hostname;
	(void)port;
	rdpContext *context = transport_get_context(transport);
	OrbisRDPTransportRoute *route = freerdp_get_io_callback_context(context);
	if (!route || !route->original.ConnectLayer)
		return NULL;
	// Reuse FreeRDP's socket, event, and TLS machinery through its public callbacks.
	// Do not rewrite ServerHostname, ServerPort, or the redirected certificate identity.
	return route->original.ConnectLayer(transport, route->hostname, route->port, timeout);
}

OrbisRDPTransportRoute *OrbisRDPTransportRouteInstall(rdpContext *context, const char *hostname, UINT16 port)
{
	if (!context || !hostname || !hostname[0] || !port || freerdp_get_io_callback_context(context))
		return NULL;
	const rdpTransportIo *original = freerdp_get_io_callbacks(context);
	if (!original || !original->ConnectLayer)
		return NULL;
	OrbisRDPTransportRoute *route = calloc(1, sizeof(*route));
	if (!route)
		return NULL;
	route->hostname = strdup(hostname);
	if (!route->hostname)
	{
		free(route);
		return NULL;
	}
	route->context = context;
	route->original = *original;
	route->port = port;
	rdpTransportIo callbacks = *original;
	callbacks.ConnectLayer = OrbisRDPTransportConnectLayer;
	if (!freerdp_set_io_callback_context(context, route))
	{
		free(route->hostname);
		free(route);
		return NULL;
	}
	if (!freerdp_set_io_callbacks(context, &callbacks))
	{
		(void)freerdp_set_io_callback_context(context, NULL);
		free(route->hostname);
		free(route);
		return NULL;
	}
	return route;
}

void OrbisRDPTransportRouteFree(OrbisRDPTransportRoute *route)
{
	if (!route)
		return;
	(void)freerdp_set_io_callbacks(route->context, &route->original);
	(void)freerdp_set_io_callback_context(route->context, NULL);
	free(route->hostname);
	free(route);
}
