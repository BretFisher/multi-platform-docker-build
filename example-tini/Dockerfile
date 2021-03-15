# example base image for your app
FROM debian as base

# default to the build platforms image, and not the target platform image
# since this is a temp image stage, we should avoid qemu for the binary download
# and only pull the alpine image once
FROM --platform=${BUILDPLATFORM} alpine as tini-binary
ENV TINI_VERSION=v0.19.0
# Use BuildKit to help translate architecture names
ARG TARGETPLATFORM
# translating Docker's TARGETPLATFORM into tini download names
RUN case ${TARGETPLATFORM} in \
         "linux/amd64")  TINI_ARCH=amd64  ;; \
         "linux/arm64")  TINI_ARCH=arm64  ;; \
         "linux/arm/v7") TINI_ARCH=armhf  ;; \
         "linux/arm/v6") TINI_ARCH=armel  ;; \
         "linux/386")    TINI_ARCH=i386   ;; \
    esac \
 && wget -q https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-${TINI_ARCH} -O /tini \
 && chmod +x /tini



# your final app image, copy tini into /usr/local/bin
FROM base as release
COPY --from=tini-binary /tini /usr/local/bin/tini
ENTRYPOINT ["/tini", "--"]

# Run your program under Tini
CMD ["/your/program", "-and", "-its", "arguments"]

