# ─────────────────────────────────────────
# Stage 1 — Builder
# ─────────────────────────────────────────
FROM node:22-alpine AS builder
RUN apk update && apk upgrade --no-cache
RUN npm install -g npm@latest

WORKDIR /usr/src/app

COPY package*.json ./

RUN npm ci --only=production

# ─────────────────────────────────────────
# Stage 2 — Final hardened image
# ─────────────────────────────────────────
FROM node:22-alpine
RUN apk update && apk upgrade --no-cache
RUN npm install -g npm@latest

LABEL maintainer="henrykum088@gmail.com"
LABEL service="eshop-chatbot"
LABEL security="hardened"

WORKDIR /usr/src/app

# Create non-root user
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup

# Copy production dependencies from builder
COPY --from=builder /usr/src/app/node_modules ./node_modules

# Copy application code
COPY . .

# Set ownership and permissions
RUN chown -R appuser:appgroup /usr/src/app && \
    chmod -R 550 /usr/src/app

# Switch to non-root user
USER appuser

EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s \
            --timeout=5s \
            --start-period=10s \
            --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:4000/health || exit 1

CMD ["node", "server.js"]