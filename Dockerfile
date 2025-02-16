FROM busybox

# this shows us what various BuildKit arguments are based on the 
# docker buildx build --platform= option you give Docker.

# For best output results, build with --progress=plain --no-cache

ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETVARIANT
RUN printf "NOTE: docker build --progress=plain --no-cache --platform=<YOUR-TARGET-PLATFORM>"
RUN printf "TARGETPLATFORM=${TARGETPLATFORM}"
RUN printf "TARGETARCH=${TARGETARCH}"
RUN printf "TARGETVARIANT=${TARGETVARIANT}"
RUN printf "With uname -s : " && uname -s
RUN printf "and  uname -m : " && uname -m
