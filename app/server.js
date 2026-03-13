// const express = require('express');
// const path = require('path');

// const app = express();

// // Serve static files from the 'public' directory
// app.use(express.static(path.join(__dirname, 'public')));

// // For any GET request to '/', serve index.html
// app.get('/', (req, res) => {
//   res.sendFile(path.join(__dirname, 'public', 'index.html'));
// });

// // Choose a port to listen on
// const PORT = process.env.PORT || 3000;
// app.listen(PORT, () => {
//   console.log(`Server running at http://*:${PORT}`);
// });

const express = require('express');
const path = require('path');

const app = express();

app.use(express.json());

// Serve static files from the 'public' directory
app.use(express.static(path.join(__dirname, 'public')));

// ── Chatbot Proxy ─────────────────────────────────────────────────────────────
// The frontend calls /api/chat on the eshop server
// The eshop server forwards the request to the chatbot microservice
// This keeps the Anthropic API key hidden from the browser
// and avoids CORS issues since both are on the same domain

app.post('/api/chat', async (req, res) => {
  try {
    // Chatbot service is reachable via Kubernetes internal DNS
    // Service name: chatbot, Namespace: my-app, Port: 80
    const chatbotUrl = process.env.CHATBOT_URL || 'http://chatbot.my-app.svc.cluster.local';

    const response = await fetch(`${chatbotUrl}/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body),
    });

    const data = await response.json();
    res.json(data);

  } catch (err) {
    console.error('Chatbot proxy error:', err);
    res.status(500).json({ error: 'Chatbot service unavailable' });
  }
});

// ── Serve index.html ──────────────────────────────────────────────────────────

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// ── Start Server ──────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running at http://*:${PORT}`);
});