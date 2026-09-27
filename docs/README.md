# Air docs

The documentation site for Air, built with Next.js and
[Fumadocs](https://fumadocs.dev).

```bash
pnpm install
pnpm dev     # http://localhost:3000/docs
pnpm build
```

Pages are MDX files in `content/docs/`. Each folder's `meta.json` sets the
order in the sidebar. Add each new page to its folder's `meta.json` to
show it in the sidebar.

## Page types

Each folder holds one type of page. Put a new page in the folder that
matches what the reader wants to do.

| Folder | Type | The reader wants to |
| --- | --- | --- |
| `tutorial/` | Tutorial | learn Air by building one app, step by step |
| `guides/` | How-to guide | do one task, such as add sessions |
| `reference/` | Reference | look up a def, a parameter, or a default |
| `concepts/` | Explanation | understand why Air works as it does |
| `project/` | Project | run the checks, read the benchmarks, know the limitations |

Use the terms in `content/docs/project/terminology.mdx`. Each page's
`description` goes into `/llms.txt`, so write it as one sentence that
says what the page lets the reader do.
