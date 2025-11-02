cmake_minimum_required(VERSION 3.16)
project(MyCppLambda LANGUAGES CXX)

find_package(ZLIB REQUIRED)
find_package(aws-lambda-runtime REQUIRED)
find_package(AWSSDK REQUIRED COMPONENTS s3 eventbridge dynamodb secretsmanager)
include_directories(/usr/local/include)
include_directories(${AWSSDK_INCLUDE_DIRS})
add_executable(bootstrap lambda_function.cpp)
target_link_libraries(bootstrap PUBLIC AWS::aws-lambda-runtime ${AWSSDK_LINK_LIBRARIES} ZLIB::ZLIB)
target_include_directories(bootstrap PUBLIC /usr/local/include ${AWSSDK_INCLUDE_DIRS})
target_compile_features(bootstrap PUBLIC cxx_std_17)

# Lambda expects executable named 'bootstrap'
set_target_properties(bootstrap PROPERTIES OUTPUT_NAME bootstrap)