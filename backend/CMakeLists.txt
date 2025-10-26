cmake_minimum_required(VERSION 3.10)
project(gits)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(CURL REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(ZIP REQUIRED libzip)

add_executable(gits gits.cpp)

target_link_libraries(gits CURL::libcurl OpenSSL::SSL OpenSSL::Crypto ${ZIP_LIBRARIES})
target_include_directories(gits PRIVATE ${ZIP_INCLUDE_DIRS})

install(TARGETS gits DESTINATION bin)
