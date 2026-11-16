# Bema website

The landing page and docs for Bema, served at https://getbema.dev (and www.getbema.dev).
Plain static files, no build step. They're hosted on Cloudflare Workers static assets; `wrangler.jsonc` holds the config and the two custom domains. To redeploy after a change:

```bash
cd site && npx wrangler deploy
```

`.assetsignore` keeps this README and `wrangler.jsonc` off the live site.

## Before the first release
The Download buttons point to https://github.com/getbema/bema/releases/latest. There's no release yet, so that link returns a 404 until the first one is published.

## Everything in Bema
The home page's feature cards and their side panel come from the list in `features.js`. When a feature is added or changed (see `docs/GUIDE.md`), add or update its card there. Each card can be opened by a link: `#feature-<id>`, or any element with `data-feature="<id>"`.

## What's real and what's drawn
- `img/presenter.jpg` is a capture of Bema's presenter window running the demo deck, and `img/slide-projected.jpg` is that deck's title slide. The deck is `Samples/Sample.pptx`, built by `Scripts/make_sample_deck.py` (needs `python-pptx`).
- The hero's desktop, meeting window, Dock icons and prompter strip are drawn in HTML and CSS. They're generic on purpose: no other company's icons or logos.
- The detached prompter is shown as an illustration: macOS keeps that window out of screenshots.
- `brand/` holds the logo mark (dark and light versions).

## Photo credits
The people in the hero's meeting window are free photos from Unsplash (https://unsplash.com/license), shown with made-up first names:
noa.jpg Wcp5t-CdH4E · daniel.jpg cMsdRjEApeo · amir.jpg rmzF0er-JeY · omer.jpg Vr9hsELbhu8 · lior.jpg lDQFD3t3oGk · you.jpg 5ruK7pUXzrA (photo ids, at https://unsplash.com/photos/<id>).
