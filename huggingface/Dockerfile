FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y wget ca-certificates curl jq gettext-base inotify-tools && \
    rm -rf /var/lib/apt/lists/*

# Download latest CLI Proxy API for Linux
RUN LATEST_URL=$(curl -s https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest | jq -r '.assets[] | select(.name | test("linux.*amd64.*tar.gz")) | .browser_download_url') && \
    echo "Downloading: $LATEST_URL" && \
    wget -q "$LATEST_URL" -O cli-proxy-api.tar.gz && \
    tar -xzf cli-proxy-api.tar.gz && \
    find . -name "cli-proxy-api" -type f -exec mv {} /app/cli-proxy-api \; && \
    rm -rf cli-proxy-api.tar.gz CLIProxyAPI* && \
    chmod +x /app/cli-proxy-api

# Copy config template
COPY config.yaml /app/config.template.yaml

# Create Supabase sync script
COPY supabase-sync.sh /app/supabase-sync.sh
RUN chmod +x /app/supabase-sync.sh

# Create startup script
RUN echo '#!/bin/bash\n\
\n\
# Replace environment variables in config\n\
envsubst < /app/config.template.yaml > /app/config.yaml\n\
\n\
# Create auths directory\n\
mkdir -p /app/auths\n\
\n\
# Download auth files from Supabase Storage\n\
echo "=== Downloading auth files from Supabase ==="\n\
/app/supabase-sync.sh download || echo "Supabase download skipped"\n\
\n\
echo "=== Auth files loaded: $(find /app/auths -name "*.json" | wc -l) ==="\n\
\n\
# Start file watcher in background (sync changes to Supabase)\n\
/app/supabase-sync.sh watch &\n\
\n\
exec ./cli-proxy-api -config config.yaml\n\
' > /app/start.sh && chmod +x /app/start.sh

EXPOSE 7860

CMD ["/app/start.sh"]
