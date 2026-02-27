# Nanobot AI for Home Assistant (App)

Nanobot is an ultra-lightweight and powerful AI Agent integrated directly into Home Assistant. This App (formerly Add-on) has been engineered to offer maximum flexibility, universal support for LLM providers, and secure data persistence.

## 🌟 New Features (v0.5.0)
* **Zero Symlink Loop:** Completely rewritten file system structure. System data (`/data`) is invisible and protected, while your workspace (`/share/nanobot_workspace`) is clean and free of recursions.
* **Auto-Routing Fallback:** If your primary model goes offline or runs out of credits, the agent automatically switches to the fallback model without interrupting the conversation.
* **Advanced JSON Config:** Full support for complex configurations (e.g., MCP servers, custom tools) via an external file that can be easily edited with Studio Code Server.

---

## 📂 Folder Structure
On the first startup, the App will automatically create this structure in the folder defined in `workspace_path` (default `/share/nanobot_workspace`):

* `/skills/` -> Here you can place your Python files to teach the agent new capabilities.
* `/media/` -> Storage folder for images, audio, and files managed by the agent.
* `advanced_config.json` -> The file where you can put your advanced JSON configurations.

---

## ⚙️ Provider Configuration (Practical Examples)

Thanks to the integrated LiteLLM, you can use any provider. Here are some common configurations to enter in the Home Assistant UI:

### 1. OpenRouter (Recommended for Open Source models)
* **Provider:** `openrouter`
* **API Key:** `sk-or-v1-...`
* **Model:** `openrouter/deepseek/deepseek-chat` (or `anthropic/claude-3.5-sonnet`)

### 2. Local Ollama (100% Free and Private)
*Note: Make sure you have exposed Ollama to the network by setting `OLLAMA_HOST=0.0.0.0` on the host machine.*
* **Provider:** `openai` *(Do not use 'ollama', use the OpenAI-compatible module)*
* **API Key:** `sk-dummy` *(Write anything)*
* **API Base:** `http://YOUR_LOCAL_IP:11434/v1` *(Do not forget the trailing /v1)*
* **Model:** `openai/llama3.1` *(Replace with your model, keeping the openai/ prefix)*

### 3. Z.AI (Zhipu AI / GLM Models)
* **Provider:** `openai`
* **API Key:** `your-zhipu-key...`
* **API Base:** `https://open.bigmodel.cn/api/paas/v4`
* **Model:** `openai/glm-4-flash`

---

## 🛡️ The Fallback System
You can set an emergency LLM directly from the user interface. 
Example of strategic use:
1. Set **Ollama** as primary (Zero cost).
2. Set **OpenAI/GPT-4o-mini** as Fallback.
If your PC with Ollama is turned off, Nanobot will automatically route the call to OpenAI, ensuring the agent *always* responds.

---

## 🛠️ Advanced Configuration (advanced_config.json)
To avoid syntax errors in the Home Assistant UI, all extra configurations must be written in the `advanced_config.json` file that you will find in your workspace.

You can use this file to add MCP servers, third-party providers, or channel-specific configurations.

**Example content for `advanced_config.json`:**
```json
{
  "mcpServers": {
    "home_assistant": {
      "command": "python",
      "args": ["/share/nanobot_workspace/mcp_ha.py"]
    }
  }
}
```
> 💡 **Safety Note:** The App will verify the validity of the JSON at every restart. If there are syntax errors (e.g., missing commas), the App will temporarily ignore the file to prevent the agent from crashing and will report the error in the Home Assistant logs.

🚀 **Replace the files and trigger a Rebuild**: you will effectively have an enterprise-grade App. Let me know when you've got it running again!
