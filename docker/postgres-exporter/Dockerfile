FROM alpine:3.19
ARG VERSION=0.15.0
RUN apk add --no-cache curl tar && \
    curl -L https://github.com/prometheus-community/postgres_exporter/releases/download/v${VERSION}/postgres_exporter-${VERSION}.linux-amd64.tar.gz \
    | tar xz && \
    mv postgres_exporter-${VERSION}.linux-amd64/postgres_exporter /usr/local/bin/ && \
    apk del curl tar
EXPOSE 9187
ENTRYPOINT ["/usr/local/bin/postgres_exporter"]
