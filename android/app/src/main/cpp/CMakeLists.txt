cmake_minimum_required(VERSION 3.16)

project(gs1_composite_scanner LANGUAGES CXX)

set(GS1_ZXING_CPP_SRC_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/zxing-cpp"
    CACHE PATH "ZXing-C++ source used only by the native GS1 Composite scanner"
    FORCE
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED OFF)
set(CMAKE_CXX_EXTENSIONS OFF)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(ZXING_READERS ON CACHE BOOL "" FORCE)
set(ZXING_WRITERS OFF CACHE STRING "" FORCE)
set(ZXING_ENABLE_AZTEC OFF CACHE BOOL "" FORCE)
set(ZXING_ENABLE_DATAMATRIX OFF CACHE BOOL "" FORCE)
set(ZXING_ENABLE_MAXICODE OFF CACHE BOOL "" FORCE)
set(ZXING_ENABLE_QRCODE OFF CACHE BOOL "" FORCE)
set(ZXING_EXAMPLES OFF CACHE BOOL "" FORCE)
set(ZXING_BLACKBOX_TESTS OFF CACHE BOOL "" FORCE)
set(ZXING_UNIT_TESTS OFF CACHE BOOL "" FORCE)

add_subdirectory(
    "${GS1_ZXING_CPP_SRC_DIR}/core"
    "${CMAKE_CURRENT_BINARY_DIR}/zxing_core"
)

add_library(
    gs1_composite_scanner
    SHARED
    gs1_composite_scanner.cpp
)

target_include_directories(
    gs1_composite_scanner
    PRIVATE
    "${GS1_ZXING_CPP_SRC_DIR}/core/src"
)

target_link_libraries(gs1_composite_scanner PRIVATE ZXing)

if (ANDROID)
    find_library(log-lib log)
    target_link_libraries(gs1_composite_scanner PRIVATE ${log-lib})
    target_link_options(gs1_composite_scanner PRIVATE "-Wl,-z,max-page-size=16384")
endif ()
