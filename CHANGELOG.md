# Changelog

Versions use MAJOR.MINOR.PATCH. The number lives in the `VERSION` file only; the build, setup, uninstaller, Windows Apps entry and the board all read it from there.

- MAJOR: a change that breaks settings or the way people use the board.
- MINOR: a new feature.
- PATCH: fixes only.

## 1.1.0 — 2026-09-24

**New**
- Pick a colour per customer (Amber, Blue, Violet, Pink, Cyan, Slate) in the setup and on the Settings page; each customer section on the board uses its colour.
- Modern setup and uninstall window (follows Windows light/dark mode) with Details, Installing, Done and Error pages.
- Silent install for IT through the setup file itself, with strict input checks, an exit code and a log file.
- The version number is shown on the board, on the Settings page and in the setup.

**Fixed**
- Meetings with a Webex, Zoom or Google Meet link only in the invitation text now show.
- At most two drafts run at the same time, also for "Try again", "Regenerate" and several tabs.
- Drafts of an expired Copilot conversation continue in one shared new conversation.
- Short connector, network and throttling errors are retried once, also for briefings and drafts.
- Upgrades are safe: if anything fails, the previous version and settings come back.
- Customer sections read more than 50 emails and show "+" when the list may be incomplete.
- Save and Print include only finished drafts.
- The build checks the Node.js engine's version, checksum and signature.
- Other websites cannot start a sign-in.
- Briefing sections show at most 6 lines; saved files use the meeting date; the meeting count shows "+" when cut off; screen readers no longer read the timer every second.
- A board started from the setup no longer locks the setup's temporary folder.

## 1.0.0 — 2026-09-24

- First installable version: live mail triage with up to three customer sections, meetings today and tomorrow, Copilot pre-meeting briefings and follow-up artifact drafts, Settings page, setup with upgrade and removal.
