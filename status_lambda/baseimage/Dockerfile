# Base image for status_lambda with pre-built AWS SDK and dependencies

# Pinned digest to ensure reproducible builds
FROM public.ecr.aws/lambda/provided:al2023@sha256:2feecc94e45a6c5fde2600d0d8ddaae7da001d5f0641e7bfbd027024b181fe9a

# Install build tools and dependencies
RUN dnf install -y cmake gcc-c++ git libcurl-devel openssl-devel zlib-devel

# Clone and build AWS SDK C++ (pinned version for reproducible builds)
RUN git clone --recurse-submodules --branch 1.11.709 --depth 1 https://github.com/aws/aws-sdk-cpp.git && \
    cd aws-sdk-cpp && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_ONLY="core;dynamodb" -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local -DENABLE_TESTING=OFF -DENABLE_UNITY_BUILD=ON && \
    make && make install

# Clone and build aws-lambda-cpp runtime (pinned version)
RUN git clone --branch v0.2.10 --depth 1 https://github.com/awslabs/aws-lambda-cpp.git && \
    cd aws-lambda-cpp && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local && \
    make && make install

# Clean up to reduce image size
RUN rm -rf aws-sdk-cpp aws-lambda-cpp
