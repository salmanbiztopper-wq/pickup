---
name: handoff
description: Prepare a clean restart. Brings the project notebook (PICKUP.md) fully up to date so a brand-new session that never saw this conversation can continue, then tells the user they can open a new chat in the same folder or type /clear.
when_to_use: Use when the user runs /pickup:handoff or says things like "this session feels confused, let's start fresh", "let's start over clean", "prepare a handoff", "wrap up so a new chat can continue", "I want to continue in a new chat", or "I want to clear and continue".
---

# Hand off to a fresh session

## Most important rules

1. Write the notebook for a reader who knows nothing about this conversation. In a new chat, or after `/clear`, the notebook is all the next session gets.
2. Take extra care with **Next step** and **Watch out**. They must be specific enough to continue without asking anything.
3. Never write anything between `<!-- pickup:facts:start -->` and `<!-- pickup:facts:end -->`. Keep both marker lines exactly as they are, at the bottom of the file.
4. If the user has edited the notebook by hand, keep their changes. Their version wins.
5. When done, reply with exactly: `Handoff ready. Open a new chat in this same folder (this chat stays as it is), or type /clear to start fresh here. Either way, I'll pick up from the notebook.`

## Steps

1. If `PICKUP.md` does not exist in the project folder, read the template at `${CLAUDE_PLUGIN_ROOT}/templates/PICKUP.md` and create `PICKUP.md` with exactly that content.
2. Read `PICKUP.md` in full.
3. Update every section, the same way as a normal save:
   - **Last updated:** today's date and time.
   - **What we're building:** one or two plain sentences.
   - **The plan:** tick finished steps with `[x]`, add new ones, fold long runs of finished steps into one line.
   - **Decisions (and why):** every decision that still matters, with its reason, including ones made only in this conversation.
4. Then give the two key sections extra care:
   - **Next step:** the exact next action: which file or part, what to change, and how to tell it worked. If something is half done, say exactly where it stopped.
   - **Watch out:** what was tried and failed, and why. Things that must not be touched. Anything the user asked for in specific words that a new session could get wrong.
5. **Waiting on you:** list open questions only the user can answer. Remove answered ones.
6. Plain words, short sentences, about 150 lines at most for the whole notebook.
7. Save the file, then send the exact reply from rule 5.
