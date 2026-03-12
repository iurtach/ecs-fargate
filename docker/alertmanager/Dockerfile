# ============================================================
# Alertmanager — with Telegram receiver
# TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID injected via ECS secrets
# ============================================================
FROM prom/alertmanager:v0.27.0

COPY alertmanager.yml /etc/alertmanager/alertmanager.yml

EXPOSE 9093

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:9093/-/healthy || exit 1
