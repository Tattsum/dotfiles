# Security Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: XSS And Output Safety

Review HTML injection sinks and unsafe output.

- Do not pass user-controlled or externally-sourced strings into `v-html` (Vue) or `dangerouslySetInnerHTML` (React) without sanitization (e.g. DOMPurify). These bypass the framework's automatic escaping.
- Do not build DOM/HTML by string concatenation with untrusted input (`innerHTML`, `insertAdjacentHTML`, `document.write`). Prefer text nodes / framework binding.
- Reject `javascript:` and `data:` URLs where a user value flows into `href`/`src`/`window.open`; validate the scheme against an allowlist (`http`/`https`/relative).
- Be cautious with dynamic script/style injection and third-party embeds fed by user input.
- For an embedded `<iframe>`, do not default the `sandbox` attribute to a permissive value — in particular do not include `allow-same-origin` (combined with `allow-scripts` it lets the framed content escape the sandbox). Start from the most restrictive `sandbox` and add only the tokens required, allowlisting specific embed hosts rather than granting broadly. A value the docs explicitly warn against must not be the default.

Report only sinks reachable from user-controlled or external input.

## Focus B: Authorization, Input Validation, And Secret Handling

Review authorization, validation, CSRF, and secrets exposed to the client.

- Every server route / API handler must enforce authorization server-side — authenticated *and* permitted for this specific resource — on read, update, and delete. Do not rely on the UI hiding an action. Guard against privilege lockout (removing the last admin, a user demoting themselves out of access).
- Do not fetch or proxy a user-supplied URL from the server without validating it against a scheme/origin allowlist (SSRF); pass secrets in request headers, not in query strings where they leak into logs and history.
- Reject inputs that collide with reserved routes or system prefixes (an id that shadows a URL path) and inputs that silently corrupt downstream operations (e.g. numeric-looking strings like `"1e+21"` that break sort/filter/aggregation).
- Client-side validation is UX only. Anything that protects data integrity or authorization must also be validated server-side; do not treat a client check as the security boundary.
- Do not embed real secrets (API keys, tokens with server privileges) in client code or public env vars; anything shipped to the browser is public. Only publishable/anon keys belong in the bundle.
- Do not store sensitive data (access tokens, PII) in `localStorage`/`sessionStorage` where XSS can read it; prefer httpOnly cookies for auth tokens.
- State-changing requests should carry CSRF protection appropriate to the auth scheme (token/SameSite cookies) when the app relies on cookie auth.
- Validate and constrain redirect targets and postMessage origins reached from user input.

Report only concrete exposure, missing-authorization, or missing-server-validation risks, not defense-in-depth wishlist items.
