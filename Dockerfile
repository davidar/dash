ARG TAG=latest

FROM davidar/sabotage AS sabotage-amd64
SHELL [ "/bin/linux64", "/bin/sh", "-c" ]
FROM davidar/sabotage AS sabotage-386
SHELL [ "/bin/linux32", "/bin/sh", "-c" ]
FROM sabotage-$TARGETARCH AS build-latest
RUN butch install samurai

FROM davidar/bootsh:latest AS build-stage0
FROM davidar/bootsh:stage0 AS build-stage1
FROM davidar/bootsh:stage1 AS build-stage2

FROM build-$TAG AS build
COPY tarballs /src/tarballs
WORKDIR /tmp
COPY configure Makefile bootsh/
COPY scripts bootsh/scripts
COPY src bootsh/src
COPY lib bootsh/lib
RUN cd bootsh && CFLAGS=-Werror ./configure && samu && DESTDIR=/dest scripts/install.sh

FROM alpine AS cpio
RUN apk add xz
COPY --from=build /dest /dest
RUN cd /dest && find . | cpio -H newc -o | xz --check=crc32 -9 --lzma2=dict=1MiB | \
    dd conv=sync bs=512 of=/initramfs.cpio.xz

FROM build-latest AS kernel
RUN apk add perl gmp-dev mpc1-dev mpfr-dev elfutils-dev bash flex bison zstd
RUN apk add sed installkernel bc linux-headers linux-firmware-any openssl-dev mawk diffutils findutils zstd pahole python3 gcc
ADD https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.9.5.tar.xz /
RUN tar -xf linux-6.9.5.tar.xz
WORKDIR /linux-6.9.5
COPY linux-6.9.config .config
RUN make -j$(nproc) ARCH=x86 bzImage && cp -f arch/x86/boot/bzImage /

FROM scratch AS output
COPY --from=cpio /initramfs.cpio.xz /
COPY --from=kernel /bzImage /

FROM scratch AS bootsh
COPY --from=build /dest /
ENTRYPOINT [ "/bin/init" ]
CMD [ "/bin/sh" ]
SHELL [ "/bin/init", "/bin/sh", "-c" ]
