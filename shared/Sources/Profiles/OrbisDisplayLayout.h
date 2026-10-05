/* SPDX-License-Identifier: MIT */
#ifndef ORBIS_DISPLAY_LAYOUT_H
#define ORBIS_DISPLAY_LAYOUT_H
#include <stdbool.h>
#include <stdint.h>

typedef enum {
    OrbisMonitorRight, OrbisMonitorLeft, OrbisMonitorAbove, OrbisMonitorBelow
} OrbisMonitorArrangement;

typedef struct {
    int32_t x, y;
    uint32_t width, height;
} OrbisDisplayRect;

typedef struct {
    uint32_t count, width, height;
    /* Protocol positions are relative to the primary; pixels start at the bounding box origin. */
    OrbisDisplayRect monitors[2];
    OrbisDisplayRect pixels[2];
} OrbisDisplayLayout;

bool OrbisDisplayResolutionIsValid(uint32_t width, uint32_t height);
bool OrbisDisplayLayoutMake(uint32_t primaryWidth, uint32_t primaryHeight,
                            uint32_t secondaryWidth, uint32_t secondaryHeight,
                            OrbisMonitorArrangement arrangement, bool secondDisplay,
                            OrbisDisplayLayout *layout);
#endif
