# Docker --platform translation example for TARGETPLATFORM

Naming is hard. Having a consistent OS (kernel) and architecture naming scheme for building is harder.

**Goal**: In Docker, our goal should be a single Dockerfile that can build for multiple Linux architectures.
A stretch-goal might be cross-OS (Windows Containers), but for now let's focus on the Linux kernel.

Turns out this might be harder then you're expecting.

Docker has BuildKit which makes this **much easier** with the `docker buildx build --platform` option, and
combined with the `ARG TARGETPLATFORM` gets us much closer to our goal. See the docs on
[multi-platform building](https://docs.docker.com/buildx/working-with-buildx/#build-multi-platform-images)
and the [automatic platform ARGs](https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope).

## The problem with downloading binaries in Dockerfiles

There are still inconsistencies we need to deal with. This problem rears its ugly head when you're
trying to download pre-built binaries of various tools and dependencies (GitHub, etc.) that don't use
a package manager (apt, yum, brew, apk, etc.).
Download URL's are inconsistently named, and expect some sort of kernel and architecture combo in the file name.
No one seems to agree on common file naming.

Using `uname -m` won't work for all architectures, as the name changes based on where it's running. For example, with
arm64 (v8) architecture, it might say arm64, or aarch64. In older arm devices it'll say armv71 even though you
might want arm/v6.

There's also the complexity that a device might have one architecture hardware (arm64) but run a different kernel (arm/v7 32-Bit).

The containerd project has
[created their own conversion table](https://github.com/containerd/containerd/blob/master/platforms/platforms.go#L88-L94),
which I'm commenting on here. This is similar to (but not exactly) what `ARG TARGETPLATFORM` gives us:

```bash
//   Value    Normalized
//   aarch64  arm64      # the latest v8 arm architecture. Used on Apple M1, AWS Graviton, and Raspberry Pi 3's and 4's
//   armhf    arm        # 32-bit v7 architecture. Used in Raspberry Pi 3 and  Pi 4 when 32bit Raspbian Linux is used
//   armel    arm/v6     # 32-bit v6 architecture. Used in Raspberry Pi 1, 2, and Zero
//   i386     386        # older Intel 32-Bit architecture, originally used in the 386 processor
//   x86_64   amd64      # all modern Intel-compatible x84 64-Bit architectures
//   x86-64   amd64      # same
```

So that's a start. But BuildKit seems to do additional conversion, as you'll see in the testing below.

## Recommended approach for curl and wget commands in multi-platform Dockerfiles

If we wanted to have a single Dockerfile build across (at minimum) x86-64, ARM 64-Bit, and ARM 32-Bit,
we can use BuildKit with the `TARGETPLATFORM` argument to get a more consistent environment variable in our
`RUN` commands, but it's not perfect. We'll still need to convert that output to what our `RUN` commands need.

`TARGETPLATFORM` is actually the combo of `TARGETOS`/`TARGETARCH`/`TARGETVARIANT` so in some cases you could use
those to help the situation, but as you can see below, the arm/v6 vs arm/v7 vs arm/v8 output can make all this
tricky. `TARGETARCH` is to general, and `ARGETVARIANT` may be blank (in the case of `arm64`).

So when I use `docker buildx build --platform`, what do I see inside the BuildKit environment?

Here's my results for this Dockerfile:

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

Here are the results when using the command `docker buildx build --progress=plain --platform=<VALUE> .`:

1. `--platform=linux/amd64` and `--platform=linux/x86-64` and `--platform=linux/x86_64`

    ```text
    I'm building for TARGETPLATFORM=linux/amd64, TARGETARCH=amd64, TARGETVARIANT=
    With uname -s : Linux
    and  uname -m : x86_64
    ```

2. `--platform=linux/arm64` and `--platform=linux/arm64/v8` **TARGETVARIANT is blank**

    ```text
    I'm building for TARGETPLATFORM=linux/arm64, TARGETARCH=arm64, TARGETVARIANT=
    With uname -s : Linux
    and  uname -m : aarch64
    ```

3. `--platform=linux/arm/v8` **Don't use this. It builds but is inconsistent.** I'd think this would be an alias to arm64, but it returns weird results (uname thinks it's 32bit, TARGETARCH is not arm64)

    ```text
    I'm building for TARGETPLATFORM=linux/arm/v8, TARGETARCH=arm, TARGETVARIANT=v8
    With uname -s : Linux
    and  uname -m : armv7l
    ```

4. `--platform=linux/arm` and `--platform=linux/arm/v7` and `--platform=linux/armhf`

    ```text
    I'm building for TARGETPLATFORM=linux/arm/v7, TARGETARCH=arm, TARGETVARIANT=v7
    With uname -s : Linux
    and  uname -m : armv7l
    ```

5. `--platform=linux/arm/v6` and `--platform=linux/armel`

    ```text
    I'm building for TARGETPLATFORM=linux/arm/v6, TARGETARCH=arm, TARGETVARIANT=v6
    With uname -s : Linux
    and  uname -m : armv7l
    ```

6. `--platform=linux/i386` and `--platform=linux/386`

    ```text
    I'm building for TARGETPLATFORM=linux/386, TARGETARCH=386, TARGETVARIANT=
    With uname -s : Linux
    and  uname -m : i686
    ```

## So what then, how do we proceed?

### Know what platforms you can build in your Docker Engine

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

Let's use [tini](https://github.com/krallin/tini) as an example of how to ensure that a single Dockerfile and download the correct tini build into our container image for Linux on amd64, arm64, arm/v7, arm/v6, and i386.
We'll use a separate build-stage, evaluate the `TARGETPLATFORM`, and manually convert the value
(via `sh case` statement) to what the specific binary URL needs.

This was inspired by @crazy-max in his [docker-in-docker Dockerfile](https://github.com/crazy-max/docker-docker/blob/1b0a1260bdbcb5931e07b5bc21e7bb0991101fda/Dockerfile-20.10#L12-L18).

See the full Dockerfile here: [example-tini\Dockerfile](example-tini\Dockerfile)

```Dockerfile
FROM --platform=${BUILDPLATFORM} alpine as tini-binary
ENV TINI_VERSION=v0.19.0
ARG TARGETPLATFORM
RUN case ${TARGETPLATFORM} in \
         "linux/amd64")  TINI_ARCH=amd64  ;; \
         "linux/arm64")  TINI_ARCH=arm64  ;; \
         "linux/arm/v7") TINI_ARCH=armhf  ;; \
         "linux/arm/v6") TINI_ARCH=armel  ;; \
         "linux/386")    TINI_ARCH=i386   ;; \
    esac \
 && wget -q https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-${TINI_ARCH} -O /tini \
 && chmod +x /tini
 ```

## Further Reading

Docker Blog from Adrian Mouat on [multi-platform Docker builds](https://www.docker.com/blog/multi-platform-docker-builds/).

## **MORE TO COME, WIP**

- [ ] Background on manifests, multi-architecture repos
- [ ] Using third-party tools like `regctl` to make your life easier (i.e. `regctl image manifest --list golang`)
- [ ] Breakdown the three parts of the platform ARG better
