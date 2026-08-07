cmake_minimum_required(VERSION 3.25)

project(zisla_windows LANGUAGES C CXX)

set(CMAKE_CXX_EXTENSIONS OFF)

option(
    ZISLA_ENABLE_QPDF_ADAPTER
    "Build the QPDF-backed PDF structure adapter"
    OFF
)
option(
    ZISLA_ENABLE_PDFIUM_ADAPTER
    "Build the fixed PDFium-backed text and rendering adapter"
    OFF
)
set(
    ZISLA_QPDF_PACKAGE_DIR
    ""
    CACHE PATH
    "Directory containing the fixed QPDF 12.3.2 CMake package"
)
set(
    ZISLA_PDFIUM_PACKAGE_DIR
    ""
    CACHE PATH
    "Directory containing the fixed PDFium 153.0.7988.0 CMake package"
)

add_library(zisla_yyjson STATIC
    Vendor/yyjson/0.12.0/src/yyjson.c
)
set_source_files_properties(
    Vendor/yyjson/0.12.0/src/yyjson.c
    PROPERTIES LANGUAGE CXX
)
target_compile_features(zisla_yyjson PUBLIC cxx_std_20)
target_include_directories(zisla_yyjson
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/Vendor/yyjson/0.12.0/src
)
target_compile_definitions(zisla_yyjson
    PUBLIC
        YYJSON_DISABLE_INCR_READER=1
        YYJSON_DISABLE_NON_STANDARD=1
        YYJSON_DISABLE_UTILS=1
)

add_library(zisla_sqlite STATIC
    Vendor/sqlite/3.53.4/sqlite3.c
)
target_include_directories(zisla_sqlite
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/Vendor/sqlite/3.53.4
)
target_compile_definitions(zisla_sqlite
    PUBLIC
        SQLITE_DQS=0
        SQLITE_OMIT_LOAD_EXTENSION=1
        SQLITE_THREADSAFE=1
)

add_subdirectory(Core)

if(ZISLA_ENABLE_QPDF_ADAPTER)
    if(NOT ZISLA_QPDF_PACKAGE_DIR)
        message(FATAL_ERROR
            "ZISLA_ENABLE_QPDF_ADAPTER requires ZISLA_QPDF_PACKAGE_DIR from the fixed vendored QPDF build")
    endif()
    find_package(
        qpdf
        12.3.2
        EXACT
        CONFIG
        REQUIRED
        PATHS "${ZISLA_QPDF_PACKAGE_DIR}"
        NO_DEFAULT_PATH
    )
    get_filename_component(
        ZISLA_QPDF_LIBRARY_DIR
        "${ZISLA_QPDF_PACKAGE_DIR}/../.."
        ABSOLUTE
    )
endif()

if(ZISLA_ENABLE_PDFIUM_ADAPTER)
    if(NOT ZISLA_PDFIUM_PACKAGE_DIR)
        message(FATAL_ERROR
            "ZISLA_ENABLE_PDFIUM_ADAPTER requires ZISLA_PDFIUM_PACKAGE_DIR from the fixed vendored PDFium package")
    endif()
    set(ZLIB_BUILD_TESTING OFF CACHE BOOL "" FORCE)
    set(ZLIB_BUILD_SHARED OFF CACHE BOOL "" FORCE)
    set(ZLIB_BUILD_STATIC ON CACHE BOOL "" FORCE)
    set(ZLIB_INSTALL OFF CACHE BOOL "" FORCE)
    add_subdirectory(Vendor/zlib/1.3.2 EXCLUDE_FROM_ALL)
    include(ExternalProject)
    set(ZISLA_JPEG_BUILD_DIR "${CMAKE_BINARY_DIR}/vendor/libjpeg-turbo")
    set(ZISLA_JPEG_OUTPUT_DIR "${ZISLA_JPEG_BUILD_DIR}/artifacts")
    file(MAKE_DIRECTORY "${ZISLA_JPEG_BUILD_DIR}")
    file(MAKE_DIRECTORY "${ZISLA_JPEG_OUTPUT_DIR}")
    set(
        ZISLA_JPEG_LIBRARY
        "${ZISLA_JPEG_OUTPUT_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}jpeg${CMAKE_STATIC_LIBRARY_SUFFIX}"
    )
    ExternalProject_Add(
        zisla_libjpeg_turbo
        SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/libjpeg-turbo/3.2.0"
        BINARY_DIR "${ZISLA_JPEG_BUILD_DIR}"
        INSTALL_COMMAND ""
        CMAKE_ARGS
            "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
            "-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY=${ZISLA_JPEG_OUTPUT_DIR}"
            "-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY_DEBUG=${ZISLA_JPEG_OUTPUT_DIR}"
            "-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELEASE=${ZISLA_JPEG_OUTPUT_DIR}"
            "-DENABLE_SHARED=OFF"
            "-DENABLE_STATIC=ON"
            "-DWITH_TURBOJPEG=OFF"
            "-DWITH_TESTS=OFF"
            "-DWITH_TOOLS=OFF"
            "-DWITH_JPEG8=ON"
        BUILD_BYPRODUCTS "${ZISLA_JPEG_LIBRARY}"
    )
    add_library(zisla_jpeg_static STATIC IMPORTED GLOBAL)
    set_target_properties(zisla_jpeg_static PROPERTIES
        IMPORTED_LOCATION "${ZISLA_JPEG_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES
            "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/libjpeg-turbo/3.2.0/src;${ZISLA_JPEG_BUILD_DIR}"
    )
    add_dependencies(zisla_jpeg_static zisla_libjpeg_turbo)
    find_package(
        PDFium
        CONFIG
        REQUIRED
        PATHS "${ZISLA_PDFIUM_PACKAGE_DIR}"
        NO_DEFAULT_PATH
    )
    if(NOT PDFium_VERSION STREQUAL "153.0.7988.0")
        message(FATAL_ERROR "Expected fixed PDFium 153.0.7988.0, found ${PDFium_VERSION}")
    endif()
endif()

if(ZISLA_ENABLE_QPDF_ADAPTER OR ZISLA_ENABLE_PDFIUM_ADAPTER)
    add_subdirectory(PDF)
endif()

if(WIN32)
    add_executable(zislactl CLI/main.cpp)
    target_compile_features(zislactl PRIVATE cxx_std_20)
    target_link_libraries(zislactl PRIVATE zisla_windows_core shell32 ole32)
    target_compile_options(zislactl PRIVATE /W4 /WX /permissive- /utf-8)
endif()

include(CTest)
if(BUILD_TESTING)
    add_subdirectory(Tests)
endif()
