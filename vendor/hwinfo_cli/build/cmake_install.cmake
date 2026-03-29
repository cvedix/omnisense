# Install script for directory: /home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "/usr/local")
endif()
string(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  if(BUILD_TYPE)
    string(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  else()
    set(CMAKE_INSTALL_CONFIG_NAME "")
  endif()
  message(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
endif()

# Set the component getting installed.
if(NOT CMAKE_INSTALL_COMPONENT)
  if(COMPONENT)
    message(STATUS "Install component: \"${COMPONENT}\"")
    set(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  else()
    set(CMAKE_INSTALL_COMPONENT)
  endif()
endif()

# Install shared libraries without execute permission?
if(NOT DEFINED CMAKE_INSTALL_SO_NO_EXE)
  set(CMAKE_INSTALL_SO_NO_EXE "1")
endif()

# Is this installation the result of a crosscompile?
if(NOT DEFINED CMAKE_CROSSCOMPILING)
  set(CMAKE_CROSSCOMPILING "FALSE")
endif()

# Set default install directory permissions.
if(NOT DEFINED CMAKE_OBJDUMP)
  set(CMAKE_OBJDUMP "/usr/bin/objdump")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for the subdirectory.
  include("/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/build/hwinfo/cmake_install.cmake")
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  if(EXISTS "$ENV{DESTDIR}/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/../../ui/priv/bin/hwinfo_cli" AND
     NOT IS_SYMLINK "$ENV{DESTDIR}/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/../../ui/priv/bin/hwinfo_cli")
    file(RPATH_CHECK
         FILE "$ENV{DESTDIR}/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/../../ui/priv/bin/hwinfo_cli"
         RPATH "")
  endif()
  list(APPEND CMAKE_ABSOLUTE_DESTINATION_FILES
   "/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/../../ui/priv/bin/hwinfo_cli")
  if(CMAKE_WARN_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(WARNING "ABSOLUTE path INSTALL DESTINATION : ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  if(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION)
    message(FATAL_ERROR "ABSOLUTE path INSTALL DESTINATION forbidden (by caller): ${CMAKE_ABSOLUTE_DESTINATION_FILES}")
  endif()
  file(INSTALL DESTINATION "/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/../../ui/priv/bin" TYPE EXECUTABLE FILES "/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/build/hwinfo_cli")
  if(EXISTS "$ENV{DESTDIR}/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/../../ui/priv/bin/hwinfo_cli" AND
     NOT IS_SYMLINK "$ENV{DESTDIR}/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/../../ui/priv/bin/hwinfo_cli")
    file(RPATH_CHANGE
         FILE "$ENV{DESTDIR}/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/../../ui/priv/bin/hwinfo_cli"
         OLD_RPATH "/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/build:"
         NEW_RPATH "")
    if(CMAKE_INSTALL_DO_STRIP)
      execute_process(COMMAND "/usr/bin/strip" "$ENV{DESTDIR}/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/../../ui/priv/bin/hwinfo_cli")
    endif()
  endif()
endif()

if(CMAKE_INSTALL_COMPONENT STREQUAL "Unspecified" OR NOT CMAKE_INSTALL_COMPONENT)
  include("/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/build/CMakeFiles/hwinfo_cli.dir/install-cxx-module-bmi-noconfig.cmake" OPTIONAL)
endif()

if(CMAKE_INSTALL_COMPONENT)
  set(CMAKE_INSTALL_MANIFEST "install_manifest_${CMAKE_INSTALL_COMPONENT}.txt")
else()
  set(CMAKE_INSTALL_MANIFEST "install_manifest.txt")
endif()

string(REPLACE ";" "\n" CMAKE_INSTALL_MANIFEST_CONTENT
       "${CMAKE_INSTALL_MANIFEST_FILES}")
file(WRITE "/home/cvedix/Documents/Github/omnisense/vendor/hwinfo_cli/build/${CMAKE_INSTALL_MANIFEST}"
     "${CMAKE_INSTALL_MANIFEST_CONTENT}")
