# Not Lonely Backend - Client WebSocket Specification (v0.1)

This document outlines the WebSocket communication protocol for clients connecting to the Not Lonely backend service.

## Connection

-   **Endpoint**: `ws://localhost:8005/ws`

*Note: The port `8005` is based on the current `docker-compose.yml` configuration. This may differ if you change the port mappings.*

## Client to Server Messages

The client sends JSON messages to the server to initiate a chat session with an LLM provider.

### Message Format

The message must be a JSON object with the following structure:

```typescript
interface ChatRequest {
  provider: string; // The desired LLM provider (e.g., "openai", "ollama")
  messages: {
    role: "user" | "assistant" | "system";
    content: string;
  }[];
  model?: string; // Optional: The specific model to use (e.g., "gpt-4-turbo", "llama3")
}
```

-   `provider`: (Required) A string specifying which provider to use. The available providers are determined by the backend configuration (currently `openai` and `ollama`).
-   `messages`: (Required) A list of message objects, following the standard chat completion format.
-   `model`: (Optional) A string specifying which model the provider should use. If omitted, the provider's default model will be used.

### Example Request

```json
{
  "provider": "openai",
  "messages": [
    {
      "role": "user",
      "content": "Tell me a joke about software development."
    }
  ],
  "model": "gpt-4-turbo"
}
```

## Server to Client Messages

The server streams the LLM's response back to the client as a series of JSON messages.

### Message Format

The server sends JSON objects with the following structure:

```typescript
interface LLMResponse {
  partial: boolean;
  content: string;
}
```

-   `partial`: A boolean indicating if this is part of a streaming response.
    -   `true`: This message contains a token from the LLM. The stream is ongoing.
    -   `false`: This message signals the end of the stream. The `content` will be empty.
-   `content`: The text chunk from the LLM.

### Example Response Stream

For a simple response like "Hello!", the client could receive the following messages in sequence:

1.  `{"partial": true, "content": "He"}`
2.  `{"partial": true, "content": "llo!"}`
3.  `{"partial": false, "content": ""}` 