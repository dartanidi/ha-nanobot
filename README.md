# Home Assistant Add-on: Nanobot

An ultra-lightweight, local-first AI Agent based on [HKUDS/nanobot](https://github.com/HKUDS/nanobot). This add-on runs Nanobot in **Gateway Mode**, providing an API endpoint for your AI agents with full persistence and MCP (Model Context Protocol) support.

![Supports aarch64 & amd64](https://img.shields.io/badge/arch-aarch64%20|%20amd64-blue)

## ✨ Features

* **Multi-Provider Support:** Works with OpenAI, Anthropic, Gemini, Groq, DeepSeek, OpenRouter, and local LLMs (vLLM/Ollama via OpenAI compatible).
* **Persistent Memory:** All agent memories, sessions, and vector databases are stored in Home Assistant's persistent storage (`/data`), ensuring no data loss on restarts.
* **MCP Support:** Full support for the **Model Context Protocol**. Connect external tools and data sources via JSON configuration.
* **Secure Workspace:** Restrict the agent's file access to a specific folder (default: `/share/nanobot_workspace`) to prevent unauthorized system access.
* **Gateway Mode:** Exposes the Nanobot API on port `18790` (configurable) for integration with other services.

## 🚀 Installation

1.  Add this repository to your Home Assistant Add-on Store.
2.  Search for **Nanobot** and click **Install**.
3.  **Configuration:** Go to the **Configuration** tab and set up your LLM Provider (API Key is required).
4.  **Network:** (Optional) Configure the port in the **Network** section (default is 18790).
5.  Start the Add-on.
6.  Check the logs to ensure the gateway has started successfully.

## ⚙️ Configuration

You can configure the agent directly via the Add-on Web UI.

### Basic Options

| Option | Description | Default |
| :--- | :--- | :--- |
| `provider` | The LLM provider to use (e.g., `openrouter`, `openai`, `anthropic`, `custom`). | `openrouter` |
| `api_key` | Your API Key for the selected provider. | *(empty)* |
| `model` | The specific model name (e.g., `anthropic/claude-3-5-sonnet`). | `anthropic/claude-3-5-sonnet` |
| `api_base` | (Optional) Custom API endpoint. Useful for LocalAI, vLLM, or regional proxies. | *(empty)* |

### Security & Workspace

| Option | Description | Default |
| :--- | :--- | :--- |
| `restrict_to_workspace` | If `true`, the agent can only read/write files inside the defined workspace path. Highly recommended for security. | `true` |
| `workspace_path` | The directory where the agent is allowed to work. | `/share/nanobot_workspace` |

> **Note:** The `/share` directory is recommended as it allows you to easily access files created by the agent via Samba or File Editor.

### Advanced: MCP & Custom Config

The `additional_config_json` field allows you to inject raw JSON into the Nanobot configuration. This is primarily used to define **MCP Servers** or override advanced settings not available in the UI.

**Example: Adding a Filesystem MCP Tool**
Paste this into the `additional_config_json` field to allow the agent to use filesystem tools:

```json
{
  "tools": {
    "mcpServers": {
      "filesystem": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-filesystem", "/share/nanobot_workspace"]
      }
    }
  }
}
```
## 📡 Networking

The add-on exposes the **Nanobot Gateway** API.

* **Default Port:** `18790`

You can change this port in the **Network** section of the add-on configuration page in Home Assistant (e.g., map it to port `8080` externally while keeping it `18790` internally).

## 📂 Persistence

* **Agent Data:** The internal database, conversation history, and memory are stored in `/data/nanobot_root`. This data persists across add-on restarts and updates.
* **Workspace:** Files created or modified by the agent are stored in the path defined by `workspace_path`.

## 🔨 Development & Debugging

If the agent isn't behaving as expected:

1. Check the **Log** tab in the add-on.
2. Ensure your `api_key` is correct and has credit.
3. If using `custom` or `vllm` providers, ensure `api_base` is reachable from within the Home Assistant network (use the IP address, not `localhost`).

## Credits

This add-on is a wrapper for [Nanobot](https://github.com/HKUDS/nanobot) created by HKUDS.
