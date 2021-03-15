# Docker --platform translation example for TARGETPLATFORM

Naming is hard. Having a consistent OS (kernel) and architecture naming scheme for building is harder. 

In Docker, our goal should be a single Dockerfile that can build for at least all Linux architectures, and eventually
across many kernels (Linux/Windows/Darwin) too.

Usually this problem rears its ugly head when you're trying to download pre-built binaries of various tools and 
dependencies (GitHub, etc.). Download URL's are inconsistently named, and expect some sort of kernel and architecture
combo in the file name. No one seems to agree on common naming.

Using `uname -m` won't work for architecture, as the name changes based on where it's running. For example, with 
arm64 (v8) architecture, it might say arm64, or aarch64. 

There's also the complexity that a device might have one architecture hardware (arm64) but run a different kernel 
(arm/v7 32-Bit). In this case you'll need to download the v7 binary.

The containerd project has 
[created their own conversion table](https://github.com/containerd/containerd/blob/master/platforms/platforms.go#L88-L94),
which I'm commenting on here
```
//   Value    Normalized
//   aarch64  arm64      # the latest v8 arm architecture. Used on Apple M1, AWS Graviton, and Raspberry Pi 3's and 4's
//   armhf    arm        # 32-bit v7 architecture. Used in Raspberry Pi 3 and  Pi 4 when 32bit Raspbian Linux is used
//   armel    arm/v6     # 32-bit v6 architecture. Used in Raspberry Pi 1, 2, and Zero
//   i386     386        # older Intel 32-Bit architecture, originally used in the 386 processor
//   x86_64   amd64      # all modern Intel-compatible x84 64-Bit architectures
//   x86-64   amd64      # same
```
So that's a start. BuildKit, which uses contained to run the containers, seems to do additional conversion, as
you'll see in the testing below.

For now, if we wanted to have a single Dockerfile build across x86-64, ARM 64-Bit, and ARM 32-Bit, we can use BuildKit
with the `TARGETPLATFORM` argument to get a more consistent environment variable in our `RUN` commands for predictable use, but it's not perfect. We'll still need to convert that output to what our RUN commands need.

`TARGETPLATFORM` is actually the combo of `TARGETOS`/`TARGETARCH`/`TARGETVARIANT` so in some cases you could use
those to help the situation, but as you can see below, the arm/v6 vs arm/v7 vs arm/v8 below can make all this tricky.
`TARGETARCH` is to general, and `ARGETVARIANT` may be blank (in the case of `arm64`).

For this Dockerfile:

```Dockerfile
FROM busybox
ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETVARIANT
RUN printf "I'm building for TARGETPLATFORM=${TARGETPLATFORM}" \
    && printf ", TARGETARCH=${TARGETARCH}" \
    && printf ", TARGETVARIANT=${TARGETVARIANT} \n" \
    && printf "With uname -s : " && uname -s \
    && printf "and  uname -m : " && uname -mm
```

Here are builds and results when using the command `docker buildx build --progress=plain --platform=<VALUE> .`:

1. `--platform=linux/amd64` and `--platform=linux/x86-64` and `--platform=linux/x86_64`

    ```
    I'm building for TARGETPLATFORM=linux/amd64, TARGETARCH=amd64, TARGETVARIANT=
    With uname -s : Linux
    and  uname -m : x86_64
    ```

2. `--platform=linux/arm64` NOTE: TARGETVARIANT is blank

    ```
    I'm building for TARGETPLATFORM=linux/arm64, TARGETARCH=arm64, TARGETVARIANT=
    With uname -s : Linux
    and  uname -m : aarch64
    ```

3. `--platform=linux/arm/v8` NOTE: I'd think this would be an alias to arm64, but it returns weird results

    ```
    I'm building for TARGETPLATFORM=linux/arm/v8, TARGETARCH=arm, TARGETVARIANT=v8
    With uname -s : Linux
    and  uname -m : armv7l
    ```

4. `--platform=linux/arm` and `--platform=linux/arm/v7` and `--platform=linux/armhf`

    ```
    I'm building for TARGETPLATFORM=linux/arm/v7, TARGETARCH=arm, TARGETVARIANT=v7
    With uname -s : Linux
    and  uname -m : armv7l
    ```

5. `--platform=linux/arm/v6` and `--platform=linux/armel`

    ```
    I'm building for TARGETPLATFORM=linux/arm/v6, TARGETARCH=arm, TARGETVARIANT=v6
    With uname -s : Linux
    and  uname -m : armv7l
    ```

4. `--platform=linux/i386` and `--platform=linux/386`

    ```
    I'm building for TARGETPLATFORM=linux/386, TARGETARCH=386, TARGETVARIANT=
    With uname -s : Linux
    and  uname -m : i686
    ```

## So what then, how do we proceed?

### Know what platforms you can build

First, you'll need to know what platforms your Docker Engine can build. Docker can support multi-platform builds with the `buildx` command. The [README is great](https://github.com/docker/buildx#building-multi-platform-images). By default it only supports the platform that Docker Engine (daemon) is running on, but if QEMU is installed, it can emulate many others. You can see the list it's currently enabled for with the `docker buildx inspect --bootstrap` command.  

For example, this is what I see in Docker Desktop on a Intel-based Mac and a Windows 10 with WSL2,
with `linux/amd64` being the native platform, and the rest using QEMU emulation:

`linux/amd64, linux/arm64, linux/riscv64, linux/ppc64le, linux/s390x, linux/386, linux/arm/v7, linux/arm/v6`

I see the same list in Docker Desktop on a Apple M1 Mac, with `linux/arm64` being the native platform, and the
rest using QEMU emulation:

`linux/arm64, linux/amd64, linux/riscv64, linux/ppc64le, linux/s390x, linux/386, linux/arm/v7, linux/arm/v6`

This is what I see in Docker for Linux on a Raspberry Pi 4 with Raspbian (32bit as of early 2021). QEMU isn't
enabled by default, so only the native options show up:

`linux/arm/v7, linux/arm/v6`

This is what I see in Docker for Linux on a Digital Ocean amd64 standard droplet. Notice again,
QEMU isn't setup so the list is much shorter:

`linux/amd64, linux/386`

### Add Dockerfile logic to detect the platform it needs to use

Let's use [tini](https://github.com/krallin/tini) as an example of how to ensure that a single Dockerfile and download the correct tini build into our container image 
for Linux on amd64, arm64, arm/v7, arm/v6, and i386. We'll use a separate build-stage, evaluate the
`TARGETPLATFORM`, and manually convert the value (via `sh case` statement) to what the specific binary URL needs.

This was inspired by @crazy-max in his [docker-in-docker Dockerfile](https://github.com/crazy-max/docker-docker/blob/1b0a1260bdbcb5931e07b5bc21e7bb0991101fda/Dockerfile-20.10#L12-L18).
FROM busybox as tini-binaries
RUN mkdir -p /opt/tini \
 && case ${TARGETPLATFORM} in \
         linux/amd64)  curl -L https://...amd64.bin -o /binary/tini;; \
         linux/arm64)  curl -L https://...arm64.bin -o /binary/tini;; \
    esac
...
FROM base as release
COPY --from tini-binaries /binary/tini /usr/local/bin/tini