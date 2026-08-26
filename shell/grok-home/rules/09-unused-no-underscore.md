# Unused params — no underscore silence (Grok pointer)

**Status:** Grok pointer only. Full hardline is control-layer
`unused-declarations` (preamble tier 1) in `@revealui/harnesses`.

## Adapter summary

Every session: **never** rename to `_line` / `_unused` / `_req` to quiet
TS6133 or Biome when the honest fix is implement the value, remove the
parameter from an API you control, or delete dead code.

Underscore is allowed only for host-mandated callback arity or IaC
side-effect constructs, and only with a comment naming why.

Do not re-author the full body here. Edit
`packages/harnesses/src/content/definitions/rules/unused-declarations.ts`.
