# Security Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: XSS And Output Safety

Review HTML injection sinks and unsafe output.

- Do not pass user-controlled or externally-sourced strings into `v-html` (Vue) or `dangerouslySetInnerHTML` (React) without sanitization (e.g. DOMPurify). These bypass the framework's automatic escaping.
- Do not build DOM/HTML by string concatenation with untrusted input (`innerHTML`, `insertAdjacentHTML`, `document.write`). Prefer text nodes / framework binding.
- Reject `javascript:` and `data:` URLs where a user value flows into `href`/`src`/`window.open`; validate the scheme against an allowlist (`http`/`https`/relative).
- Be cautious with dynamic script/style injection and third-party embeds fed by user input.

Report only sinks reachable from user-controlled or external input.

## Focus B: Input Validation And Secret Handling

Review validation, CSRF, and secrets exposed to the client.

- Client-side validation is UX only. Anything that protects data integrity or authorization must also be validated server-side; do not treat a client check as the security boundary.
- Do not embed real secrets (API keys, tokens with server privileges) in client code or public env vars; anything shipped to the browser is public. Only publishable/anon keys belong in the bundle.
- Do not store sensitive data (access tokens, PII) in `localStorage`/`sessionStorage` where XSS can read it; prefer httpOnly cookies for auth tokens.
- State-changing requests should carry CSRF protection appropriate to the auth scheme (token/SameSite cookies) when the app relies on cookie auth.
- Validate and constrain redirect targets and postMessage origins reached from user input.

Report only concrete exposure or missing-server-validation risks, not defense-in-depth wishlist items.
