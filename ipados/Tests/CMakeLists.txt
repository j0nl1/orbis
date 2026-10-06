# SPDX-License-Identifier: MIT

execute_process(COMMAND xcrun --sdk iphonesimulator --show-sdk-platform-path
  OUTPUT_VARIABLE ORBIS_SIMULATOR_PLATFORM OUTPUT_STRIP_TRAILING_WHITESPACE
  COMMAND_ERROR_IS_FATAL ANY)
set(ORBIS_XCTEST_FRAMEWORKS "${ORBIS_SIMULATOR_PLATFORM}/Developer/Library/Frameworks")
add_library(OrbisIPadTests MODULE OrbisIPadTests.m ${ORBIS_SHARED_DIR}/Tests/OrbisDiagnosticsTests.m)
set_source_files_properties(${ORBIS_SHARED_DIR}/Tests/OrbisDiagnosticsTests.m PROPERTIES COMPILE_OPTIONS "-fobjc-arc;-fblocks")
# Xcode installs app-hosted tests relative to the host app in this build directory.
set_target_properties(OrbisIPadTests PROPERTIES
  BUNDLE TRUE BUNDLE_EXTENSION xctest PREFIX ""
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/$<CONFIG>\${EFFECTIVE_PLATFORM_NAME}"
  XCODE_PRODUCT_TYPE com.apple.product-type.bundle.unit-test
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER com.dnexus.orbis.tests
  XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE YES
  XCODE_ATTRIBUTE_SDKROOT iphonesimulator
  XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS iphonesimulator
  XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET 26.0
  XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY 2
  XCODE_ATTRIBUTE_TEST_HOST "$<TARGET_FILE:iFreeRDP>"
  XCODE_ATTRIBUTE_BUNDLE_LOADER "$(TEST_HOST)"
  XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "-"
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED YES
  XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED YES)
add_dependencies(OrbisIPadTests iFreeRDP)
target_compile_options(OrbisIPadTests PRIVATE -fno-objc-arc -fblocks "-F${ORBIS_XCTEST_FRAMEWORKS}")
target_link_options(OrbisIPadTests PRIVATE "-F${ORBIS_XCTEST_FRAMEWORKS}")
target_link_libraries(OrbisIPadTests PRIVATE "-framework XCTest" ${UIKIT_FRAMEWORK} ${COREGRAPHICS_FRAMEWORK} freerdp3-lib freerdp-client3-lib winpr3-lib)
