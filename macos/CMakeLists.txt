# SPDX-License-Identifier: MIT

cmake_minimum_required(VERSION 3.22)

set(ORBIS_SHARED_DIR "${PROJECT_SOURCE_DIR}/shared")

string(TIMESTAMP ORBIS_DEFAULT_VERSION "%Y.%m.%d" UTC)
string(TIMESTAMP ORBIS_DEFAULT_BUILD "%Y%m%d" UTC)
set(ORBIS_VERSION_DATE "${ORBIS_DEFAULT_VERSION}" CACHE STRING "Displayed Orbis version")
set(ORBIS_BUILD_NUMBER "${ORBIS_DEFAULT_BUILD}" CACHE STRING "Monotonically increasing Orbis build")
option(ORBIS_ENABLE_UPDATES "Enable signed GitHub release updates" OFF)
set(ORBIS_UPDATE_FEED_URL "https://github.com/j0nl1/orbis/releases/latest/download/appcast.xml"
    CACHE STRING "Sparkle appcast URL")
set(ORBIS_UPDATE_PUBLIC_KEY "" CACHE STRING "Base64 Sparkle Ed25519 public key")
set(ORBIS_SPARKLE_ROOT "" CACHE PATH "Extracted Sparkle distribution")
set(ORBIS_UPDATER_PLIST "")
if(ORBIS_ENABLE_UPDATES)
  if(NOT ORBIS_UPDATE_PUBLIC_KEY MATCHES "^[A-Za-z0-9+/]+=$" OR
     NOT ORBIS_UPDATE_FEED_URL MATCHES "^https://[A-Za-z0-9./_-]+$")
    message(FATAL_ERROR "Updates require an Ed25519 public key and an HTTPS appcast URL")
  endif()
  string(LENGTH "${ORBIS_UPDATE_PUBLIC_KEY}" ORBIS_UPDATE_KEY_LENGTH)
  if(NOT ORBIS_UPDATE_KEY_LENGTH EQUAL 44)
    message(FATAL_ERROR "The Ed25519 public key must encode 32 bytes")
  endif()
  find_library(SPARKLE_FRAMEWORK Sparkle PATHS "${ORBIS_SPARKLE_ROOT}" NO_DEFAULT_PATH REQUIRED)
  set(ORBIS_UPDATER_PLIST "
  <key>SUFeedURL</key><string>${ORBIS_UPDATE_FEED_URL}</string>
  <key>SUPublicEDKey</key><string>${ORBIS_UPDATE_PUBLIC_KEY}</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>SUAutomaticallyUpdate</key><false/>
  <key>SUAllowsAutomaticUpdates</key><false/>
  <key>SUEnableSystemProfiling</key><false/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SURequireSignedFeed</key><true/>
  <key>SUSignedFeedFailureExpirationInterval</key><integer>0</integer>")
endif()

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
    Sources/OrbisSessionEndPolicy.h
    Sources/OrbisSessionEndPolicy.c
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

if(ORBIS_ENABLE_UPDATES)
  target_compile_definitions(OrbisMac PRIVATE ORBIS_ENABLE_UPDATES=1)
  target_link_libraries(OrbisMac PRIVATE ${SPARKLE_FRAMEWORK})
  add_custom_command(TARGET OrbisMac POST_BUILD
    COMMAND /usr/bin/ditto "${SPARKLE_FRAMEWORK}"
            "$<TARGET_BUNDLE_DIR:OrbisMac>/Contents/Frameworks/Sparkle.framework"
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:OrbisMac>/Contents/Resources"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${ORBIS_SPARKLE_ROOT}/LICENSE"
            "$<TARGET_BUNDLE_DIR:OrbisMac>/Contents/Resources/Sparkle-LICENSE.txt"
    VERBATIM)
else()
  add_custom_command(TARGET OrbisMac POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E remove_directory
            "$<TARGET_BUNDLE_DIR:OrbisMac>/Contents/Frameworks/Sparkle.framework"
    COMMAND ${CMAKE_COMMAND} -E rm -f
            "$<TARGET_BUNDLE_DIR:OrbisMac>/Contents/Resources/Sparkle-LICENSE.txt"
    VERBATIM)
endif()

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
