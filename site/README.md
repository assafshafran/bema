# Bema website

Static landing page and docs, live at https://getbema.dev (and www.getbema.dev).
Hosted on Cloudflare Workers static assets (`wrangler.jsonc`); no build step. To redeploy after a change:

```bash
cd site && npx wrangler deploy
```

`.assetsignore` keeps this README, `wrangler.jsonc` and `demo-deck/` off the live site.

Links point at the GitHub repository and its releases (the first signed release is still to come). The hero's Dock uses generic icons, never other companies' app icons. Remaining placeholders: the `[PHOTO NEEDED]` / `[SCREENSHOT NEEDED]` boxes, if any.
`img/presenter.jpg` is a real capture of the presenter window rehearsing `Samples/Sample.pptx`.
The design source lives on the private Claude Design canvas "Bema website".

## Photo credits
The call participants in the hero are free photos from Unsplash (https://unsplash.com/license):
noa.jpg Wcp5t-CdH4E · daniel.jpg cMsdRjEApeo · amir.jpg rmzF0er-JeY · omer.jpg Vr9hsELbhu8 · lior.jpg lDQFD3t3oGk · you.jpg 5ruK7pUXzrA (photo ids, at https://unsplash.com/photos/<id>).

## Dock icons
`img/dock/*.png` are the real macOS, Microsoft and Bema app icons, rendered from the apps installed on the design machine. Apple and Microsoft icons are their owners' trademarks: check their guidelines before the site goes public, or swap in a real screenshot of a desktop.
