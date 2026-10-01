/* SPDX-License-Identifier: MIT */

#include "OrbisRDPTransportRoute.h"

#include <assert.h>
#include <freerdp/freerdp.h>
#include <string.h>

static unsigned int connectionCount;
static const char *expectedHostname = "127.0.0.1";
static int expectedPort = 40123;

static rdpTransportLayer *RecordConnection(rdpTransport *transport, const char *hostname,
                                           int port, DWORD timeout)
{
	assert(transport);
	assert(strcmp(hostname, expectedHostname) == 0);
	assert(port == expectedPort);
	assert(timeout == 15000);
	connectionCount++;
	return NULL;
}

int main(void)
{
	freerdp *instance = freerdp_new();
	assert(instance);
	assert(freerdp_context_new(instance));
	rdpContext *context = instance->context;
	assert(context);
	assert(freerdp_settings_set_string(context->settings, FreeRDP_ServerHostname, "rdp.example.test"));
	assert(freerdp_settings_set_uint32(context->settings, FreeRDP_ServerPort, 3389));
	rdpTransportIo original = *freerdp_get_io_callbacks(context);
	original.ConnectLayer = RecordConnection;
	assert(freerdp_set_io_callbacks(context, &original));
	assert(!OrbisRDPTransportRouteInstall(context, "127.0.0.1", 0));
	assert(!OrbisRDPTransportRouteInstall(context, NULL, 3389));
	assert(!OrbisRDPTransportRouteInstall(context, "", 3389));
	OrbisRDPTransportRoute *route = OrbisRDPTransportRouteInstall(context, "127.0.0.1", 40123);
	assert(route);
	assert(!OrbisRDPTransportRouteInstall(context, "127.0.0.1", 40123));
	const rdpTransportIo *callbacks = freerdp_get_io_callbacks(context);
	assert(callbacks->TLSConnect == original.TLSConnect);
	assert(callbacks->ReadBytes == original.ReadBytes);
	assert(callbacks->SetBlockingMode == original.SetBlockingMode);
	(void)callbacks->ConnectLayer(freerdp_get_transport(context), "rdp.example.test", 3389, 15000);
	assert(connectionCount == 1);
	assert(strcmp(freerdp_settings_get_string(context->settings, FreeRDP_ServerHostname), "rdp.example.test") == 0);
	assert(freerdp_settings_get_uint32(context->settings, FreeRDP_ServerPort) == 3389);
	// A server redirect must not bypass the tunnel or overwrite its new TLS identity.
	assert(freerdp_settings_set_string(context->settings, FreeRDP_ServerHostname, "redirected.internal"));
	assert(freerdp_settings_set_uint32(context->settings, FreeRDP_ServerPort, 3390));
	(void)callbacks->ConnectLayer(freerdp_get_transport(context), "redirected.internal", 3390, 15000);
	assert(connectionCount == 2);
	assert(strcmp(freerdp_settings_get_string(context->settings, FreeRDP_ServerHostname), "redirected.internal") == 0);
	assert(freerdp_settings_get_uint32(context->settings, FreeRDP_ServerPort) == 3390);
	OrbisRDPTransportRouteFree(route);
	assert(freerdp_get_io_callback_context(context) == NULL);
	assert(freerdp_get_io_callbacks(context)->ConnectLayer == RecordConnection);
	// A different adapter can supply a hostname rather than a loopback bridge.
	char gateway[] = "gateway.internal";
	expectedHostname = "gateway.internal";
	expectedPort = 4444;
	route = OrbisRDPTransportRouteInstall(context, gateway, 4444);
	assert(route);
	gateway[0] = 'x'; // The route must own its destination, independent of the caller.
	callbacks = freerdp_get_io_callbacks(context);
	(void)callbacks->ConnectLayer(freerdp_get_transport(context), "redirected.internal", 3390, 15000);
	assert(connectionCount == 3);
	assert(strcmp(freerdp_settings_get_string(context->settings, FreeRDP_ServerHostname), "redirected.internal") == 0);
	OrbisRDPTransportRouteFree(route);
	OrbisRDPTransportRouteFree(NULL);
	freerdp_context_free(instance);
	freerdp_free(instance);
	return 0;
}
