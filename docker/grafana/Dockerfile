FROM grafana/grafana:10.4.3

USER root
RUN mkdir -p /etc/grafana/provisioning/datasources \
             /etc/grafana/provisioning/dashboards \
             /etc/grafana/dashboards && \
    chown -R 472:472 /etc/grafana

COPY provisioning/datasources/prometheus.yml /etc/grafana/provisioning/datasources/prometheus.yml
COPY provisioning/dashboards/dashboards.yml  /etc/grafana/provisioning/dashboards/dashboards.yml
COPY dashboards/                             /etc/grafana/dashboards/

RUN chown -R 472:472 /etc/grafana

USER grafana
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:3000/grafana/api/health || exit 1