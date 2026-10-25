# Developer-funded Groq access

The developer's Groq key belongs **on the server**, never in the downloadable app, its plist, an embedded environment file, JavaScript shipped to clients, or a shared Keychain item. An app binary cannot keep a developer-wide secret from its users.

This relay gives each tester a separate random access token, stores only its SHA-256 hash, permits revocation, expires tokens, enforces per-user and global request budgets, fixes the model on the server, and bounds input/output. Groq receives the developer key; the macOS app receives only a tester token.

## Local setup — no installation dependencies

Requires Node 24 or later (available on this Mac):

```sh
desktop/scripts/run-relay.sh
```

Open [local developer setup](http://127.0.0.1:8766/admin). Enter the actual Groq secret key (not its name) in the password field. The server validates it and automatically selects an available chat model; a dropdown lets you change it. Then create an access token for your own Mac. Token creation stays unavailable until key validation succeeds. No need to paste the Groq key into a terminal, shell history, source file, chat or macOS client. The key is held only in the local server process; restarting it clears the key. For a vision model, confirm support in [Groq's model documentation](https://console.groq.com/docs/vision).

In Howdoey's AI settings:

1. Choose **Howdoey shared AI**.
2. Address: `http://127.0.0.1:8766/v1`.
3. Paste the generated Howdoey access token in the API key field; this is **not the Groq key**.
4. Find models and select the service's model, Save, then Test connection.

The app saves its token in its own Mac's Keychain. The browser displays a newly generated token once; copy it before leaving that page. The service retains hashes, tester labels, expirations and request counters in `relay/.state/relay.sqlite` (git-ignored, private filesystem permissions). It does not save questions, screenshots, model responses or developer keys. The developer setup page can revoke testers individually.

Default budgets are **6 requests/minute and 30/day per token**, and **100/day across the whole service**. Every attempt that reaches Groq counts, including upstream errors; limits persist across relay restarts. Input is bounded to 140KB of text and at most one inline image; model output is capped at 1,800 tokens. Limits count requests, not dollars. Set a separate Groq project spend limit; a leaked valid tester token can consume its remaining quota until revoked. Do not use a permanent universal token for all users.

## What “local” means here

This server listens on `127.0.0.1` only. The setup form uses a local password field, strict Host and Origin checks, and a random CSRF token. It loads no external scripts or assets, disables caching/framing and does not log request bodies. It assumes other processes running as your local user are trusted. A compromised developer machine is outside that boundary.

Questions and optional screenshots still go **from this local relay to Groq**. This is different from running a model locally in Ollama. The localhost URL works only on this Mac; other people's computers need your deployed HTTPS endpoint. Nothing has been deployed or made public automatically.

## Hosting it for other people

The same Node service can run as a single process on a persistent host behind a real HTTPS reverse proxy. It binds to loopback so a same-host proxy can reach it without exposing its plain HTTP port. Use your hosting secret manager for:

- `GROQ_API_KEY`: developer key; never put it in the app or source.
- `HOWDOEY_MODEL`: one allowed model ID.
- `HOWDOEY_PUBLIC_ORIGIN`: your HTTPS origin, for example `https://api.howdoey.com` (example only; no DNS changes made).
- `HOWDOEY_RELAY_DB`: path on a persistent private volume.
- Optional `HOWDOEY_PER_MINUTE`, `HOWDOEY_PER_USER_DAY`, `HOWDOEY_GLOBAL_DAY`, `PORT`.

In public mode, all `/admin` routes return 404; they cannot accept or change a provider key. Configure or rotate the key using the hosting secret manager. HTTPS termination and strict Host validation are mandatory. A same-host Caddy example:

```caddyfile
api.howdoey.com {
    request_body { max_size 2100KB }
    reverse_proxy 127.0.0.1:8766
}
```

Do not point DNS or alter the partner's website without coordinating. Deploy the relay independently. Restrict SSH/host administration, run it under a dedicated unprivileged user, and keep Node patched. This implementation targets one service instance with SQLite; multiple replicas need a shared transactional quota/auth store. Add upstream IP throttling, monitoring without prompt logging, operational alerts and a managed account/invitation flow before a broad public rollout. This is an authenticated, bounded alpha relay, not a claim of a completed public backend.

To issue a tester token on the server (prints the token once to your admin terminal, not the Groq key):

```sh
node desktop/relay/server.mjs issue-token 'Tester label' 7
```

Use the same `HOWDOEY_RELAY_DB` as the server. Distribute tester tokens privately; do not embed a common token in the app. Give each tester the hosted endpoint and token during onboarding. Key rotation does not require updating desktop apps; revoke tokens independently.

## Tests

```sh
node --test desktop/relay/server.test.mjs
```

Transport fixtures exist only inside these isolated tests. The running relay always calls Groq; it never returns a predetermined assistant answer. Tests cover authentication/revocation/expiry, global and per-client quotas, disallowed models/tools/remote image URLs, output bounds, safe response projection, Host/CSRF validation, public admin denial and upstream-error redaction.

Groq's [security guidance](https://console.groq.com/docs/production-readiness/security-onboarding) recommends environment variables or secret management and forbids exposing keys in client code.
