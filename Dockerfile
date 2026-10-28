# Image of the native server. The wasm front is not built here: compile it
# with web/build.sh and it will be copied in if web/dist is present.
# This image is not a production deploy. See docs/despliegue.md.
FROM ubuntu:24.04

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git build-essential \
  && rm -rf /var/lib/apt/lists/*

RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
  | sh -s -- -y --default-toolchain leanprover/lean4:v4.35.0
ENV PATH="/root/.elan/bin:${PATH}"

WORKDIR /src
COPY . .
RUN lake update && lake build vlab-server vlab-tests \
  && if [ -d web/dist ]; then echo "front included"; else echo "front not in the build context"; fi

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin vlab \
  && mkdir -p /data \
  && chown -R vlab:vlab /data /src

USER vlab
EXPOSE 8080
VOLUME ["/data"]
ENTRYPOINT ["/src/.lake/build/bin/vlab-server"]
CMD ["--host", "0.0.0.0", "--port", "8080", "--data", "/data", "--static", "/src/web/dist"]
