# tf997.github.io

The website behind Readthroughs: recommendation links, the file that lets those links open the app, and the reading lists.

| Path | What it is |
|---|---|
| `r/` | The page a recommendation link opens when the app isn't installed. The recommendation is in the link after the `#`, so the server never sees it. |
| `.well-known/apple-app-site-association` | Tells iOS that links under `/r/` open Readthroughs. |
| `lists.json` | The reading lists shown on the Lists tab. |
| `tools/` | The publishing check. Not published. |

## Reading lists

### When phones pick up a change

1. After a change is merged to `main`, the workflow publishes it. GitHub can keep serving the old `lists.json` for up to about 10 minutes after that.
2. The app checks for a new `lists.json` when it's opened or brought back to the front, **at most once every 24 hours** since its last successful check. There's no fixed time of day.
3. A check that fails (no connection, site down, a file it can't read) doesn't count, so the app tries again next time it's opened.

So expect a change on a phone the first time the app is opened after its 24 hours are up: within about a day for daily users. To see it sooner on your own phone, delete and reinstall the app.

The app also ships with the lists, so they're there on first launch and offline.

### The rules

Lists are **append-only**, so nobody's progress through a list, or a shelf reward tied to it, ever moves:

- You **can** add a new list, add it to a group, rename or reorder groups, and correct a book's `pages` or `coverID`.
- You **can't** remove a list, or add, remove, reorder or retitle the books on a list that's been published, or change its winner.
- A list's `id` never changes; rewards are tied to it.

The workflow checks every change against the `lists.json` that's live and refuses to publish one that breaks these rules. Phones enforce the same rules themselves: they keep every list they've seen, with its books unchanged, whatever the website later says.

Removing or fixing a published list needs an app update first.

### File format

```json
{
  "version": 1,
  "sections": [{ "title": "Prizes of 2026", "lists": ["booker-2026"] }],
  "lists": [{
    "id": "booker-2026",
    "name": "Booker Prize",
    "detail": "2026 shortlist",
    "kind": "prize",
    "books": [{ "title": "The End of Everything", "author": "M. John Harrison", "pages": 208, "coverID": 15239006, "winner": true }]
  }]
}
```

`kind` is `prize`, `author` or `genre`. `pages`, `coverID` and `winner` are optional; `coverID` is an Open Library cover number. Raising `version` hides the file from apps that don't understand it.

## Publishing

Changes go through a pull request. The **Check and publish** workflow runs the check on every pull request and on `main`, and only publishes when it passes. `tools/ListsFile.swift` is a copy of the app's `PagePlanner/Support/ListsFile.swift`; a test in the app fails if they differ.
