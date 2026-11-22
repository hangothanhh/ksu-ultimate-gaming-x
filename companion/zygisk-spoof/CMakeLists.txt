cmake_minimum_required(VERSION 3.22.1)
project(kgx_zygisk_spoof LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Provide path to zygisk.hpp from KernelSU/ZygiskNext/ReZygisk SDK
set(ZYGISK_HEADER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/include" CACHE PATH "Directory containing zygisk.hpp")

add_library(kgx_zygisk_spoof SHARED
    src/main.cpp
)

target_include_directories(kgx_zygisk_spoof PRIVATE "${ZYGISK_HEADER_DIR}")

target_compile_options(kgx_zygisk_spoof PRIVATE
    -O2
    -fvisibility=hidden
    -fno-exceptions
    -fno-rtti
    -Wall
    -Wextra
)

target_link_options(kgx_zygisk_spoof PRIVATE -static-libstdc++)
target_link_libraries(kgx_zygisk_spoof PRIVATE log dl)
