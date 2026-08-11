# SPDX-License-Identifier: MIT

cmake_minimum_required(VERSION 3.22)

set(ORBIS_SHARED_DIR "${PROJECT_SOURCE_DIR}/shared")

string(TIMESTAMP ORBIS_VERSION_DATE "%Y.%m.%d" UTC)
string(TIMESTAMP ORBIS_BUILD_NUMBER "%Y%m%d" UTC)

find_library(APPKIT_FRAMEWORK AppKit REQUIRED)
find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
find_library(SECURITY_FRAMEWORK Security REQUIRED)

set(ORBIS_MACOS_SOURCES
    Sources/main.m
    Sources/OrbisAppDelegate.h
    Sources/OrbisAppDelegate.m
	Sources/OrbisAboutController.h
	Sources/OrbisAboutController.m
    Sources/OrbisLibraryViewController.h
    Sources/OrbisLibraryViewController.m
    Sources/OrbisProfileEditorController.h
    Sources/OrbisProfileEditorController.m
	Sources/OrbisConnectionRetryPolicy.h
	Sources/OrbisConnectionRetryPolicy.c
    Sources/OrbisSessionController.h
    Sources/OrbisSessionController.m
    ${ORBIS_SHARED_DIR}/Sources/Profiles/OrbisProfile.h
    ${ORBIS_SHARED_DIR}/Sources/Profiles/OrbisProfile.m
    ${ORBIS_SHARED_DIR}/Sources/Security/OrbisCredentialStore.h
    ${ORBIS_SHARED_DIR}/Sources/Security/OrbisCredentialStore.m
	${ORBIS_SHARED_DIR}/Sources/About/OrbisAcknowledgements.h
	${ORBIS_SHARED_DIR}/Sources/About/OrbisAcknowledgements.m
)

set(ORBIS_MACOS_ICON Resources/OrbisMacIcon.png)
set_source_files_properties(${ORBIS_MACOS_ICON} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)

configure_file(Info.plist.in ${CMAKE_CURRENT_BINARY_DIR}/Info.plist @ONLY)

add_executable(OrbisMac MACOSX_BUNDLE ${ORBIS_MACOS_SOURCES} ${ORBIS_MACOS_ICON})

target_include_directories(
  OrbisMac
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/Sources
    ${ORBIS_SHARED_DIR}/Sources/Profiles
    ${ORBIS_SHARED_DIR}/Sources/Security
	${ORBIS_SHARED_DIR}/Sources/About
    ${PROJECT_SOURCE_DIR}/client/Mac
)

target_link_libraries(
  OrbisMac
  PRIVATE
    MacFreeRDP-library
    ${APPKIT_FRAMEWORK}
    ${FOUNDATION_FRAMEWORK}
    ${SECURITY_FRAMEWORK}
)

target_compile_options(OrbisMac PRIVATE -fno-objc-arc)

set_target_properties(
  OrbisMac
  PROPERTIES
    OUTPUT_NAME Orbis
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_BINARY_DIR}/Info.plist
    MACOSX_BUNDLE_BUNDLE_NAME Orbis
    MACOSX_BUNDLE_GUI_IDENTIFIER com.dnexus.orbis
	MACOSX_BUNDLE_SHORT_VERSION_STRING ${ORBIS_VERSION_DATE}
	MACOSX_BUNDLE_BUNDLE_VERSION ${ORBIS_BUILD_NUMBER}
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "@executable_path/../Frameworks;@loader_path/../Frameworks"
)

set(ORBIS_MACOS_FRAMEWORKS_DIR "$<TARGET_BUNDLE_DIR:OrbisMac>/Contents/Frameworks")
add_custom_command(
  TARGET OrbisMac
  POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${ORBIS_MACOS_FRAMEWORKS_DIR}"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "$<TARGET_FILE:MacFreeRDP-library>"
          "${ORBIS_MACOS_FRAMEWORKS_DIR}/$<TARGET_SONAME_FILE_NAME:MacFreeRDP-library>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "$<TARGET_FILE:freerdp-client>"
          "${ORBIS_MACOS_FRAMEWORKS_DIR}/$<TARGET_SONAME_FILE_NAME:freerdp-client>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "$<TARGET_FILE:freerdp>"
          "${ORBIS_MACOS_FRAMEWORKS_DIR}/$<TARGET_SONAME_FILE_NAME:freerdp>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "$<TARGET_FILE:winpr>"
          "${ORBIS_MACOS_FRAMEWORKS_DIR}/$<TARGET_SONAME_FILE_NAME:winpr>"
  COMMAND /usr/bin/codesign --force --deep --sign - "$<TARGET_BUNDLE_DIR:OrbisMac>"
  COMMENT "Bundling the native FreeRDP runtime and signing Orbis for local use"
  VERBATIM
)

install(TARGETS OrbisMac BUNDLE DESTINATION . COMPONENT client)
