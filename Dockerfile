FROM golang:1.25-bookworm AS backend-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG COMMITHASH=local
ARG VERSION=development

RUN make build-server COMMITHASH="$COMMITHASH" VERSION="$VERSION"




FROM node:22-bookworm AS frontend-builder

WORKDIR /build

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

RUN make build-ssr
RUN make build-ui





FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    perl-base \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system fider \
    && useradd --system --gid fider --home-dir /app --shell /usr/sbin/nologin fider

WORKDIR /app

COPY --from=backend-builder /build/fider ./fider
COPY --from=backend-builder /build/migrations ./migrations
COPY --from=backend-builder /build/views ./views
COPY --from=backend-builder /build/locale ./locale
COPY --from=backend-builder /build/static ./static
COPY --from=backend-builder /build/LICENSE ./LICENSE

COPY --from=frontend-builder /build/dist ./dist
COPY --from=frontend-builder /build/ssr.js ./ssr.js
COPY --from=frontend-builder /build/favicon.png ./favicon.png
COPY --from=frontend-builder /build/robots.txt ./robots.txt

EXPOSE 3000

RUN chown -R fider:fider /app

USER fider

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["./fider", "ping"]

CMD ["sh", "-c", "./fider migrate && exec ./fider"]