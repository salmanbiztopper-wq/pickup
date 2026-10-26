# Pickup

**Install once, keep working as usual, and Claude never loses its place.**

Pickup is a plugin for Claude Code. It keeps one plain-English page about your project, called `PICKUP.md`, and makes sure Claude reads it whenever it might have forgotten something. You never have to remember to save. If you ever want to check what Claude knows, the whole story is on one page.

It works for any kind of project: a website, an app, a design, a book, a research report.

## The problem: a full desk

Think of Claude's memory as a desk. Everything from your conversation goes on the desk: what you asked for, what Claude tried, what you decided, what broke.

In a long session the desk fills up. When it is full, Claude Code clears it and leaves a short summary note in its place. This is called compaction. The note is short, so details get lost: decisions, the reasons behind them, what already failed, and your exact words.

Claude then fills the gaps with guesses. To you, it looks like Claude is making things up, or forgetting what you agreed on. And when you start a brand-new session, the desk is empty. Claude starts with no memory of your project at all.

Pickup keeps a notebook next to the desk. When the desk gets cleared, or a new session starts, the notebook goes straight back on the desk.

## What you get

A file called `PICKUP.md` appears in your project folder after the first real piece of work. It looks like this:

```markdown
# Where this project stands

Last updated: 2026-10-16 17:45

## What we're building
A one-page website for Rosa's Bakery, with a menu and an order form.

## The plan
- [x] Home page with the bakery's story
- [x] Menu section with photos
- [ ] Order form that sends an email
- [ ] Publish the site

## Decisions (and why)
- Green order button: Rosa wants it to match the shop sign.
- No online payments for now: Rosa takes payment when people pick up.

## Next step
Build the order form in index.html: name, phone, cake choice, pickup day.

## Watch out
- The photos in /images are large. Shrink new ones before adding them.
- Don't change the logo colors. Rosa approved them.

## Waiting on you
- Which email address should orders go to?

<!-- pickup:facts:start -->
## Last session facts
_Copied automatically by Pickup from the session record. Claude does not write this part._

Updated: 2026-10-16 17:40

**Your latest requests (newest first)**
1. "make the order button green and bigger"
2. "add a menu section with photos"

**Files changed recently (newest first)**
- styles.css
- index.html
<!-- pickup:facts:end -->
```

The notebook has two parts:

- **The top part is written by Claude.** It holds the meaning: what you're building, the plan, the decisions and why, the next step, the traps, and the questions only you can answer.
- **The bottom part is copied by Pickup itself.** It holds the hard facts: your latest requests, word for word, and the files that changed. Claude doesn't write this part, so it can't be made up.

You can read the notebook and change it any time. If you fix something in it by hand, Claude follows your version.

## Install

You need Claude Code. Type these two commands into Claude Code, one at a time:

```
/plugin marketplace add salmanbiztopper-wq/pickup
```

```
/plugin install pickup@pickup
```

Then restart Claude Code, or type `/reload-plugins`. That's it.

## What happens on its own

You don't need to do anything. Pickup works in the background.

- **When you open a session,** Claude starts its first reply with one line on where things stand, like *"Last time we finished the menu. Next is the order form."* Then it does what you asked.
- **While you work,** Claude updates the notebook after real progress. If a number of files have changed since the last update, Claude is reminded to update it before it finishes its reply. Claude can update the notebook without asking you for permission each time. Pickup allows this for `PICKUP.md` only, never for any other file, and your own permission rules still come first.
- **When the desk gets cleared (compaction),** Pickup copies the latest facts into the notebook first. Afterwards it puts the notebook straight back on Claude's desk. Claude checks the next step before carrying on, and tells you in one line that a clean restart is there if things feel off: a new chat in the same folder, or `/clear`.
- **When you close a session,** Pickup copies the latest facts into the notebook, so it's ready for next time.

## The three commands

You rarely need these, but they're there when you want them.

| Command | What it does |
|---|---|
| `/pickup:save` | Updates the notebook right now. Replies in one line: "Saved. Next step: ..." |
| `/pickup:status` | Tells you where the project stands: what we're building, what's done, the next step, and anything waiting on you. Doesn't change anything. |
| `/pickup:handoff` | Gets the notebook fully ready for a fresh start. Then tells you: "Handoff ready. Open a new chat in this same folder (this chat stays as it is), or type /clear to start fresh here. Either way, I'll pick up from the notebook." |

Plain words work too. Try "save progress", "where are we?", or "this session feels confused, let's start fresh".

