# Base image for gitsops_lambda with pre-built AWS SDK and dependencies

FROM public.ecr.aws/lambda/provided:al2023

# Install build tools and dependencies
RUN dnf install -y cmake gcc-c++ git libcurl-devel openssl-devel zlib-devel

# Clone and build AWS SDK C++ (only required components)
RUN git clone --recurse-submodules https://github.com/aws/aws-sdk-cpp.git && \
    cd aws-sdk-cpp && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_ONLY="core;s3;eventbridge;dynamodb;secretsmanager" -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local -DENABLE_TESTING=OFF -DENABLE_UNITY_BUILD=ON && \
    make && make install

# Clone and build aws-lambda-cpp runtime
RUN git clone https://github.com/awslabs/aws-lambda-cpp.git && \
    cd aws-lambda-cpp && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local && \
    make && make install

# Clean up to reduce image size
RUN rm -rf aws-sdk-cpp aws-lambda-cpp
