# Bricksmith

## Code comments

Keep comments short, in simple English.

- Say what the code does or when it runs, in one or two short sentences. One line is best.
- Add a short "why" only when the code would look wrong or pointless without it: a guard that
  isn't obvious, an order that matters, or a rule that prevents data loss.
- No history ("used to…"), bug stories, long examples, or links to other files and tests. Put
  those in the commit message or `docs/`.
- Use simple words and short sentences. No jargon, metaphors, or *italic*/**bold** emphasis.
- Don't write comments that only repeat the code or the test name.

## Code layout

- In a multi-line Objective-C call or method declaration, line up the colons of the following
  lines under the first colon. For a nested call, line up under the inner call's first colon.
- Indent with tabs (width 4), then spaces to reach the exact column.
- After a rename, check the alignment of every call that uses the renamed name.
- Keep lines under about 120 columns. Move a long argument into a local rather than let a line run
  on.

## Spelling

Use American English in names, comments, strings, tests and docs: color, center, gray,
behavior, -ize, -ized. Keep keywords a file format defines as they are, such as LDraw's `!COLOUR`.
