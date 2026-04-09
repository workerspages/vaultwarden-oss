FROM vaultwarden/server:alpine

# Install dependencies needed for syncing
RUN apk add --no-cache rclone bash tzdata sqlite

# Copy our custom entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment settings
ENV ROCKET_PORT=8080
ENV PORT=8080
ENV SYNC_INTERVAL=5

# Expose the Cloudflare HTTP supported port
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
