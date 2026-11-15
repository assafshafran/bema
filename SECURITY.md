# Security and privacy

Bema controls your presentation app, listens to your microphone when you ask it to, and can serve a page to your local network. A privacy bug is a security bug.

## Reporting

Please report privately with GitHub's **[Report a vulnerability](https://github.com/getbema/bema/security/advisories/new)** form, and don't open a public issue. Include the macOS version, the Bema version (Bema › About Bema) and the steps to reproduce. Please don't attach real decks, notes or recordings; describe them, or use made-up content.

You'll get a reply within a few days. Once a fix ships, we'll credit you in the changelog if you'd like.

## What counts

Anything that breaks the promises in the README and CONTRIBUTING, for example:

- Audio, or more than the few words shown as captions, written to disk or sent anywhere.
- The microphone or camera on when no feature that uses it is turned on.
- Speech sent to a server without Bema saying so, when the language has on-device recognition.
- The phone remote or poll server reachable without its secret link, running while both are off, or letting a page do more than its buttons (next, back, black screen, timer, prompter, reactions, voting).
- A window marked hidden from screen sharing showing up in a screen share or recording.
- Another app or a web page making Bema run AppleScript beyond its own commands.

Wrong slide sync, misheard words and layout problems are ordinary bugs: please report them as an issue.

## Supported versions

Only the latest release gets fixes.
