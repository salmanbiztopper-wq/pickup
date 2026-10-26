---
name: status
description: Say in plain English where the project stands, from the project notebook (PICKUP.md). Read only, never changes the file.
when_to_use: Use when the user runs /pickup:status or asks things like "where are we?", "what's the status?", "what have we done so far?", "what's next?", or "remind me where we left off".
---

# Project status

## Most important rules

1. Read only. Do not change `PICKUP.md` or any other file.
2. Answer from `PICKUP.md` in the project folder. It is the source of truth, including any changes the user made by hand.
3. Plain English, short sentences, no jargon. The user may not be a programmer.

## Steps

1. Read `PICKUP.md` in full.
2. Answer in this order, briefly:
   - **What we're building:** one sentence.
   - **Done so far:** the finished steps, as a short list.
   - **Next step:** the very next thing to do.
   - **Waiting on you:** anything only the user can answer. Leave this out if there is nothing.
3. If the notebook looks out of date compared with this conversation, say so in one line and suggest `/pickup:save`.

If `PICKUP.md` does not exist, say there is no notebook for this project yet. It appears on its own after the first real piece of work, or the user can run `/pickup:save` to create it now.
