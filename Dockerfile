ARG GOLANG_VERSION=1.22.5
ARG CMAKE_VERSION=3.22.1
ARG CUDA_VERSION_11=11.3.1
ARG CUDA_V11_ARCHITECTURES="50;52;53;60;61;62;70;72;75;80;86"
ARG CUDA_VERSION_12=12.4.0
ARG CUDA_V12_ARCHITECTURES="60;61;62;70;72;75;80;86;87;89;90;90a"
ARG ROCM_VERSION=6.1.2

# Copy the minimal context we need to run the generate scripts
FROM scratch AS llm-code
COPY .git .git
COPY .gitmodules .gitmodules
COPY llm llm

FROM --platform=linux/amd64 centos:7 AS cpu-builder-amd64
ARG CMAKE_VERSION
ARG GOLANG_VERSION
COPY ./scripts/rh_linux_deps.sh /
RUN CMAKE_VERSION=${CMAKE_VERSION} GOLANG_VERSION=${GOLANG_VERSION} sh /rh_linux_deps.sh
ENV PATH=/opt/rh/devtoolset-10/root/usr/bin:$PATH
COPY --from=llm-code / /go/src/github.com/ollama/ollama/
ARG OLLAMA_CUSTOM_CPU_DEFS
ARG CGO_CFLAGS
ENV GOARCH=amd64
WORKDIR /go/src/github.com/ollama/ollama/llm/generate

FROM --platform=linux/amd64 cpu-builder-amd64 AS static-build-amd64
RUN --mount=type=cache,target=/root/.ccache \
    OLLAMA_CPU_TARGET="static" bash gen_linux.sh
FROM --platform=linux/amd64 cpu-builder-amd64 AS cpu-build-amd64
RUN --mount=type=cache,target=/root/.ccache \
    OLLAMA_SKIP_STATIC_GENERATE=1 OLLAMA_CPU_TARGET="cpu" bash gen_linux.sh
FROM --platform=linux/amd64 cpu-builder-amd64 AS cpu_avx-build-amd64
RUN --mount=type=cache,target=/root/.ccache \
    OLLAMA_SKIP_STATIC_GENERATE=1 OLLAMA_CPU_TARGET="cpu_avx" bash gen_linux.sh
FROM --platform=linux/amd64 cpu-builder-amd64 AS cpu_avx2-build-amd64
RUN --mount=type=cache,target=/root/.ccache \
    OLLAMA_SKIP_STATIC_GENERATE=1 OLLAMA_CPU_TARGET="cpu_avx2" bash gen_linux.sh

FROM --platform=linux/arm64 rockylinux:8 AS cpu-builder-arm64
ARG CMAKE_VERSION
ARG GOLANG_VERSION
COPY ./scripts/rh_linux_deps.sh /
RUN CMAKE_VERSION=${CMAKE_VERSION} GOLANG_VERSION=${GOLANG_VERSION} sh /rh_linux_deps.sh
ENV PATH=/opt/rh/gcc-toolset-10/root/usr/bin:$PATH
COPY --from=llm-code / /go/src/github.com/ollama/ollama/
ARG OLLAMA_CUSTOM_CPU_DEFS
ARG CGO_CFLAGS
ENV GOARCH=arm64
WORKDIR /go/src/github.com/ollama/ollama/llm/generate

FROM --platform=linux/arm64 cpu-builder-arm64 AS static-build-arm64
RUN --mount=type=cache,target=/root/.ccache \
    OLLAMA_CPU_TARGET="static" bash gen_linux.sh
FROM --platform=linux/arm64 cpu-builder-arm64 AS cpu-build-arm64
RUN --mount=type=cache,target=/root/.ccache \
    OLLAMA_SKIP_STATIC_GENERATE=1 OLLAMA_CPU_TARGET="cpu" bash gen_linux.sh


