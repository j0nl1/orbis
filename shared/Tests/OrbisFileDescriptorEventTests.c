/* SPDX-License-Identifier: MIT */

#include <winpr/synch.h>
#include <winpr/handle.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

static int check_borrowed_descriptor(void)
{
	int descriptors[2];
	if (pipe(descriptors) != 0)
		return 1;
	HANDLE event = CreateFileDescriptorEvent(NULL, FALSE, FALSE, descriptors[0], WINPR_FD_READ);
	BOOL closed = event && CloseHandle(event);
	int valid = fcntl(descriptors[0], F_GETFD) >= 0;
	if (valid)
		close(descriptors[0]);
	close(descriptors[1]);
	if (!closed || !valid)
		fprintf(stderr, "Closing an event must preserve its caller-owned descriptor\n");
	return !closed || !valid;
}

static int check_reused_descriptor(void)
{
	int descriptors[2];
	if (pipe(descriptors) != 0)
		return 1;
	HANDLE event = CreateFileDescriptorEvent(NULL, FALSE, FALSE, descriptors[0], WINPR_FD_READ);
	close(descriptors[0]);
	int replacement = open("/dev/null", O_RDONLY);
	if (replacement < 0)
	{
		if (event)
			CloseHandle(event);
		close(descriptors[1]);
		return 1;
	}
	if (replacement != descriptors[0])
	{
		int result = dup2(replacement, descriptors[0]);
		close(replacement);
		if (result < 0)
		{
			if (event)
				CloseHandle(event);
			close(descriptors[1]);
			return 1;
		}
	}
	BOOL closed = event && CloseHandle(event);
	int valid = fcntl(descriptors[0], F_GETFD) >= 0;
	if (valid)
		close(descriptors[0]);
	close(descriptors[1]);
	if (!closed || !valid)
		fprintf(stderr, "An event must not close a descriptor reused after pipe retirement\n");
	return !closed || !valid;
}

int main(void)
{
	return check_borrowed_descriptor() | check_reused_descriptor();
}
