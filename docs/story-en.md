# Paper from Light: How a Designer Shipped an iOS App in Ten Days

*A short hero's journey: ten days, 97 commits, one AI sidekick — and an embarrassing number of moments where I said, "Hm. That **feels** wrong."*

I'm a UI designer. I'll happily argue about a 4-point shadow for half an hour, but I can't bolt together a `for` loop on my own without googling it. And yet there's now a native iOS app on the App Store that I built: **Paper Comic Reader**, which makes comics look like ink on real paper again — instead of glowing behind cold, backlit glass.

It all started on the Mac. I'd forked *Simple Comic*, an old open-source reader, and — purely out of design lust — hand-built a **Metal shader** into it: my paper look. I sat there watching a comic page suddenly look freshly printed, and thought: *Hmm. This should work as an iPhone app too, right?*

The actual starting gun was gloriously unheroic. One evening after work I fired up Claude Code and noticed I still had **tokens left for the week** — the kind that reset the next day at the stroke of noon. Just expire. Use them or lose them. So I thought: *"OK. Let's do this." :D* No business plan, no roadmap workshop — just a leftover weekly allowance that would otherwise evaporate, and a designer with a fixed idea. That's how the best expeditions start: on a whim, right before closing time.

From then on I had a sidekick. The division of labour stayed the same for all ten days: **I felt, decided, and saw — Claude Code typed, worked out the geometry, and wrestled the toolchain.**

## The magic trick: paper from light

A screen glows. Paper doesn't. Comics were printed on warm, cream-coloured stock, and behind glass they look clinical. Too clean. Too blue. So: pull every white gently toward cream, lift pure black to a deep warm grey, ease off the saturation and contrast a touch. "Glossy display" turns into "matte print."

The part I'm genuinely proud of is the **grain** — and how it fakes paper *twice at once*, the way real paper works: a fine tooth sitting on the light areas (the rough surface of the stock), *and* fibres peeking through the ink, strongest in the dark, saturated regions. That show-through is the real charm of a printed comic: you *sense* the paper under the colour.

And here lurked the first monster. My first grain had a fine but visible horizontal-vertical **grid** — it looked like a window screen, the exact opposite of organic paper. The reason: the noise pattern was politely aligned to the pixel grid. The cure was almost poetic — you rotate every single layer of the noise a touch, so nothing lines up with the grid anymore. Nobody ever consciously notices the layers are rotated. But everybody instantly notices when they *aren't*. That's design in one sentence.

And because I think in materials rather than columns of numbers, the sliders also come as named paper stocks: *Cream Paper*, *Newsprint*, *Manga*, *E-Ink*. Four papers, one tap. To run it live on every page, the effect sits as a tiny GPU program right on the graphics card — with a full fallback path for when it can't load.

## The things only I could see

Reading comics means turning pages and rotating the device — and that's exactly where I lost my mind. On day one alone it took six attempts to get *one* rotation right, because in landscape the right half of a two-page spread must never become the left half when you turn the phone. An engineer would've said "works fine." I saw the page land on the wrong side every single time, and couldn't move on.

The meanest monster, though, was invisible — to everyone but me. Flipping through, I had this stubborn gut feeling that page turns were a hair *less smooth* than the zoom. Just a frame here, a frame there. Turns out I was right. Two animations ran on two completely different engines — one on Apple's mercilessly smooth render server, the other on a hand-rolled loop that nudged things along frame by frame on the always-busy main thread, so on 120 Hz displays it occasionally swallowed a frame. Invisible at 60 Hz. At 120 Hz: exactly the hair my eye kept demanding. The cure: rip out the loop, hand everything to the render server. **A designer's eye is a measuring instrument — sometimes a better one than the profiler.**

## The Apple ordeal

End of week one: off to the App Store. Back came a rejection with my personal favourite reason — "**Tips failed to load**." I'd built in a small, friendly tip-jar button, in case someone wanted to buy me a coffee. And that, of all things, refused to load right in front of the reviewer.

