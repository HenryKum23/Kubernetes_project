# AI Customer Support Chatbot

An AI-powered customer support chatbot microservice for the Floma eshop, built with Node.js/Express and the Anthropic Claude API.

---

## Overview

The chatbot runs as a **separate microservice** alongside the main eshop application. It is not exposed directly to the internet — the eshop proxies all chat requests through to it internally, keeping the Anthropic API key completely hidden from the browser.

```
Browser
    ↓
Eshop (port 3000) → /api/chat
    ↓
Chatbot (port 4000) → Anthropic Claude API
    ↓
Response back to browser
```

---

## File Structure

```
app/
└── chatbot/
    ├── server.js          # Express API — calls Claude API
    ├── package.json       # Dependencies
    ├── Dockerfile         # Hardened multi-stage image
    └── .dockerignore
```

---

## How It Works

### Request Flow

```
1. User types a message in the chat widget (chatbot.js)
2. chatbot.js sends POST to /api/chat on the eshop server
3. eshop server.js proxies the request to:
   http://chatbot.my-app.svc.cluster.local/chat
4. chatbot/server.js receives the message
5. Calls the Anthropic Claude API (claude-haiku)
6. Returns the response back through the chain
7. Chat widget displays the reply to the user
```

### Internal DNS

The eshop talks to the chatbot using Kubernetes internal DNS — this never leaves the cluster:

```
http://chatbot.my-app.svc.cluster.local/chat
         ↑         ↑           ↑
    service    namespace   cluster DNS
```

---

## API Endpoints

| Method | Endpoint  | Description                        |
|--------|-----------|------------------------------------|
| POST   | /chat     | Send a message, receive AI response |
| GET    | /health   | Health check for Kubernetes probe   |

### Request Body

```json
{
  "message": "What are your return policies?"
}
```

### Response Body

```json
{
  "reply": "Our return policy allows returns within 30 days..."
}
```

---

## AI Model

The chatbot uses **claude-haiku** — the fastest and most cost-efficient Claude model, ideal for real-time customer support responses.

| Property       | Value                    |
|----------------|--------------------------|
| Model          | claude-haiku-4-5         |
| Max tokens     | 1000                     |
| Input cost     | $0.80 per 1M tokens      |
| Output cost    | $4.00 per 1M tokens      |
| Typical cost   | ~$0.01–$0.10/month       |

---

## Kubernetes Resources

| File                    | Kind       | Purpose                                      |
|-------------------------|------------|----------------------------------------------|
| chatbot-deployment.yaml | Deployment | Runs 1 chatbot pod, pulls image from ECR     |
| chatbot-service.yaml    | Service    | ClusterIP — exposes chatbot internally only  |
| chatbot-secret.yaml     | Secret     | Stores the Anthropic API key securely        |

---

## Configuration

### Anthropic API Key

The API key is stored in a Kubernetes Secret and injected as an environment variable into the chatbot pod.

```yaml
# chatbot-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: anthropic-secret
  namespace: my-app
type: Opaque
stringData:
  ANTHROPIC_API_KEY: YOUR_ANTHROPIC_API_KEY_HERE
```

**How to get your API key:**
1. Go to **console.anthropic.com**
2. Sign in or create an account
3. Click **API Keys** in the left sidebar
4. Click **Create Key**
5. Copy the key immediately — it is only shown once

**How to apply the secret:**
```bash
# Edit the file with your real key first, then:
kubectl apply -f apps/my-app/chatbot-secret.yaml
```

> ⚠️ Never commit the real API key to GitHub. Apply this file manually only.

---

## Docker Image

The chatbot uses the same hardened multi-stage Dockerfile pattern as the eshop:

| Hardening Measure   | Detail                                      |
|---------------------|---------------------------------------------|
| Multi-stage build   | No build tools in the production image      |
| Non-root user       | Runs as appuser, not root                   |
| chmod -R 550        | App cannot modify its own files             |
| npm ci --only=prod  | Reproducible install, no dev dependencies   |
| HEALTHCHECK         | Kubernetes restarts unhealthy pods          |
| EXPOSE 4000         | Chatbot listens on port 4000                |

---

## ECR Repository

The chatbot has its own ECR repository separate from the eshop:

| Repository    | Image           |
|---------------|-----------------|
| my-app        | Eshop image     |
| eshop-chatbot | Chatbot image   |

Both are built and pushed by the GitHub Actions pipeline on every push to `main`.

---

## Frontend Widget

The chat widget lives in `app/public/chatbot.js` and is loaded by `index.html`:

```html
<!-- In index.html, before </body> -->
<script src="chatbot.js"></script>
```

The widget:
- Injects its own CSS into the page
- Renders a floating chat button in the bottom-right corner
- Opens a chat window when clicked
- Maintains conversation history across messages
- Sends messages to `/api/chat` on the eshop server

---

## Cost Estimate

For a portfolio project with light traffic the Anthropic API cost is negligible:

| Usage               | Estimated Cost     |
|---------------------|--------------------|
| Testing/development | < $0.01/month      |
| 100 conversations   | ~$0.01/month       |
| 1,000 conversations | ~$0.10/month       |
| Your $5 credit      | Lasts 6–12 months  |

The AWS EKS cluster (~$170/month) will always be the dominant cost by far.