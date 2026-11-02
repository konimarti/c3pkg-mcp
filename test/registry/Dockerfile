# Local copy of the c3pkg.eu registry (github.com/tonis2/c3pkg), built from a pinned commit.
FROM golang:1.26 AS build
ARG C3PKG_REF=101345814e5fdab0c4e23b8c9e4823081a78b87d
# Optional: put your network's TLS-inspection root CA (*.crt) in test/registry/certs/ to trust it while building.
COPY certs/ /usr/local/share/ca-certificates/extra/
RUN update-ca-certificates
RUN git clone https://github.com/tonis2/c3pkg /src \
 && git -C /src checkout "$C3PKG_REF" \
 && cd /src && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /c3pkg ./cmd/c3pkg \
 && mkdir -p /data/uploads && chown -R 65532:65532 /data

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /c3pkg /c3pkg
COPY --from=build --chown=65532:65532 /data /data
ENV C3PKG_ADDR=:8080 C3PKG_DATA_DIR=/data
EXPOSE 8080
USER 65532:65532
HEALTHCHECK --interval=2s --timeout=3s --start-period=5s --retries=15 CMD ["/c3pkg", "healthcheck"]
ENTRYPOINT ["/c3pkg"]
