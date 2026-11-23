# Support

How someone who is stuck reaches help. The photographer, 23 November 2026:
"ik weet niet zo goed hoe slim het is om mijn email zomaar erbij te
zetten". So nothing is decided here: the options, a recommendation, and
his choice. Then: "eigenlijk vanaf de inlogpagina hebben meerdere
gebruikers nu al hulp nodig", so help starts on the sign-in page.

## What is built, whichever he picks

- **The help page**, `docs/help.html`, on the site:
  <https://simmmmm.github.io/Jukebox/help.html>. Signing in (the port, http
  or https, a reverse proxy's path, away from home, Tailscale, the local
  network permission, Navidrome's demo to try), Last.fm, downloads.
- **Trouble signing in?** under the sign-in form on every client. It opens
  the help page at Signing in.
- **Help & Feedback**: Jukebox Help, Report a Problem (GitHub's issues),
  Copy Diagnostic Info.
  - iPhone, iPad: Settings › About.
  - Mac: the Help menu.
  - Linux: Help (F1) in the primary menu; About Jukebox has Website,
    Support Questions, Report an Issue and Troubleshooting.
- **Copy Diagnostic Info**, on the sign-in page too. It copies:

  ```
  Jukebox 1.3 (163)
  Client: iPhone
  System: Version 18.1 (Build 22B83)
  Server: Jellyfin 10.11.0
  Last.fm: on
  ```

  Never the server's address or name, the user, a token, the device's name
  or anything of the library. `AccountCheck` holds it to that.
- **One constant**, `Support.contact` in `Jukebox/App/Support.swift`, empty
  now. Filled with an address or a URL, every client gains a Contact
  Support entry. Nothing else changes.

## The options

| | His address shown | The user needs | Public | Spam | Cost |
|---|---|---|---|---|---|
| GitHub Issues | no | a GitHub account | yes | GitHub's own filters | free |
| A support address | an alias, never his own | an email app | no | the alias can be replaced | free to about 1 euro a month |
| An in-app form | no | nothing | no | his to stop | hours to build, then his server |

**GitHub Issues.** The repository is public, so this works today. Issue
templates can ask for the diagnostic info. Against it: many listeners have
no GitHub account, and a report there is public, so an address pasted into
one is public too.

**A support address.** `jukebox@` or `support@` on his own domain,
forwarding to his inbox, or an alias from SimpleLogin, Addy.io or iCloud's
Hide My Email. His own address is never shown. When spam finds the alias,
he makes another and changes the one constant. Replying shows the address
he answers from, unless he replies through the alias: SimpleLogin and
Addy.io do that, and so does a mailbox on his own domain. A plain forward
does not.

**An in-app form.** A text field that posts to an endpoint of his: a small
service beside OpenPanel, a form service (Formspree and the like, free for
a few a month), or GitHub's API making an issue from a bot account.
The friendliest for the listener, and the most work:
- a form on four clients, and a server to keep running;
- an open endpoint draws spam, so it needs a limit per address and a
  size limit at least;
- he can only answer if the listener types an email address, which is
  then personal data he stores, and `PRIVACY.md` and the App Store's
  privacy answers change (Contact Info, collected);
- a token for GitHub's API cannot ship in a public app, so that route
  needs his server in between anyway.

## What the App Store asks

A **Support URL** is required for the iPhone's and the Mac's listing, and
it must lead to a way to get help. Today it is
`https://github.com/simmmmm/Jukebox` (`RELEASE.md`). The help page is the
better answer, once it is on main. A Marketing URL is optional. App Review
also has his contact details, which are never shown.

The App Store shows no email address of the developer. Only a trader under
the Digital Services Act has an address and a phone number shown, and he
is listed as not a trader.

## What others do

Looked up on 23 November 2026, on each project's own page.

- **Finamp**: GitHub Issues and Discussions, and a Discord server. No email.
- **Feishin**: GitHub Issues and Discussions, Discord and Matrix. No email.
- **Amperfy**: GitHub Issues and Discussions. No email.
- **Symfonium** (paid): its own forum, a documentation site with an FAQ,
  and feedback from inside the app.
- **Plexamp**: Plex's forum and support site (not checked today; its page
  refused the request).

None of the open-source ones shows an email address. The one with a form
in the app is the paid one, with a forum behind it.

## Recommendation

1. **The help page first, GitHub Issues for bugs, and an alias address for
   everyone else.** Make `jukebox@` on his domain (or a SimpleLogin alias)
   that forwards to him, and put it in `Support.contact`. Point the App
   Store's Support URL at the help page. It costs nothing, shows nothing
   personal, and takes ten minutes.
2. **GitHub only**, as it is now with the constant empty. Fine for a
   while. It leaves out the listener without a GitHub account, who is
   likely the one who cannot sign in.

Not now: the in-app form. Come back to it if email becomes more than he
wants to answer by hand.

## His to decide

- Which of the two, and for 1: which address.
- Whether the App Store's Support URL becomes the help page.
- Whether `tijmen.me/jukebox/help` should serve the help page. Today only
  `tijmen.me/jukebox` is rewritten, so the apps link to github.io, and the
  site's visit count (OpenPanel, "Jukebox site") does not see the page.
