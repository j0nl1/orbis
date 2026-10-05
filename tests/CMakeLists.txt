# SPDX-License-Identifier: MIT

if(NOT APPLE)
  message(FATAL_ERROR "The Orbis native test suite requires macOS")
endif()

find_library(APPKIT_FRAMEWORK AppKit REQUIRED)
find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
find_library(SECURITY_FRAMEWORK Security REQUIRED)
find_package(XCTest REQUIRED)
find_package(Python3 COMPONENTS Interpreter REQUIRED)
add_test(NAME unit.release-version
  COMMAND ${Python3_EXECUTABLE} ${PROJECT_SOURCE_DIR}/tests/test_release_version.py)
set_tests_properties(unit.release-version PROPERTIES LABELS "unit;release")
add_test(NAME unit.appcast COMMAND ${Python3_EXECUTABLE} ${PROJECT_SOURCE_DIR}/tests/test_appcast.py)
set_tests_properties(unit.appcast PROPERTIES LABELS "unit;release")
add_test(NAME integration.macos-signing
  COMMAND ${PROJECT_SOURCE_DIR}/scripts/test-orbis-macos-signing.sh)
set_tests_properties(integration.macos-signing PROPERTIES LABELS "integration;release")
set(ORBIS_TEST_SPARKLE_ROOT "$ENV{ORBIS_TEST_SPARKLE_ROOT}" CACHE PATH "Sparkle distribution for updater tests")
set(ORBIS_TEST_FREERDP_BUILD_DIR "" CACHE PATH "Built FreeRDP runtime for native keyboard input tests")
if(ORBIS_TEST_FREERDP_BUILD_DIR)
  set(keyboard_source ${PROJECT_SOURCE_DIR}/.build/vendor/freerdp)
  set(keyboard_runtime ${ORBIS_TEST_FREERDP_BUILD_DIR}/macos/Orbis.app/Contents/Frameworks)
  add_executable(orbis_keyboard_input_tests
    ${PROJECT_SOURCE_DIR}/macos/Tests/OrbisKeyboardInputTests.m
    ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisInputCapture.m
    ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisInputCaptureSettings.m
    ${keyboard_source}/client/Mac/MRDPView.m
    ${keyboard_source}/client/Mac/Keyboard.m
    ${keyboard_source}/client/Mac/Clipboard.m
    ${keyboard_source}/client/Mac/mf_client.m
    ${keyboard_source}/client/Mac/MRDPCursor.m)
  target_include_directories(orbis_keyboard_input_tests PRIVATE
    ${PROJECT_SOURCE_DIR}/macos/Sources
    ${keyboard_source}/client/Mac ${keyboard_source}/include ${keyboard_source}/winpr/include
    ${ORBIS_TEST_FREERDP_BUILD_DIR}/include ${ORBIS_TEST_FREERDP_BUILD_DIR}/winpr/include)
  target_compile_options(orbis_keyboard_input_tests PRIVATE -fno-objc-arc -fblocks)
  # Replace only the outgoing network boundary; run the real AppKit event handlers.
  target_compile_definitions(orbis_keyboard_input_tests PRIVATE
    freerdp_input_send_keyboard_event=OrbisRecordKeyboardEvent
    freerdp_input_send_unicode_keyboard_event=OrbisRecordUnicodeKeyboardEvent)
  set_property(SOURCE ${keyboard_source}/client/Mac/MRDPView.m APPEND PROPERTY
    COMPILE_DEFINITIONS mf_press_mouse_button=OrbisRecordMouseButton
      freerdp_client_send_button_event=OrbisRecordDisplayPointer
      freerdp_client_send_extended_button_event=OrbisRecordExtendedDisplayPointer)
  target_link_libraries(orbis_keyboard_input_tests PRIVATE ${APPKIT_FRAMEWORK}
    "${keyboard_runtime}/libfreerdp3.3.dylib"
    "${keyboard_runtime}/libfreerdp-client3.3.dylib"
    "${keyboard_runtime}/libwinpr3.3.dylib" "-framework IOKit" "-framework CoreGraphics" "-framework ApplicationServices")
  target_link_options(orbis_keyboard_input_tests PRIVATE "LINKER:-rpath,${keyboard_runtime}")
  add_executable(orbis_virtual_display_tests
    ${PROJECT_SOURCE_DIR}/macos/Tests/OrbisVirtualDisplayTests.m
    ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisAppDelegate.m
    ${keyboard_source}/client/Mac/MRDPView.m
    ${keyboard_source}/client/Mac/Keyboard.m
    ${keyboard_source}/client/Mac/Clipboard.m
    ${keyboard_source}/client/Mac/mf_client.m
    ${keyboard_source}/client/Mac/MRDPCursor.m
    ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisSessionController.m
    ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisInputCapture.m
    ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisConnectionRetryPolicy.c
    ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisSessionEndPolicy.c
    ${PROJECT_SOURCE_DIR}/shared/Sources/Transport/OrbisRDPTransportRoute.c)
  target_include_directories(orbis_virtual_display_tests PRIVATE
    ${PROJECT_SOURCE_DIR}/macos/Sources ${keyboard_source}/client/Mac
    ${keyboard_source}/include ${keyboard_source}/winpr/include
    ${ORBIS_TEST_FREERDP_BUILD_DIR}/include ${ORBIS_TEST_FREERDP_BUILD_DIR}/winpr/include)
  target_compile_options(orbis_virtual_display_tests PRIVATE -fno-objc-arc -fblocks)
  target_link_libraries(orbis_virtual_display_tests PRIVATE orbis_macos_ui ${APPKIT_FRAMEWORK}
    "-framework IOKit" "-framework CoreGraphics"
    "${keyboard_runtime}/libfreerdp3.3.dylib"
    "${keyboard_runtime}/libfreerdp-client3.3.dylib"
    "${keyboard_runtime}/libwinpr3.3.dylib")
  target_link_options(orbis_virtual_display_tests PRIVATE "LINKER:-rpath,${keyboard_runtime}")
  add_test(NAME integration.macos-virtual-display COMMAND orbis_virtual_display_tests)
  set_tests_properties(integration.macos-virtual-display PROPERTIES LABELS "integration;appkit;freerdp" RUN_SERIAL TRUE)
  add_test(NAME integration.macos-keyboard-input COMMAND orbis_keyboard_input_tests)
  set_tests_properties(integration.macos-keyboard-input PROPERTIES LABELS "integration;appkit;freerdp")
