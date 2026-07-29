cmake_minimum_required(VERSION 3.25)

project(CadReaderNative VERSION 0.1.0 LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum macOS version")
set(CMAKE_XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES)

find_path(LIBREDWG_INCLUDE_DIR dwg.h
  PATHS /opt/homebrew/opt/libredwg/include /usr/local/opt/libredwg/include
  REQUIRED
)
find_library(LIBREDWG_LIBRARY redwg
  PATHS /opt/homebrew/opt/libredwg/lib /usr/local/opt/libredwg/lib
  REQUIRED
)
get_filename_component(LIBREDWG_LIBRARY_REAL "${LIBREDWG_LIBRARY}" REALPATH)

add_executable(CadReader MACOSX_BUNDLE
  src/main.mm
  src/CadModel.cpp
)

target_include_directories(CadReader PRIVATE
  src
  ${LIBREDWG_INCLUDE_DIR}
)

target_compile_options(CadReader PRIVATE
  -Wall
  -Wextra
  -Wno-deprecated-declarations
  $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>
)

target_link_libraries(CadReader PRIVATE
  ${LIBREDWG_LIBRARY}
  "-framework AppKit"
  "-framework Metal"
  "-framework MetalKit"
  "-framework QuartzCore"
)

add_executable(CadReaderProbe
  src/probe.cpp
  src/CadModel.cpp
)
target_include_directories(CadReaderProbe PRIVATE
  src
  ${LIBREDWG_INCLUDE_DIR}
)
target_link_libraries(CadReaderProbe PRIVATE ${LIBREDWG_LIBRARY})

add_custom_command(TARGET CadReader POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:CadReader>/Contents/Frameworks"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "${LIBREDWG_LIBRARY_REAL}"
          "$<TARGET_BUNDLE_DIR:CadReader>/Contents/Frameworks/libredwg.0.dylib"
  COMMAND install_name_tool -change
          "/opt/homebrew/opt/libredwg/lib/libredwg.0.dylib"
          "@executable_path/../Frameworks/libredwg.0.dylib"
          "$<TARGET_FILE:CadReader>"
  COMMAND install_name_tool -id
          "@rpath/libredwg.0.dylib"
          "$<TARGET_BUNDLE_DIR:CadReader>/Contents/Frameworks/libredwg.0.dylib"
)

set_target_properties(CadReader PROPERTIES
  MACOSX_BUNDLE_BUNDLE_NAME "CadReader"
  MACOSX_BUNDLE_GUI_IDENTIFIER "com.local.cadreader"
  MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
  MACOSX_BUNDLE_BUNDLE_VERSION "1"
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.local.cadreader"
)
