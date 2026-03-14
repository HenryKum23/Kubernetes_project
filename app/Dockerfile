# ─────────────────────────────────────────
# Stage 1 — Builder
# Install dependencies in a separate stage
# so build tools never make it into the final image
# ─────────────────────────────────────────
FROM node:25-alpine AS builder
RUN apk update && apk upgrade --no-cache
RUN npm install -g npm@latest

WORKDIR /usr/src/app

# Copy package files first for better layer caching
COPY package*.json ./

# Install only production dependencies
RUN npm ci --only=production

# ─────────────────────────────────────────
# Stage 2 — Final hardened image
# Only copies what is needed to run the app
# ─────────────────────────────────────────
FROM node:25-alpine
RUN apk update && apk upgrade --no-cache
RUN npm install -g npm@latest

# Add security labels
LABEL maintainer="henrykum088@gmail.com"
LABEL version="1.0"
LABEL security="hardened"

WORKDIR /usr/src/app

# Create a non-root user and group to run the app
# Running as root inside a container is a security risk
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup

# Copy only production dependencies from builder stage
COPY --from=builder /usr/src/app/node_modules ./node_modules

# Copy application code that is the public folder that contained the html, css and js files for the frontend
COPY . .

# Set correct ownership of files to non-root user
RUN chown -R appuser:appgroup /usr/src/app

# Remove write permissions from app files
# App should only need to read its own files
RUN chmod -R 550 /usr/src/app

# Switch to non-root user — all commands from here run as appuser
USER appuser

# Expose the port your app runs on
EXPOSE 3000

# Healthcheck — Kubernetes will use this to verify the app is running
HEALTHCHECK --interval=30s \
            --timeout=5s \
            --start-period=10s \
            --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/ || exit 1

# Use exec form of CMD — more secure than shell form
# Shell form:  CMD "node server.js"      ← runs via /bin/sh -c (less secure)
# Exec form:   CMD ["node", "server.js"] ← runs directly (more secure)
CMD ["node", "server.js"]