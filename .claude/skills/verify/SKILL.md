---
name: verify
description: Run full project verification — format, type-check engine, tools, and all examples. Use before submitting changes.
---

Run the full verification pipeline:

```bash
just verify
```

This runs: `format` → `check` → `check-tools` → `check-all-examples`

If any step fails, fix the issues and re-run. All code must pass strict vetting flags (`-vet -strict-style -vet-semicolon -vet-cast -vet-using-param -vet-shadowing -warnings-as-errors`).
