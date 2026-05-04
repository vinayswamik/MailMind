<div align="center">
  <img src="MailMind/LaunchMarkLaunch.png" alt="MailMind logo" width="280">
</div>

# MailMind

I built **MailMind** — an iPhone app for people who live in Gmail but want **less noise and faster decisions**.

---

### What you use MailMind for

- **Work from one place:** connect your Gmail account(s) and read, triage, and follow up without jumping between tabs and clients.
- **Decide faster:** see previews, thread context, and short summaries so you know whether to reply, archive, or ignore.
- **Stay organized:** group mail into **categories** you care about instead of a single endless unread list.
- **Trust your data path:** Gmail sign-in uses Google’s OAuth over HTTPS; tokens stay in the **Keychain** on your device. MailMind is not a webmail service that stores your inbox on our servers.

---

### What MailMind provides


| Area                  | What you get                                                                                                                                                                                        |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Gmail**             | Sign in with Google, sync mail, and work with your real threads and labels through Google’s APIs.                                                                                                   |
| **Inbox experience**  | Home and archive views, per-message detail, unread handling, and haptics-driven flows tuned for quick triage.                                                                                       |
| **Intelligence**      | On-device help (including **Apple Intelligence / Foundation Models** where available) for categorization and summaries so your mail content isn’t sent off to a random cloud “inbox AI” by default. |
| **Background work**   | Background refresh and **silent push** hooks (when configured) so new mail can wake sync without you staring at the app.                                                                            |
| **Skills & settings** | Customizable behavior in settings (including developer-oriented tools if you’re testing sync).                                                                                                      |

This repository contains the **iOS app source** under the [MIT License](LICENSE).

To build it yourself, copy `MailMind/Info.plist.example` to `MailMind/Info.plist`, add your Google Sign-In client ID and the other keys described in that file, then open `MailMind.xcodeproj` in Xcode.