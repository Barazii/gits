cmake_minimum_required(VERSION 3.14)
project(gits)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(CURL REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(ZIP REQUIRED libzip)

add_executable(gits gits.cpp)

# nlohmann/json (header-only): always use FetchContent for reliability
include(FetchContent)
FetchContent_Declare(
	nlohmann_json
	GIT_REPOSITORY https://github.com/nlohmann/json.git
	GIT_TAG v3.11.3
)
FetchContent_MakeAvailable(nlohmann_json)
target_link_libraries(gits PRIVATE nlohmann_json::nlohmann_json)

target_link_libraries(gits PRIVATE CURL::libcurl OpenSSL::SSL OpenSSL::Crypto ${ZIP_LIBRARIES})
target_include_directories(gits PRIVATE ${ZIP_INCLUDE_DIRS})
target_link_directories(gits PRIVATE ${ZIP_LIBRARY_DIRS})

install(TARGETS gits DESTINATION bin)

# ---------------- CPack (Debian package) ----------------
set(CPACK_GENERATOR "DEB")
set(CPACK_PACKAGE_NAME "gits")
set(CPACK_PACKAGE_VERSION "1.0.0")
set(CPACK_PACKAGE_CONTACT "MB mahmoud.baraziii@gmail.com")
set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
set(CPACK_DEBIAN_PACKAGE_SECTION "utils")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "libcurl4, libssl3 | openssl, libzip4, zlib1g")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "gits CLI tool")
set(CPACK_DEBIAN_ARCHITECTURE ${CMAKE_SYSTEM_PROCESSOR})
include(CPack)
