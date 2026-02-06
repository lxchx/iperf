FROM debian:stretch AS build

# Debian 9 (stretch) is archived; point apt at archive.debian.org and disable
# Valid-Until checks so `apt-get update` keeps working.
RUN set -eux; \
    # Debian stretch is archived; avoid stretch-updates (not present in archive).
    # Keep base + security archive repos only.
    printf '%s\n' \
      'deb http://archive.debian.org/debian stretch main' \
      'deb http://archive.debian.org/debian-security stretch/updates main' \
      > /etc/apt/sources.list; \
    printf '%s\n' 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid; \
    apt-get -y update; \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
    ; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . /src

# Build from the existing autotools-generated ./configure in the repo.
RUN set -eux; \
    # Build with a static libiperf so we can ship a single iperf3 ELF.
    # Note: This does NOT produce a fully-static binary; it only disables libiperf.so.
    # Also disable OpenSSL so release binaries do not depend on libssl/libcrypto.
    ./configure --disable-shared --enable-static --with-openssl=no; \
    make -j"$(nproc)"; \
    mkdir -p /dist; \
    # With --disable-shared, libtool will typically emit a real ELF at src/iperf3 (no wrapper script).
    cp -a src/iperf3 /dist/iperf3; \
    strip /dist/iperf3 || true

FROM scratch
COPY --from=build /dist/ /dist/
