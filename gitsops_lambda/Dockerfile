# Use the custom base image (build and push baseimage/Dockerfile to ECR first)
FROM 482497089777.dkr.ecr.eu-north-1.amazonaws.com/gitsops-lambda-base:latest AS builder

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