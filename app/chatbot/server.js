const express = require('express');
const cors = require('cors');

const app = express();

// ── Middleware ────────────────────────────────────────────────────────────────

app.use(express.json());
app.use(cors({
  origin: process.env.ESHOP_URL || '*',   // restrict to your eshop domain in production
  methods: ['POST'],
}));

// ── System Prompt ─────────────────────────────────────────────────────────────
// This tells Claude who it is and what it knows about your eshop
// Edit this section to match your actual products, policies and store details

const SYSTEM_PROMPT = `
You are a friendly and helpful customer support assistant for an online eshop.
You help customers with questions about products, orders, shipping, and returns.

Store Information:
- Name: My Eshop
- We sell a range of products online
- Shipping: Standard delivery 3-5 business days, Express delivery 1-2 business days
- Returns: 30-day return policy on all items in original condition
- Payment: We accept all major credit cards and PayPal
- Support hours: Monday to Friday, 9am to 5pm

Guidelines:
- Be friendly, concise and helpful
- If you do not know the answer to a specific question, politely say so and suggest the customer contact support directly
- Do not make up product details, prices or policies you are not sure about
- Keep responses short and easy to read
- Always stay on topic — only answer questions related to the eshop
`;

// ── Chat Endpoint ─────────────────────────────────────────────────────────────

app.post('/chat', async (req, res) => {
  const { messages } = req.body;

  // Validate request
  if (!messages || !Array.isArray(messages) || messages.length === 0) {
    return res.status(400).json({ error: 'messages array is required' });
  }

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',  // fast and cost-effective for a chatbot
        max_tokens: 1024,
        system: SYSTEM_PROMPT,
        messages,                             // full conversation history from frontend
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      console.error('Claude API error:', error);
      return res.status(500).json({ error: 'Failed to get response from AI' });
    }

    const data = await response.json();

    // Return just the text response to the frontend
    res.json({ reply: data.content[0].text });

  } catch (err) {
    console.error('Chatbot error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ── Health Check ──────────────────────────────────────────────────────────────

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// ── Start Server ──────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => {
  console.log(`Chatbot service running on port ${PORT}`);
});