endif()
find_library(NETWORK_FRAMEWORK Network REQUIRED)

# The asynchronous transport uses ARC independently of the existing MRC adapters.
add_library(orbis_tunnel STATIC
  ${PROJECT_SOURCE_DIR}/shared/Sources/Transport/OrbisTunnelBridge.m
  ${PROJECT_SOURCE_DIR}/shared/Sources/Transport/OrbisConnectionTransport.m
  ${PROJECT_SOURCE_DIR}/shared/Sources/Transport/OrbisDirectTransport.m
  ${PROJECT_SOURCE_DIR}/shared/Sources/Transport/OrbisCloudflareTransport.m
  ${PROJECT_SOURCE_DIR}/shared/Sources/Transport/OrbisTransportFactory.m
)
target_include_directories(orbis_tunnel PUBLIC ${PROJECT_SOURCE_DIR}/shared/Sources/Transport)
target_compile_options(orbis_tunnel PRIVATE -fobjc-arc -fblocks -Wall -Wextra)
target_link_libraries(orbis_tunnel PUBLIC ${FOUNDATION_FRAMEWORK} ${NETWORK_FRAMEWORK})

xctest_add_bundle(OrbisTunnelTests orbis_tunnel
  ${PROJECT_SOURCE_DIR}/shared/Tests/OrbisTunnelBridgeTests.m
  ${PROJECT_SOURCE_DIR}/shared/Tests/OrbisConnectionTransportTests.m
)
target_compile_options(OrbisTunnelTests PRIVATE -fobjc-arc -fblocks)
xctest_add_test(integration.tunnel OrbisTunnelTests)
set_tests_properties(integration.tunnel PROPERTIES
  LABELS "integration;xctest;shared;network"
  TIMEOUT 120
  ENVIRONMENT "ORBIS_TUNNEL_FIXTURE_PYTHON=${Python3_EXECUTABLE};ORBIS_TUNNEL_FIXTURE_SCRIPT=${PROJECT_SOURCE_DIR}/shared/Tests/Fixtures/tunnel_server.py"
)

