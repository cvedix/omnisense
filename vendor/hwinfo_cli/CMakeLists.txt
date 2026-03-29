cmake_minimum_required(VERSION 3.14)
project(hwinfo_cli LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add hwinfo as subdirectory
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../hwinfo ${CMAKE_CURRENT_BINARY_DIR}/hwinfo)

add_executable(hwinfo_cli main.cpp)
target_link_libraries(hwinfo_cli PRIVATE hwinfo)

# Install to project bin directory
install(TARGETS hwinfo_cli DESTINATION ${CMAKE_CURRENT_SOURCE_DIR}/../../ui/priv/bin)
