/* SPDX-License-Identifier: MIT */
#include "OrbisDisplayLayout.h"
#include <string.h>

bool OrbisDisplayResolutionIsValid(uint32_t width, uint32_t height)
{
    return width >= 200 && width <= 8192 && !(width % 2) && height >= 200 && height <= 8192;
}

bool OrbisDisplayLayoutMakeWithOffset(uint32_t pw, uint32_t ph, uint32_t sw, uint32_t sh,
                            OrbisMonitorArrangement arrangement, int32_t offset, bool second,
                            OrbisDisplayLayout *layout)
{
    if (!layout || !OrbisDisplayResolutionIsValid(pw, ph) ||
        arrangement < OrbisMonitorRight || arrangement > OrbisMonitorBelow ||
        (second && !OrbisDisplayResolutionIsValid(sw, sh)))
        return false;
    memset(layout, 0, sizeof(*layout));
    layout->count = second ? 2 : 1;
    layout->monitors[0] = (OrbisDisplayRect){0, 0, pw, ph};
    if (second)
    {
        int32_t x = 0, y = 0;
        switch (arrangement)
        {
            case OrbisMonitorRight: x = (int32_t)pw; y = offset; break;
            case OrbisMonitorLeft: x = -(int32_t)sw; y = offset; break;
            case OrbisMonitorAbove: y = -(int32_t)sh; x = offset; break;
            case OrbisMonitorBelow: y = (int32_t)ph; x = offset; break;
        }
        /* Keep a shared edge so the pointer can cross between the monitors. */
        if (arrangement < OrbisMonitorAbove)
            y = y < 1 - (int32_t)sh ? 1 - (int32_t)sh : y >= (int32_t)ph ? (int32_t)ph - 1 : y;
        else
        {
            x = x < 1 - (int32_t)sw ? 1 - (int32_t)sw : x >= (int32_t)pw ? (int32_t)pw - 1 : x;
            /* GNOME Remote Desktop requires an even aggregate desktop width. */
            x -= x % 2;
        }
        layout->monitors[1] = (OrbisDisplayRect){x, y, sw, sh};
    }
    int32_t minX = 0, minY = 0;
    for (uint32_t i = 0; i < layout->count; i++)
    {
        if (layout->monitors[i].x < minX) minX = layout->monitors[i].x;
        if (layout->monitors[i].y < minY) minY = layout->monitors[i].y;
    }
    for (uint32_t i = 0; i < layout->count; i++)
    {
        OrbisDisplayRect rect = layout->monitors[i];
        rect.x -= minX;
        rect.y -= minY;
        layout->pixels[i] = rect;
        if ((uint32_t)rect.x + rect.width > layout->width) layout->width = rect.x + rect.width;
        if ((uint32_t)rect.y + rect.height > layout->height) layout->height = rect.y + rect.height;
    }
    return true;
}

bool OrbisDisplayLayoutMake(uint32_t pw, uint32_t ph, uint32_t sw, uint32_t sh,
                           OrbisMonitorArrangement arrangement, bool second, OrbisDisplayLayout *layout)
{
    return OrbisDisplayLayoutMakeWithOffset(pw, ph, sw, sh, arrangement, 0, second, layout);
}
