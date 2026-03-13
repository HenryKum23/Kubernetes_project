// ── Eshop Chatbot Widget ──────────────────────────────────────────────────────
// Add this script to your index.html just before </body>:
// <script src="chatbot.js"></script>

(function () {

  // ── Conversation history (sent to chatbot API on every message) ──────────────
  let conversationHistory = [];

  // ── Inject styles ────────────────────────────────────────────────────────────
  const style = document.createElement('style');
  style.textContent = `
    #chat-toggle {
      position: fixed; bottom: 24px; right: 24px;
      width: 56px; height: 56px; border-radius: 50%;
      background: #2E75B6; color: white; border: none;
      font-size: 24px; cursor: pointer; box-shadow: 0 4px 12px rgba(0,0,0,0.2);
      z-index: 1000; display: flex; align-items: center; justify-content: center;
      transition: background 0.2s;
    }
    #chat-toggle:hover { background: #1F4E79; }

    #chat-window {
      position: fixed; bottom: 90px; right: 24px;
      width: 340px; height: 480px;
      background: white; border-radius: 12px;
      box-shadow: 0 8px 24px rgba(0,0,0,0.15);
      display: none; flex-direction: column;
      z-index: 1000; overflow: hidden;
      font-family: Arial, sans-serif;
    }
    #chat-window.open { display: flex; }

    #chat-header {
      background: #2E75B6; color: white;
      padding: 14px 16px; font-weight: bold; font-size: 15px;
      display: flex; justify-content: space-between; align-items: center;
    }
    #chat-close {
      background: none; border: none; color: white;
      font-size: 20px; cursor: pointer; line-height: 1;
    }

    #chat-messages {
      flex: 1; overflow-y: auto; padding: 16px;
      display: flex; flex-direction: column; gap: 10px;
    }

    .chat-msg {
      max-width: 80%; padding: 10px 14px;
      border-radius: 16px; font-size: 14px; line-height: 1.4;
    }
    .chat-msg.user {
      align-self: flex-end;
      background: #2E75B6; color: white;
      border-bottom-right-radius: 4px;
    }
    .chat-msg.bot {
      align-self: flex-start;
      background: #F0F4F8; color: #333;
      border-bottom-left-radius: 4px;
    }
    .chat-msg.typing {
      align-self: flex-start;
      background: #F0F4F8; color: #999;
      border-bottom-left-radius: 4px;
      font-style: italic;
    }

    #chat-input-row {
      display: flex; padding: 12px; border-top: 1px solid #eee; gap: 8px;
    }
    #chat-input {
      flex: 1; border: 1px solid #ddd; border-radius: 20px;
      padding: 8px 14px; font-size: 14px; outline: none;
      font-family: Arial, sans-serif;
    }
    #chat-input:focus { border-color: #2E75B6; }
    #chat-send {
      background: #2E75B6; color: white; border: none;
      border-radius: 50%; width: 36px; height: 36px;
      cursor: pointer; font-size: 16px; display: flex;
      align-items: center; justify-content: center;
      flex-shrink: 0;
    }
    #chat-send:hover { background: #1F4E79; }
    #chat-send:disabled { background: #aaa; cursor: not-allowed; }
  `;
  document.head.appendChild(style);

  // ── Build widget HTML ────────────────────────────────────────────────────────
  document.body.insertAdjacentHTML('beforeend', `
    <button id="chat-toggle" title="Chat with us">💬</button>
    <div id="chat-window">
      <div id="chat-header">
        <span>🛍️ Eshop Support</span>
        <button id="chat-close">×</button>
      </div>
      <div id="chat-messages">
        <div class="chat-msg bot">Hi there! 👋 How can I help you today?</div>
      </div>
      <div id="chat-input-row">
        <input id="chat-input" type="text" placeholder="Type a message..." />
        <button id="chat-send">➤</button>
      </div>
    </div>
  `);

  // ── References ───────────────────────────────────────────────────────────────
  const toggle   = document.getElementById('chat-toggle');
  const window_  = document.getElementById('chat-window');
  const closeBtn = document.getElementById('chat-close');
  const messages = document.getElementById('chat-messages');
  const input    = document.getElementById('chat-input');
  const sendBtn  = document.getElementById('chat-send');

  // ── Toggle open/close ────────────────────────────────────────────────────────
  toggle.addEventListener('click', () => window_.classList.toggle('open'));
  closeBtn.addEventListener('click', () => window_.classList.remove('open'));

  // ── Send message ─────────────────────────────────────────────────────────────
  function addMessage(text, role) {
    const div = document.createElement('div');
    div.className = `chat-msg ${role}`;
    div.textContent = text;
    messages.appendChild(div);
    messages.scrollTop = messages.scrollHeight;
    return div;
  }

  async function sendMessage() {
    const text = input.value.trim();
    if (!text) return;

    input.value = '';
    sendBtn.disabled = true;

    // Show user message
    addMessage(text, 'user');

    // Add to conversation history
    conversationHistory.push({ role: 'user', content: text });

    // Show typing indicator
    const typing = document.createElement('div');
    typing.className = 'chat-msg typing';
    typing.textContent = 'Typing...';
    messages.appendChild(typing);
    messages.scrollTop = messages.scrollHeight;

    try {
      // Call the chatbot microservice
      // In the cluster this resolves via Kubernetes internal DNS
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ messages: conversationHistory }),
      });

      const data = await res.json();

      // Remove typing indicator
      messages.removeChild(typing);

      if (data.reply) {
        // Show bot reply and add to history
        addMessage(data.reply, 'bot');
        conversationHistory.push({ role: 'assistant', content: data.reply });
      } else {
        addMessage('Sorry, I could not get a response. Please try again.', 'bot');
      }

    } catch (err) {
      messages.removeChild(typing);
      addMessage('Sorry, something went wrong. Please try again later.', 'bot');
      console.error('Chatbot error:', err);
    }

    sendBtn.disabled = false;
    input.focus();
  }

  sendBtn.addEventListener('click', sendMessage);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') sendMessage();
  });

})();