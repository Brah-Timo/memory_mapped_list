cmake_minimum_required(VERSION 3.14)
project(mml_native C)

set(CMAKE_C_STANDARD 11)

# Optimisation flags
if(MSVC)
  add_compile_options(/O2 /W3)
else()
  add_compile_options(-O2 -Wall -Wextra -fPIC)
endif()

# Shared library target
add_library(mml_native SHARED mml_native.c)

# Platform-specific linker settings
if(UNIX AND NOT APPLE)
  target_link_libraries(mml_native m)
endif()

if(APPLE)
  set_target_properties(mml_native PROPERTIES
    MACOSX_RPATH TRUE
    SUFFIX ".dylib"
  )
endif()

# Install to lib/src/ffi/native/ inside the package
install(
  TARGETS mml_native
  LIBRARY DESTINATION "${CMAKE_SOURCE_DIR}"
  RUNTIME DESTINATION "${CMAKE_SOURCE_DIR}"
)

message(STATUS "mml_native build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "Output directory: ${CMAKE_BINARY_DIR}")
