# Local AI setup

New installations default to the Ollama-compatible local endpoint, `http://127.0.0.1:11434/v1`, using `qwen3.5:2b` with screenshots enabled. Existing saved provider configuration is preserved.

In Settings choose **Download local AI**. The app uses an existing Ollama service when available. Otherwise it downloads the official macOS runtime v0.40.11 into its Application Support directory, verifies SHA-256, extracts it, and starts a loopback service. It then downloads the vision model through Ollama, displaying real download progress. The provider is saved only after success. Cancel stops the app’s setup task; partial model data may remain for retry. No shell installer or administrator access is used.

Allow approximately 3 GB download and 8 GB free disk; Apple silicon and macOS 14 or later are required by this setup flow. Small local models may be slower or less accurate than the Claude demo provider. This installer has been compiled and packaged, but its download flow has not been executed as part of the user-owned testing session.

Pinned runtime archive: https://github.com/ollama/ollama/releases/download/v0.40.11/ollama-darwin.tgz

SHA-256: `aea7d3f2e32371b7644a6e2ec8d4f26820a0e3965918cce8a46cef3e947f6291`

Runtime license (MIT): https://github.com/ollama/ollama/blob/main/LICENSE

Model weights/license (Apache 2.0): https://huggingface.co/Qwen/Qwen3.5-2B

Ollama model listing: https://ollama.com/library/qwen3.5

The app archive does not contain model weights. Downloads occur only when the user chooses the setup button. In local mode screen context is processed on the Mac; a localhost bridge to a remote service is different and still forwards context to that service.