At that point I made a very deliberate, very designerly decision: it's not worth it to me. The whole approval-and-agreements circus felt, for a free little app, like an *ordeal*. So I did something unexpectedly liberating — I ripped out all the payment code and switched to **sideloading**: the app goes up on GitHub as a finished but deliberately *unsigned* package, and everyone re-signs it with their own Apple ID. Honestly fiddly for end users, but it was *mine*, and nobody had to approve it.

## A shelf full of comics that aren't there

The next piece is the one I'm secretly proudest of, even though you never get to *see* it. In week two the app grew up: it learned to read the info baked into comics — series, issue, story titles — and keeps all of that, alongside your reading progress, in a small database. (One wrong move on that database's structure, and a recovery routine can, worst case, delete the *whole* thing: every bookmark, every position — gone. So we tested the change against a real old database, column by column, *before* any user ever saw it.)

The actual magic trick came on top. A real comic collection is huge — gigabytes on gigabytes; nobody wants all of it on their phone. But you still want to *see* it — every cover, every title, searchable. The solution: you point the app at *one* folder the Files app can reach — a NAS in the living room, iCloud, a file server. It walks the folder once and pulls out only the **featherweight** bits of each comic: the cover and the metadata. Only those land on the phone; the heavy archives stay put.

The result feels like magic: **your library looks complete** — but most of those comics aren't on your phone at all, they're just *promises*. Tap one and it downloads on the spot. Done reading, or need the space? Throw the heavy file out — the cover and title stay on the shelf. A bookcase whose books materialise the moment you reach for them.

Under the hood, that's a lot of invisible plumbing: a special permission just to reach a folder outside your own sandbox, one that has to survive app restarts and that you must scrupulously hand back after every access. A NAS that's asleep — and the simple question "is the folder even there?" can *hang* on the network, so it happens far from the main thread, or the app would freeze just opening your shelf. And a classic trap: a folder called `Comics` and a neighbour called `ComicsExtra` start the same, so the app compares strictly on path boundaries, or the second gets mistaken for a child of the first. That kind of bug costs nobody any sleep. Until it does.

## The carousel that snagged

Near the end, the most elegant riddle of all: a "Discover" carousel juddered at the end of a *slow* swipe — but only then. On a fast swipe: perfect. The cause was delightfully sneaky: the stage was reading, on every swipe frame, which cover was currently centred — and so it redrew itself completely, mid-motion, shoving the card that was just trying to settle. The fix: the container simply must never know that again; only the edge views read it. Butter-smooth. And provable, by the way, only on a real device — no test script feels a stutter for you. I had to *sense* the app more than measure it.

## The return

Then, on the last day, the U-turn: back to the App Store — the very place I'd stormed out of, slamming the door. This time without a payment feature. The best plot twist: the tip-jar button from before was long gone, so "remove the payment feature" turned out to be not a coding task but a marketing sentence deleted from a form. The monster had been dead for ages; it was only haunting the fine print.

A final boss fight was mandatory, of course: the signed build failed, reproducibly, with a meaningless error. The culprit — a copy tool installed via Homebrew that had elbowed ahead of Apple's own in the system path. Two hours of hunting, one line of fix. That's how undocumented monsters die: quietly, on a one-liner. Today the app ships both ways: sideloaded from GitHub for the tinkerers, and properly on the App Store for everyone else.

## What a designer learned

"It compiles" isn't a finish line — it's the starting gun. Almost every real fight on this trip was invisible until I held the thing in my hand and *felt* it. The designer's eye that makes colleagues roll theirs is, in truth, a precision instrument. And the most honest bit to end on: I'd never have built this alone — not in ten days, and probably not in ten months. An AI pair-programmer turned "a designer with an idea" into someone who *ships*. I never wrote a single loop by hand. I felt, I pointed, I rejected, I decided.

Ten days. 97 commits. A few slain monsters. And a small app that makes comics look like paper again — born from a scrap of weekly tokens that would otherwise have expired at the stroke of noon.