# Intermediate stages used for ./scripts/build_linux.sh
FROM --platform=linux/amd64 cpu-build-amd64 AS build-amd64
ENV CGO_ENABLED=1
WORKDIR /go/src/github.com/ollama/ollama
COPY . .
COPY --from=static-build-amd64 /go/src/github.com/ollama/ollama/llm/build/ llm/build/
COPY --from=cpu_avx-build-amd64 /go/src/github.com/ollama/ollama/build/ build/
COPY --from=cpu_avx2-build-amd64 /go/src/github.com/ollama/ollama/build/ build/
ARG GOFLAGS
ARG CGO_CFLAGS
RUN --mount=type=cache,target=/root/.ccache \
    go build -trimpath -o dist/linux-amd64/bin/ollama .
RUN cd dist/linux-$GOARCH && \
    tar --exclude runners -cf - . | pigz --best > ../ollama-linux-$GOARCH.tgz

FROM --platform=linux/arm64 cpu-build-arm64 AS build-arm64
ENV CGO_ENABLED=1
ARG GOLANG_VERSION
WORKDIR /go/src/github.com/ollama/ollama
COPY . .
COPY --from=static-build-arm64 /go/src/github.com/ollama/ollama/llm/build/ llm/build/
ARG GOFLAGS
ARG CGO_CFLAGS
RUN --mount=type=cache,target=/root/.ccache \
    go build -trimpath -o dist/linux-arm64/bin/ollama .
RUN cd dist/linux-$GOARCH && \
    tar --exclude runners -cf - . | pigz --best > ../ollama-linux-$GOARCH.tgz

FROM --platform=linux/amd64 scratch AS dist-amd64
COPY --from=build-amd64 /go/src/github.com/ollama/ollama/dist/ollama-linux-*.tgz /
FROM --platform=linux/arm64 scratch AS dist-arm64
COPY --from=build-arm64 /go/src/github.com/ollama/ollama/dist/ollama-linux-*.tgz /
FROM dist-$TARGETARCH as dist


# Optimized container images do not cary nested payloads
FROM --platform=linux/amd64 static-build-amd64 AS container-build-amd64
WORKDIR /go/src/github.com/ollama/ollama
COPY . .
ARG GOFLAGS
ARG CGO_CFLAGS
RUN --mount=type=cache,target=/root/.ccache \
    go build -trimpath -o dist/linux-amd64/bin/ollama .

FROM --platform=linux/arm64 static-build-arm64 AS container-build-arm64
WORKDIR /go/src/github.com/ollama/ollama
COPY . .
ARG GOFLAGS
ARG CGO_CFLAGS
RUN --mount=type=cache,target=/root/.ccache \
    go build -trimpath -o dist/linux-arm64/bin/ollama .

FROM --platform=linux/amd64 ubuntu:22.04 AS runtime-amd64
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --from=container-build-amd64 /go/src/github.com/ollama/ollama/dist/linux-amd64/bin/ /bin/
COPY --from=cpu-build-amd64 /go/src/github.com/ollama/ollama/dist/linux-amd64/lib/ /lib/
COPY --from=cpu_avx-build-amd64 /go/src/github.com/ollama/ollama/dist/linux-amd64/lib/ /lib/
COPY --from=cpu_avx2-build-amd64 /go/src/github.com/ollama/ollama/dist/linux-amd64/lib/ /lib/

FROM --platform=linux/arm64 ubuntu:22.04 AS runtime-arm64
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --from=container-build-arm64 /go/src/github.com/ollama/ollama/dist/linux-arm64/bin/ /bin/
COPY --from=cpu-build-arm64 /go/src/github.com/ollama/ollama/dist/linux-arm64/lib/ /lib/

FROM runtime-$TARGETARCH
EXPOSE 11434
ENV OLLAMA_HOST=0.0.0.0
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_VISIBLE_DEVICES=all

ENTRYPOINT ["/bin/ollama"]
CMD ["serve"]
