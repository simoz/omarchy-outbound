FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl ruby python3 libmaxminddb-dev file \
    && rm -rf /var/lib/apt/lists/*

# Build context: a checkout of the revision recorded in README.md.
COPY . /opt/spinel
WORKDIR /opt/spinel
RUN make deps && make -j4
ENV PATH="/opt/spinel:${PATH}"
WORKDIR /tmp/probe
