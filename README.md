# Nanobot AI per Home Assistant (App)

Nanobot è un Agente IA ultra-leggero e potente integrato direttamente in Home Assistant. Questa App (ex Add-on) è stata ingegnerizzata per offrire massima flessibilità, supporto universale ai provider LLM e persistenza sicura dei dati.

## 🌟 Nuove Funzionalità (v0.5.0)
* **Zero Symlink Loop:** Struttura del file system completamente riscritta. I dati di sistema (`/data`) sono invisibili e protetti, mentre il tuo workspace (`/share/nanobot_workspace`) è pulito e privo di ricorsioni.
* **Auto-Routing Fallback:** Se il tuo modello primario va offline o esaurisce i crediti, l'agente passa automaticamente al modello di emergenza senza interrompere la conversazione.
* **Advanced JSON Config:** Supporto totale per configurazioni complesse (es. MCP servers, tool personalizzati) tramite file esterno editabile comodamente con Studio Code Server.

---

## 📂 Struttura Cartelle
Al primo avvio, l'App creerà automaticamente questa struttura nella cartella definita in `workspace_path` (di default `/share/nanobot_workspace`):

* `/skills/` -> Qui puoi inserire i tuoi file Python per insegnare nuove capacità all'agente.
* `/media/` -> Cartella di appoggio per immagini, audio e file gestiti dall'agente.
* `advanced_config.json` -> Il file dove inserire le tue configurazioni JSON avanzate.

---

## ⚙️ Configurazione Provider (Esempi Pratici)

Grazie a LiteLLM integrato, puoi usare qualsiasi provider. Ecco alcune configurazioni comuni da inserire nella UI di Home Assistant:

### 1. OpenRouter (Consigliato per modelli Open Source)
* **Provider:** `openrouter`
* **API Key:** `sk-or-v1-...`
* **Model:** `openrouter/deepseek/deepseek-chat` (o `anthropic/claude-3.5-sonnet`)

### 2. Ollama Locale (100% Gratuito e Privato)
*Nota: Assicurati di aver sbloccato Ollama sulla rete impostando `OLLAMA_HOST=0.0.0.0` sulla macchina host.*
* **Provider:** `openai` *(Non usare 'ollama', usa il modulo OpenAI-compatibile)*
* **API Key:** `sk-dummy` *(Scrivi qualsiasi cosa)*
* **API Base:** `http://TUO_IP_LOCALE:11434/v1` *(Non dimenticare il /v1 finale)*
* **Model:** `openai/llama3.1` *(Sostituisci con il tuo modello, mantenendo openai/)*

### 3. Z.AI (Zhipu AI / GLM Models)
* **Provider:** `openai`
* **API Key:** `tua-chiave-zhipu...`
* **API Base:** `https://open.bigmodel.cn/api/paas/v4`
* **Model:** `openai/glm-4-flash`

---

## 🛡️ Il Sistema di Fallback
Puoi impostare un LLM di emergenza direttamente dall'interfaccia utente. 
Esempio di utilizzo strategico:
1. Imposta **Ollama** come primario (Costo zero).
2. Imposta **OpenAI/GPT-4o-mini** come Fallback.
Se il tuo PC con Ollama è spento, Nanobot instraderà automaticamente la chiamata verso OpenAI, garantendoti che l'agente risponda *sempre*.

---

## 🛠️ Configurazione Avanzata (advanced_config.json)
Per evitare errori di sintassi nella UI di Home Assistant, tutte le configurazioni extra vanno scritte nel file `advanced_config.json` che troverai nel tuo workspace.

Puoi usare questo file per aggiungere server MCP, provider di terze parti o configurazioni specifiche per i canali.

**Esempio di contenuto per `advanced_config.json`:**
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

> 💡 **Nota di sicurezza:** L'App verificherà la validità del JSON a ogni riavvio. Se ci sono errori di sintassi (es. virgole mancanti), l'App ignorerà temporaneamente il file per evitare che l'agente vada in crash e segnalerà l'errore nei log di Home Assistant.

🚀 **Sostituisci i file e fai il tuo Rebuild**: avrai a tutti gli effetti un Add-on di livello enterprise. Fammi sapere quando l'hai fatto ripartire!
