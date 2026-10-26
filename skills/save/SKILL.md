---
name: save
description: Update the project notebook (PICKUP.md in the project folder) right now, creating it from the Pickup template if it does not exist yet. Replies in one line with the next step.
when_to_use: Use when the user runs /pickup:save or says things like "save progress", "save where we are", "update the notebook", "write this down for next time", or "remember where we are".
---

# Save the project notebook

## Most important rules

1. The notebook is `PICKUP.md` in the project folder (the folder this session was opened in).
2. Never write anything between `<!-- pickup:facts:start -->` and `<!-- pickup:facts:end -->`. Pickup fills that part automatically. Keep both marker lines exactly as they are, at the bottom of the file.
3. If the user has edited the notebook by hand, keep their changes. Their version wins.
4. When done, reply with exactly one line: `Saved. Next step: <the next step>`

## Steps

1. If `PICKUP.md` does not exist, read the template at `${CLAUDE_PLUGIN_ROOT}/templates/PICKUP.md` and create `PICKUP.md` with exactly that content.
2. Read `PICKUP.md` in full.
3. Update each section from what you know from this conversation. Replace any template placeholder text in brackets.
   - **Last updated:** today's date and time.
   - **What we're building:** one or two plain sentences.
   - **The plan:** a checklist. Tick finished steps with `[x]`, add new ones. If the list gets long, fold finished steps into one line, such as `- [x] Done so far: menu, photos, order form`.
   - **Decisions (and why):** one line each, `decision: reason`. Keep old decisions. If one was reversed, change it and say what replaced it.
   - **Next step:** the very next thing to do, specific enough to start without asking: which file, which part, what exactly.
   - **Watch out:** traps, things that broke before and why, things not to touch.
   - **Waiting on you:** only questions or decisions the user must answer. Remove answered ones.
4. Write for someone who is not a programmer: plain words, short sentences. Keep the whole notebook short, about 150 lines at most.
5. Save the file, then send the one-line reply.

If an empty file named `.pickup-off` exists in the project folder, Pickup is switched off here. Tell the user, and only save if they confirm.
