# Home Assistant Add-on: Nanobot

An ultra-lightweight, local-first AI Agent based on [HKUDS/nanobot](https://github.com/HKUDS/nanobot). This add-on runs Nanobot in **Gateway Mode**, providing an API endpoint for your AI agents with full persistence and MCP (Model Context Protocol) support.

![Supports amd64](https://img.shields.io/badge/arch-amd64_only-blue)

## ✨ Features

* **Multi-Provider Support:** Works with OpenAI, Anthropic, Gemini, Groq, DeepSeek, OpenRouter, and local LLMs (vLLM/Ollama via OpenAI compatible).
* **True Persistence:** All agent memories, sessions, databases, and **Python dependencies** are stored in Home Assistant's persistent storage (`/share`), ensuring nothing is lost on updates.
* **Self-Evolving AI:** The agent has a dedicated Python Virtual Environment (`venv`). If it learns a skill that requires `pip install`, the packages will survive reboots!
* **MCP Support:** Full support for the **Model Context Protocol**. Connect external tools and data sources via JSON configuration.
* **Secure Workspace:** Restrict the agent's file access to a specific folder to prevent unauthorized system access.
* **Gateway Mode:** Exposes the Nanobot API on port `18790`.

## 🚀 Installation

1.  Add this repository to your Home Assistant Add-on Store.
2.  Search for **Nanobot** and click **Install**. *(Note: Requires an x86/amd64 machine. ARM/Raspberry Pi is not currently supported due to dependency compilation requirements).*
3.  **Configuration:** Go to the **Configuration** tab and set up your LLM Provider (API Key is required).
4.  **Network:** (Optional) Configure the port in the **Network** section (default is 18790).
5.  Start the Add-on.

## ⚙️ Configuration

The add-on uses the Home Assistant UI as the **Single Source of Truth**. Any manual modifications to the `config.json` file will be overwritten on the next reboot. 

### Basic Options

| Option | Description | Default |
| :--- | :--- | :--- |
| `provider` | The LLM provider to use (e.g., `openrouter`, `openai`, `anthropic`, `custom`). | `openrouter` |
| `api_key` | Your API Key for the selected provider. | *(empty)* |
| `model` | The specific model name (e.g., `anthropic/claude-3-5-sonnet`). | `gpt-4o` |
| `api_base` | (Optional) Custom API endpoint. Useful for LocalAI, vLLM, or regional proxies. | *(empty)* |

### Security & Workspace

| Option | Description | Default |
| :--- | :--- | :--- |
| `restrict_to_workspace` | Limits the agent shell and file operations exclusively to the `workspace_path`. Highly recommended. | `true` |
| `workspace_path` | The directory where the agent is allowed to work. | `/share/nanobot_workspace` |

### Advanced: MCP & Custom Config

The `additional_config_json` field allows you to inject raw JSON into the Nanobot configuration. 

**Example: Adding a Filesystem MCP Tool**
Paste this into the `additional_config_json` field:

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
## 📂 Persistence & Environment

This add-on maps the execution environment directly into your Home Assistant `/share` folder:

* **Config & DB:** Located in `/share/nanobot_workspace/.nanobot`
* **Python venv:** Located in `/share/nanobot_workspace/venv`. If your agent installs python packages, they go here.
* **Node Cache:** NPM caches for MCP servers will automatically be stored here, speeding up subsequent reboots.

## Credits

This add-on is a wrapper for [Nanobot](https://github.com/HKUDS/nanobot) created by HKUDS.