add_library(
  orbis_shared
  STATIC
  ${PROJECT_SOURCE_DIR}/shared/Sources/About/OrbisAcknowledgements.m
  ${PROJECT_SOURCE_DIR}/shared/Sources/Profiles/OrbisProfile.m
  ${PROJECT_SOURCE_DIR}/shared/Sources/Profiles/OrbisDisplayLayout.c
  ${PROJECT_SOURCE_DIR}/shared/Sources/Security/OrbisCredentialStore.m
)
target_include_directories(
  orbis_shared
  PUBLIC
    ${PROJECT_SOURCE_DIR}/shared/Sources/About
    ${PROJECT_SOURCE_DIR}/shared/Sources/Profiles
    ${PROJECT_SOURCE_DIR}/shared/Sources/Security
)
target_compile_options(orbis_shared PRIVATE -fno-objc-arc)
target_link_libraries(
  orbis_shared
  PUBLIC
    ${FOUNDATION_FRAMEWORK}
    ${SECURITY_FRAMEWORK}
)


# Adapter selection shares the profile and credential store, outside the RDP session.
target_link_libraries(orbis_tunnel PUBLIC orbis_shared)

add_library(
  orbis_macos_ui
  STATIC
  ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisFormControls.m
  ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisDisplaySettings.m
  ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisInputCaptureSettings.m
  ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisAboutController.m
  ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisLibraryViewController.m
  ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisProfileEditorController.m
)
target_include_directories(
  orbis_macos_ui
  PUBLIC
    ${PROJECT_SOURCE_DIR}/macos/Sources
)
target_compile_options(orbis_macos_ui PRIVATE -fno-objc-arc -fblocks)
target_link_libraries(
  orbis_macos_ui
  PUBLIC
    orbis_shared
    orbis_tunnel
    ${APPKIT_FRAMEWORK}
    "-framework ApplicationServices"
    "-framework CoreGraphics"
)

add_executable(orbis_editing_tests
  ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisAppDelegate.m
  ${PROJECT_SOURCE_DIR}/macos/Tests/OrbisEditingTests.m)
target_compile_options(orbis_editing_tests PRIVATE -fno-objc-arc -fblocks)
target_link_libraries(orbis_editing_tests PRIVATE orbis_macos_ui)
add_test(NAME integration.macos-editing COMMAND orbis_editing_tests)
set_tests_properties(integration.macos-editing PROPERTIES LABELS "integration;appkit" RUN_SERIAL TRUE)

if(ORBIS_TEST_SPARKLE_ROOT)
  find_library(ORBIS_TEST_SPARKLE_FRAMEWORK Sparkle
    PATHS "${ORBIS_TEST_SPARKLE_ROOT}" NO_DEFAULT_PATH REQUIRED)
  add_executable(orbis_updater_session_tests
    ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisAppDelegate.m
    ${PROJECT_SOURCE_DIR}/macos/Tests/OrbisUpdaterSessionTests.m)
  target_compile_definitions(orbis_updater_session_tests PRIVATE ORBIS_ENABLE_UPDATES=1)
  target_compile_options(orbis_updater_session_tests PRIVATE -fno-objc-arc -fblocks)
  target_link_libraries(orbis_updater_session_tests PRIVATE orbis_macos_ui ${ORBIS_TEST_SPARKLE_FRAMEWORK})
  target_link_options(orbis_updater_session_tests PRIVATE "LINKER:-rpath,${ORBIS_TEST_SPARKLE_ROOT}")
  add_test(NAME integration.updater-session COMMAND orbis_updater_session_tests)
  set_tests_properties(integration.updater-session PROPERTIES LABELS "integration;release;appkit")
endif()

