# SPDX-License-Identifier: MIT

cmake_minimum_required(VERSION 3.22)

if(APPLE AND NOT CMAKE_OSX_SYSROOT)
  set(CMAKE_OSX_SYSROOT macosx CACHE STRING "Apple SDK used by the Orbis test suite")
endif()

project(OrbisTests LANGUAGES C OBJC)

include(CTest)

if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
