FROM busybox

# this shows us what various BuildKit arguments are based on the 
# docker buildx build --platform= option you give Docker.

ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETVARIANT
RUN printf '..%s..' "I'm building for TARGETPLATFORM=${TARGETPLATFORM}" \
    && printf '..%s..' ", TARGETARCH=${TARGETARCH}" \
    && printf '..%s..' ", TARGETVARIANT=${TARGETVARIANT} \n" \
    && printf '..%s..' "With uname -s : " && uname -s \
    && printf '..%s..' "and  uname -m : " && uname -m
