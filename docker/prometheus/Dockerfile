FROM prom/prometheus:v2.51.2

USER root
RUN mkdir -p /etc/prometheus /prometheus && \
    chown -R nobody:nobody /etc/prometheus /prometheus

COPY prometheus.yml      /etc/prometheus/prometheus.yml
COPY alerting_rules.yml  /etc/prometheus/alerting_rules.yml


USER nobody

EXPOSE 9090

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:9090/prometheus/-/healthy || exit 1
