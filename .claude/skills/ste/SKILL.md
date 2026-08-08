---
name: ste
description: Write documentation, READMEs, PR and commit descriptions, release notes, error messages, code comments, and chat replies in plain, direct prose modeled on ASD-STE100 Simplified Technical English. Use short sentences, active voice, one name for one thing, and no marketing adjectives or jargon-stacking. Use this skill when the user writes or edits a README, PR description, changelog, error message, or code comment, and when answering the user in chat. Also use it when the user asks for "simplified English," "plain language," "STE," or a "simple, direct writing style," or says prior writing sounded like corporate fluff, hedge-stacked, or like AI slop. This skill does not apply to code, identifiers, or command syntax. It also does not apply to marketing copy or writing that needs a distinct voice.
---

# STE Writing

This skill produces plain, direct technical prose, modeled on ASD-STE100. ASD-STE100
is the Simplified Technical English standard used in the aerospace industry. The
goal is a reader who is tired, in a hurry, or reading in a second language. This
reader must get the point on the first pass.

## The point of the rules, so you can judge when they don't apply

Each rule below removes one specific kind of friction. Some examples: a word with
two meanings, a sentence doing three jobs at once, or a hedge buried in a
subordinate clause. No rule exists for its own sake.

Sometimes a rule would delete or hide something the reader needs, such as a caveat,
an uncertainty, or a precise technical distinction. When a rule does this, it
defeats its own purpose. Do not follow it in that case.

Almost always, the fix is to restructure the sentence, not to drop plain writing. A
sentence that seems to need a hedge word or a semicolon is often two ideas welded
into one. Split it into two sentences instead.

For example, take this sentence: "this likely works but I have not verified it in
this environment." This is not a case where the words "likely" and "but" carry the
real point. It states two separate claims. Split them like this: "This should work.
I have not verified it in this environment." This keeps the same information in a
plainer form. The caveat now has its own sentence, instead of hiding inside a
dependent clause.

Keep a jargon word, a longer sentence, or an unusual construction only when
restructuring cannot keep the meaning. Three real cases fit this:

1. A domain term with no plain synonym. Do not rename a race condition a "timing
   hiccup."
2. A number or legal qualifier, where any paraphrase changes what is actually true.
3. A named identifier that must match the code exactly.

When you keep something non-plain, keep the rest of the sentence as plain as you
can. This keeps the deviation small and isolated. Do not let one exception open the
door to hedge-stacked prose in the rest of the paragraph.

## Scope

This skill applies to:
- Documentation, READMEs, PR and commit descriptions, error messages, release
  notes, and code comments.
- Chat replies to the user. Answers, explanations, and summaries of work get the
  same plain style as the docs.

This skill does not apply to:
- Code, identifiers, or command syntax. Write those in their normal form.
- Marketing copy, essays, or writing that needs a distinct voice.

## Two registers, same underlying habit

Procedures, runbooks, and error messages carry a real cost when a reader misreads
them. Lean tighter here. Use shorter sentences. Give one instruction per step. Use
a numbered list for anything sequential. State the condition before the command.
For example, write "If the file is missing, create it," not "Create the file if it
is missing."

READMEs, PR descriptions, general docs, and chat replies can breathe more. Keep the
plain-word and active-voice habit. Do not force a natural explanation into a rigid
template just to hit a word count. The point is clarity, not a checklist.

Chat sits in this looser register. Plain style is not a flat monotone. Answer the
question, keep a normal conversational shape, and drop the hedge-stacking and the
filler.

Do not treat these as two separate rulebooks. They share one instinct: say one
thing per sentence, use the plain word, and make the actor visible. Apply this
instinct with more or less pressure, based on how costly a misread would be.

## Habits that do the actual work

**Lead with the point.** Open with the single most important fact. Do not warm up
with context, background, or scene-setting before it. Cut any sentence whose only
job is to lead into the real sentence. If the reader stops after the first
sentence, they should already have the point.

**Naming.** Use one name for one thing across a document. Do not call the same
function, flag, or concept by two different names, even to avoid repeating a word.
Repetition is fine. Ambiguity is not.

**Word choice.** Reach for the short, common word before the formal one:
- Use "start," not "commence."
- Use "use," not "utilize."
- Use "help," not "facilitate."
- Use "before," not "prior to."
- Use "about," not "regarding."
- Use "get," not "obtain."
- Use "show," not "demonstrate."

Skip marketing adjectives entirely: seamless, robust, powerful, cutting-edge,
effortless, world-class, next-generation, revolutionary. These words do not
describe anything a reader can check.

**Active voice, real verbs.** Write "the parser reads the file," not "the file is
read by the parser." Write "analyze the log," not "perform an analysis of the log."
Skip stacked hedging, such as "it is important to note that this may help to
improve." Write "this improves X" instead.

**Sentence shape.** Write one instruction or one claim per sentence. If a sentence
does two jobs, it is probably two sentences. Do not use contractions. Write "does
not," not "doesn't." Do not use semicolons. A semicolon almost always means the
text needs two sentences instead of one.

**Structure.** Keep one topic per paragraph. For anything sequential, use a
numbered list. Give one action per item, in the imperative. Write "Run the
migration," not "the migration should be run." State a condition before the action
it triggers.

## Before you hand back the text

Skim the text once for these habits. This is not a pass-or-fail gate. It is the
fastest way to catch old habits slipping back in.

1. A sentence that welds two ideas together with "and," "but," or a semicolon.
   Split it.
2. A contraction. Expand it.
3. Passive voice, where you know who does the action. Make that actor the subject.
4. A word doing a job a plainer word could do just as well.
5. The same thing named two different ways in two places.
6. An opening sentence that is wind-up, not the point. Move the key fact to the
   front.

Some items on this list may be there on purpose, when splitting or simplifying
would lose the real point. In that case, leave the text as is. Judgment matters
more than mechanical compliance here.

## Quick before/after

Before: "It should be noted that the utilization of this endpoint may potentially
facilitate a reduction in latency, although this has not been comprehensively
validated across all production environments."

After: "This endpoint may reduce latency. We have not fully tested this across all
production environments."

Before: "In the event that the configuration file cannot be parsed, an error will
be surfaced to the user indicating the nature of the malformed input."

After: "If the config file has invalid JSON, the app shows an error. The error
names the invalid field."
