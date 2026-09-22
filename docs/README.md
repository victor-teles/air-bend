# Air docs

The documentation site for Air, built with Next.js and
[Fumadocs](https://fumadocs.dev).

```bash
pnpm install
pnpm dev     # http://localhost:3000/docs
pnpm build
```

Pages are MDX files in `content/docs/`. Each folder's `meta.json` sets the
order in the sidebar; a new page must be listed there to appear in place.
