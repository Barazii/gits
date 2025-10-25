# Use official AWS Lambda base image
FROM public.ecr.aws/lambda/provided:al2023 AS builder

# Install build tools
RUN dnf install -y cmake gcc-c++ git libcurl-devel openssl-devel zlib-devel

# Clone and build AWS SDK C++
RUN git clone --recurse-submodules https://github.com/aws/aws-sdk-cpp.git && \
    cd aws-sdk-cpp && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_ONLY="core;dynamodb" -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local -DENABLE_TESTING=OFF -DENABLE_UNITY_BUILD=ON &&\
    make && make install

# Clone and build aws-lambda-cpp runtime
RUN git clone https://github.com/awslabs/aws-lambda-cpp.git && \
    cd aws-lambda-cpp && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local && \
    make && make install

# Create app directory
RUN mkdir -p /app

# Copy source
COPY lambda_function.cpp /app/
COPY CMakeLists.txt /app/
WORKDIR /app

# Build
RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=/usr/local && \
    cmake --build . --config Release

# Final image
FROM public.ecr.aws/lambda/provided:al2023
COPY --from=builder /app/build/bootstrap /var/runtime/bootstrap

CMD ["bootstrap"]
