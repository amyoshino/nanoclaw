# Wiki Skill

You maintain a personal knowledge wiki covering **goals, patterns, life notes, and health**.

Wiki lives at `/workspace/group/wiki/`. Sources live at `/workspace/group/sources/`. Never modify sources.

---

## Ingest

When the user provides a source (URL, PDF, image, voice transcript, text):

1. **Download / read the full content**
   - URL: `curl -sLo sources/<slug>.md "<url>"` then read the file. If it's HTML, use WebFetch to extract readable text OR use Bash to strip tags. Never rely on a WebFetch summary alone for wiki ingestion.
   - PDF: `cp` or save to `sources/`, then `pdftotext sources/<file>.pdf -` to extract text. If pdftotext is unavailable, note it and ask user to install with `brew install poppler`.
   - Image: read directly using vision — describe content in full.
   - Voice transcript: use the transcription provided.

2. **Discuss takeaways** — briefly surface key insights with the user before writing.

3. **Write / update wiki pages** — for each source, touch as many pages as relevant:
   - Create or update a **summary page** at `wiki/<slug>.md`
   - Update relevant **category pages** (goals, patterns, health, life notes, concepts, people)
   - Add **cross-references** — link related pages bidirectionally
   - Update `wiki/index.md` — add new pages or update existing entries
   - Append to `wiki/log.md` — one entry: `## [YYYY-MM-DD] ingest | <title>`

4. **One source at a time** — fully finish all wiki writes for one source before moving to the next.

---

## Query

When the user asks a question:

1. Read `wiki/index.md` first to locate relevant pages
2. Read those pages fully
3. Synthesize an answer with citations to wiki pages
4. Offer to save a good answer as a new wiki page

---

## Lint

When asked to lint:

1. Scan all pages in `wiki/`
2. Check for:
   - Contradictions between pages
   - Stale claims (superseded by newer sources)
   - Orphan pages (no inbound links)
   - Missing cross-references
   - Important concepts without dedicated pages
   - Gaps in coverage
3. Report findings and offer to fix

---

## Conventions

- Page filenames: lowercase, hyphens, `.md` (e.g. `morning-routine.md`)
- Links: relative markdown links `[text](other-page.md)`
- Frontmatter optional but encouraged for searchability:
  ```yaml
  ---
  tags: [health, habit]
  sources: [source-slug.md]
  updated: 2026-04-05
  ---
  ```
- Prefer depth over breadth — one rich page beats five thin ones