**When to use handoff:** if Claude starts going in circles, repeating old mistakes, or forgetting what you agreed, the session is worn out. Type `/pickup:handoff`. Then pick one:

- **Open a new chat in the same project folder.** Your old chat stays as it is, so you can scroll back through it any time.
- **Or type `/clear`** to start fresh in the same chat window.

Either way, the new session starts from the notebook with a clean desk.

## Where things are stored, and privacy

- **The notebook** is `PICKUP.md` in your project folder. You can see it, edit it, and share it like any other file.
- **The activity record** is a private log of your requests and the files that changed. It's kept in Claude Code's own plugin folder on your computer (`~/.claude/plugins/data/`), never in your project folder. It also notes where Claude Code keeps each session's chat history, for the coming Recall feature.
- **Only a cleaned-up copy goes into the notebook.** Anything that looks like a password, key or token is replaced with `[hidden]`, and each request is cut to a short length.
- **Nothing leaves your computer.** There are no accounts and no cloud.
- **If you share your project** (for example on GitHub), `PICKUP.md` goes with it, including your latest requests. Have a quick look at it before sharing. If you don't want `PICKUP.md` shared at all, ask Claude to add it to your `.gitignore` file.
- **If you uninstall Pickup,** Claude Code deletes the private log. Your `PICKUP.md` files stay where they are.

## Turning it off for one project

Create an empty file called `.pickup-off` in that project's folder. Pickup then stays completely quiet there. The easiest way is to ask Claude: "create an empty file called .pickup-off". To turn Pickup back on, delete the file.

## Requirements

- **Claude Code.**
- **On a Mac or Linux:** nothing else.
- **On Windows:** [Git for Windows](https://git-scm.com/downloads/win). Claude Code uses it to run Pickup. Most people who use Claude Code on Windows have it already.

There's nothing else to install: no accounts, no extra programs.

## Settings

The defaults work for most people. To change one, add it to your Claude Code settings file (`~/.claude/settings.json`) under `"env"`. For example, to be reminded less often:

```json
{
  "env": {
    "PICKUP_SAVE_AFTER_EDITS": "10"
  }
}
```

| Setting | Default | What it does |
|---|---|---|
| `PICKUP_SAVE_AFTER_EDITS` | `6` | How many file changes before Claude is reminded to update the notebook. The notebook first appears after half this many. `0` turns reminders off. |
| `PICKUP_FACT_REQUESTS` | `5` | How many of your latest requests the notebook shows. |
| `PICKUP_FACT_FILES` | `10` | How many recently changed files the notebook shows. |
| `PICKUP_REQUEST_CHARS` | `280` | How long each copied request can be, in bytes (about 280 English letters). |
| `PICKUP_CONTEXT_BYTES` | `9000` | The most text Pickup loads at the start of a session. A longer notebook is cut, and Claude reads the rest from the file. |
| `PICKUP_NOTEBOOK` | `PICKUP.md` | The notebook's file name. |
| `PICKUP_OFF_FILE` | `.pickup-off` | The name of the file that turns Pickup off in a project. |

## Good to know

- "Files changed recently" only lists changes Claude makes with its normal editing tools. If Claude changes a file by running a terminal command, that file won't appear in the list.
- If you move or rename a project folder, Pickup starts a fresh private log for it. The notebook itself moves with the folder and keeps working.

## Questions

**How is this different from Claude Code's built-in memory?**
Claude Code's memory (the `CLAUDE.md` file and its own notes) holds lasting instructions and habits, like "this project uses these tools" or "always write in British English". It doesn't keep track of where a piece of work stands: the plan, what's done, what failed, and the very next step. Pickup does exactly that, and it puts the notebook back after every compaction. They work well together.

**How is this different from claude-mem and other memory tools?**
Tools like claude-mem, Supermemory and Mem0 are built for developers. They store your history in a database that Claude searches, and they usually need extra software or an account. Pickup is the simple one: a single page in your project folder that you can read and fix yourself, with nothing extra to install.

**Will it slow Claude down or use up the desk?**
Barely. Pickup adds nothing to the desk while you work. It only loads the notebook at the start of a session and after a compaction, and it keeps that short.

**What if Claude writes something wrong in the notebook?**
Open `PICKUP.md` and fix it. Claude follows your edited version.

## Coming next: Recall

Recall, for finding your exact words from older chats. For example: "what exactly did I say about the logo last week?"

## License and author

MIT License. Made by Salman Islam. Source and issues: [github.com/salmanbiztopper-wq/pickup](https://github.com/salmanbiztopper-wq/pickup)
