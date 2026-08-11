# SPDX-License-Identifier: MIT

if(NOT APPLE)
  message(FATAL_ERROR "The Orbis native test suite requires macOS")
endif()

find_library(APPKIT_FRAMEWORK AppKit REQUIRED)
find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
find_library(SECURITY_FRAMEWORK Security REQUIRED)
find_package(XCTest REQUIRED)

add_library(
  orbis_shared
  STATIC
  ${PROJECT_SOURCE_DIR}/shared/Sources/About/OrbisAcknowledgements.m
  ${PROJECT_SOURCE_DIR}/shared/Sources/Profiles/OrbisProfile.m
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

add_library(
  orbis_macos_ui
  STATIC
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
    ${APPKIT_FRAMEWORK}
)

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
set_tests_properties(
  integration.macos-library
  PROPERTIES
    LABELS "integration;xctest;appkit"
    RUN_SERIAL TRUE
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