add_executable(
  orbis_retry_policy_tests
  ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisConnectionRetryPolicy.c
  ${PROJECT_SOURCE_DIR}/macos/Tests/OrbisConnectionRetryPolicyTests.c
)
target_include_directories(
  orbis_retry_policy_tests
  PRIVATE
    ${PROJECT_SOURCE_DIR}/macos/Sources
)
target_compile_features(orbis_retry_policy_tests PRIVATE c_std_11)
target_compile_options(orbis_retry_policy_tests PRIVATE -Wall -Wextra -Werror)
add_test(NAME unit.retry-policy COMMAND orbis_retry_policy_tests)
set_tests_properties(unit.retry-policy PROPERTIES LABELS "unit;pure-c")

add_executable(
  orbis_session_end_policy_tests
  ${PROJECT_SOURCE_DIR}/macos/Sources/OrbisSessionEndPolicy.c
  ${PROJECT_SOURCE_DIR}/macos/Tests/OrbisSessionEndPolicyTests.c
)
target_include_directories(
  orbis_session_end_policy_tests
  PRIVATE
    ${PROJECT_SOURCE_DIR}/macos/Sources
)
target_compile_features(orbis_session_end_policy_tests PRIVATE c_std_11)
target_compile_options(orbis_session_end_policy_tests PRIVATE -Wall -Wextra -Werror)
add_test(NAME unit.session-end-policy COMMAND orbis_session_end_policy_tests)
set_tests_properties(unit.session-end-policy PROPERTIES LABELS "unit;pure-c")

xctest_add_bundle(
  OrbisSharedTests
  orbis_shared
  ${PROJECT_SOURCE_DIR}/shared/Tests/OrbisSharedTests.m
)
target_compile_options(OrbisSharedTests PRIVATE -fno-objc-arc)
xctest_add_test(unit.shared OrbisSharedTests)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/test-homes/shared)
set_tests_properties(
  unit.shared
  PROPERTIES
    LABELS "unit;xctest;shared"
    ENVIRONMENT "CFFIXED_USER_HOME=${CMAKE_CURRENT_BINARY_DIR}/test-homes/shared"
)

xctest_add_bundle(
  OrbisMacLibraryTests
  orbis_macos_ui
  ${PROJECT_SOURCE_DIR}/macos/Tests/OrbisLibraryLayoutTests.m
)
target_compile_options(OrbisMacLibraryTests PRIVATE -fno-objc-arc -fblocks)
xctest_add_test(integration.macos-library OrbisMacLibraryTests)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/test-homes/macos-library)
set_tests_properties(
  integration.macos-library
  PROPERTIES
    LABELS "integration;xctest;appkit"
    RUN_SERIAL TRUE
    ENVIRONMENT "CFFIXED_USER_HOME=${CMAKE_CURRENT_BINARY_DIR}/test-homes/macos-library"
)

set(ORBIS_LEGACY_CONTRACT_TESTS
  test-orbis-card-animation.sh
  test-orbis-certificate-policy.sh
  test-orbis-macos-authentication.sh
  test-orbis-macos-clipboard.sh
  test-orbis-macos-connecting-overlay.sh
  test-orbis-macos-fullscreen-resolution.sh
  test-orbis-macos-keyboard.sh
  test-orbis-macos-session-end.sh
  test-orbis-macos-window-lifecycle.sh
  test-orbis-native-display.sh
  test-orbis-ux-contract.sh
)

foreach(test_script IN LISTS ORBIS_LEGACY_CONTRACT_TESTS)
  string(REGEX REPLACE "^test-orbis-|\\.sh$" "" test_name "${test_script}")
  add_test(
    NAME "contract.${test_name}"
    COMMAND ${PROJECT_SOURCE_DIR}/scripts/${test_script}
  )
  set_tests_properties(
    "contract.${test_name}"
    PROPERTIES
      WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
      LABELS "contract;legacy-source-check"
      RESOURCE_LOCK prepared-freerdp-tree
  )
endforeach()

add_test(
  NAME integration.repository-layout
  COMMAND ${PROJECT_SOURCE_DIR}/scripts/test-orbis-repository-layout.sh
)
set_tests_properties(
  integration.repository-layout
  PROPERTIES
    WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
    LABELS "integration;repository"
    RESOURCE_LOCK prepared-freerdp-tree
)
