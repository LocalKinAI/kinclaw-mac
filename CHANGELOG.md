# Changelog

All notable changes to KinClaw Mac.

## [Unreleased] — Companion mode, and a panel that says what it is doing

A day and a half on two things: making the companion mode something you
can actually talk to, and making Cowork and Code tell you what the
agent is allowed to do.

### Companion mode (⇧⌘M)

The panel becomes a picture and a voice. No transcript, no buttons —
you speak, it answers out loud, and what you are looking at responds.

- **It talks like a conversation, not a form.** Sentences are spoken as
  the model writes them rather than after it stops, so the first words
  land about a second in instead of after the whole reply. Kokoro pads
  every clip with ~400ms of silence in front and ~700ms behind, which
  between streamed sentences is a 1.1s hole — trimmed to 60/160ms. The
  play queue holds decoded players, and the voices are warmed on entry
  because Kokoro's first Chinese sentence after idle takes 3.4s and its
  first English one 2.4s, against 0.5s warm.
- **You can cut in.** Through headphones, talking over it stops it and
  takes your words. Through the Mac's speakers the microphone hears the
  agent louder than it hears you (measured: −14…−4 dBFS with echo
  cancellation on), so barge-in is gated on the output route and the
  halo is tappable instead.
- **The face reacts to the conversation.** Every reply opens with a
  hidden `[情绪·主题]` tag — never spoken — that picks the art: mood
  from five folders, and a subject keyword matched against the
  pictures' own filenames and credits, which already describe them.
  Say "beach" and the background is a beach. A subject with nothing on
  disk changes nothing, and earns a background fetch by coming back.
- **It hears how you sound.** SenseVoice labels the emotion in your
  voice; the face softens before the reply arrives, and the model gets
  one hedged line about it.
- **A face that actually talks.** With `localkin-service-avatar`
  checked out, the companion can be a digital human whose mouth moves
  with the words — its inference is WASM in a web view, no GPU, driven
  by the same Kokoro bytes the speaker plays. With it on, the
  photographic background steps aside for a quiet dark ground: a
  green-screened figure over a picture of somebody's dog reads as a
  collage, not as someone in a room. Four characters. Off unless
  asked for.
- **An animal that looks back.** For photographs of pets there is no
  lip sync — a dog does not lip sync, and one that did would be a
  cartoon. macOS's animal pose model finds the eyes and ears, and the
  picture breathes, blinks irregularly, perks its ears at your voice,
  leans in to listen, and tilts its head when it is thinking. Photos
  where the pose is not found stay photos.
- **Approvals by voice.** The gate's questions and `ask_user` are read
  out and answered out loud — and also docked at the bottom of the
  picture as buttons, because a voice-only prompt is invisible if you
  stepped away. Only short affirmations approve: "把那个文件删了" is an
  instruction, not consent.
- **Background art** can be short mp4/mov loops, switched between
  themes (`~/.kinclaw/companion-<name>/`) from the face. Stills get a
  slow push-in and a breath that follows the microphone.

### Fixed — the voice loop could talk to itself

Two saved sessions ended with the agent answering its own previous
sentence. The chain: barge-in fired on the agent's own voice through
the speakers; the cancelled turn's cleanup then re-spoke the partial
reply through the non-streaming path into a microphone the barge-in had
just opened; that hot recording pre-marked itself as speech, so even a
false trigger reached the transcriber and came back as "Yeah."; and a
sentence still being synthesized when the reply was stopped played into
the next one. All four are closed, and the kernel's abort note now
tells the model to answer rather than recap.

### Changed — Cowork and Code say what they are allowed to do

- **The gate has a name and a switch**, in the composer's bottom-left:
  只看不动 / 先问我 / 放手干. Plan mode and the approval gate are the
  same question — how much rope — and were previously an unlabelled
  clipboard icon and a soul-file field you could not change while
  running.
- **Stop is the send button.** While a turn streams it turns red at the
  far right of the composer, where the hand that just pressed return
  already is. It used to be a 13pt icon in a row of eleven. ⌘. works
  with the composer empty.
- **The top bar keeps three things** — connection, search health, new
  session — plus a ⋯ menu holding what was competing with them. The
  context meter moved next to the model picker, the workspace next to
  the gate: what it may do, and where it does it.
- **Code caught up with Cowork**: the approval card (kincode no longer
  launches with `-yolo`), the build result it ran after an edit, an
  undo button beside the list of what changed, the same ⋯, the same
  send-becomes-stop.
- **The file tree is gone** from both side panels — IDE furniture in a
  window whose premise is that something else reads the files, and
  Finder does it better. What it also held is worth keeping and is not
  browsing: "what did it just change" now sits above the composer as
  one line that opens into the list.
- **The agent picker offers doors, not parts.** The kernel says which
  souls are meant to be opened; the five that exist to be dispatched
  (Eye, Critic, Researcher…) moved into a submenu. Picking one used to
  get you an agent that mysteriously could not do anything.

### Added — kinfer as a model source

- **A kinfer server is a source like any Ollama.** Give it its own port
  in Settings → Sidecars → Ollama host (`http://192.168.0.21:11590`), or
  let the brain menu's scan find it, and Cowork and Code both list its
  models and run on them: kinfer speaks Ollama's `/api/tags` and
  OpenAI's `/v1/chat/completions`, which is everything either kernel
  asks of a host. Its row says `kinfer` once probed — one box can run
  both, on two ports, with model lists that overlap.
- **The LAN scan looks for kinfer too**: Ollama's :11434, kinfer's
  default :11500, and any port a remembered host uses. One port at a
  time — three sweeps at once is close to the 256 open files an app
  gets, and a probe that fails for that reason reads as nobody there.
- **What actually stood in the way was in the kernels.** kinfer answers
  a streamed request that carries tools with one JSON body instead of
  SSE, and both kernels read that as a reply with nothing in it. Fixed
  in kinclaw and kincode.

### Added — the companion draws her own pictures

Her art has been stock until now: a Pexels search, somebody else's
photograph, and whatever it happens to show. A diffusion server answers
the other way round — you say what you want and it makes that, which is
the difference between a picture *of* a cafe and a picture of *her* in
one.

- **A generate row in the art picker.** Type what to draw, press 生成,
  and it lands in whichever group is selected — so a picture made under
  「开心」 is one she shows when she is happy, matched by mood and by the
  words in its own filename, exactly like a downloaded one.
- **`image_generate`, the eighth panel tool.** The agent can draw
  without being handed a picker: prompt, optional mood, size, steps,
  seed. It answers with where the file landed.
- **Somebody else's GPU.** It talks to OllamaDiffuser's REST API, so the
  server is wherever the memory is — the address is one field in the
  picker and defaults to the box (`192.168.0.21:8000`). Measured there
  with Boogu-Image-Turbo: **14–16s for a 768×768 at 4 steps**.
- **A server that fails mid-generation still answers 200**, with a small
  error image it drew itself. So the client checks that what came back
  is a real image of a plausible size, and says to read the server's log
  rather than writing a broken PNG into her folder.

### Added — the 3D face's mouth says what she is saying

The stage opened one shape, `aa`, in proportion to the audio's level: a
mouth flapping rather than a mouth speaking, identical on every sentence.
A VRM face has five, and Kokoro hands over the whole clip before it
plays, so the shapes are read off it once and played back alongside it.

Formant bands rather than phonemes — 350–700 Hz where an open vowel puts
its first formant, 800–1400 for a rounded one, 1900–3000 where a spread
vowel puts its second — and the band that stands out **against its own
average across the clip** picks the shape. That averaging is the whole
trick: speech carries far more energy low down, so comparing the bands
directly picks the low one nearly every time. On one 4.5s Kokoro line,
225 frames:

| | absolute | against its own average |
|---|---|---|
| `aa` | 55.6% | **28.0%** |
| `oh` | 4.0% | **12.0%** |
| `ee` | 1.3% | **12.0%** |
| `ou` | 3.6% | **8.4%** |
| `ih` | 4.0% | **8.0%** |
| closed | 31.6% | 31.6% |

The right column is a mouth that moves the way a mouth moves. A Goertzel
at three probe frequencies, not an FFT — three numbers are wanted, not
512 — and the Swift port was checked frame-for-frame against the
prototype on the same clip: same counts, same string of shapes.

The five morphs ease 0.35 of the way to their targets each frame, about
40ms to settle, which is roughly how fast a mouth moves between vowels;
slower reads as mush, faster as a puppet. Without a track the old
amplitude path still runs, so a face with no clip to read is no worse off
than before.

### Added — she lives in scenes, and the scene stays put while she talks

The flat mood folders answer "what fits this feeling", which is right for
photographs and wrong for a person: waiting in a kitchen and answering
from a night market is two different evenings. A scene holds both clips
in one place, so between them only her state changes.

    <art folder>/scenes/<name>/
        wait.mp4     she looks at you, smiling, waiting
        talk.mp4     she speaks — same place, same clothes
        still.png    the frame both were animated from
        about.txt    words the conversation might use for this place

- **She waits, she answers, she goes back to waiting** — all in one
  place. Eight scenes came out of one anchor: kitchen (the main one),
  beach, park, study, night market, sofa, bedroom, a bus stop in the
  rain, sixteen seamless loops in all.
- **The conversation moves her.** A reply's subject keyword against each
  scene's own words; two replies that name nowhere and she goes home to
  the main scene. Counted on the *transition* into speaking, not on
  every call — the art is chosen again for each sentence's mood, and
  counting those sent her home in the middle of answering.
- **A place she has never been gets made while she waits in the one she
  is in.** `wantScene` takes the subject, edits her anchor into that
  place, films a waiting clip and a talking clip, and the scene simply
  exists the next time the subject comes up — about three minutes. A
  companion who blanks out while a picture renders is worse than one who
  keeps talking to you in her kitchen.
- **`character_show` says where she is and where she can be**, because a
  companion who cannot answer "where are you" from her own tools will
  make something up.

### Fixed — a half-made digital human took the screen with it

- **A look needs both its files.** `AvatarStage` listed any folder with
  an `01.mp4`, which is what an interrupted preparation leaves behind —
  and the mouth data is what the runtime reads, so the companion went
  black and stayed there with her own pictures hidden behind the layer
  that had failed.
- **`RealLookMaker` had never once run to the end.** It handed the first
  preparation script `root/data`, which makes `root/data/data`, where
  the second script never looked. The ffmpeg check upstream of it had
  been failing for longer, so nobody had reached the bug.
- **Matting failure falls back instead of stopping.** It needs a torch
  and a torchvision that agree plus `rvm_resnet50.pth`; without them the
  first step dies on `torchvision::nms does not exist`, so it is tried
  and then retried without.
- **The four-hundred-key state-dict error is now one sentence.** DH_live's
  published weights are a year older than its code — the reference
  feature went from 6480 numbers to 80 at their 2.0 upgrade — so a look
  you build yourself cannot be read by the shipped runtime. A look may
  now carry its own `runtime/`, which is how the two generations sit
  side by side.
- **ffmpeg, found where it actually works.** A Homebrew ffmpeg can be
  installed and still not run: this Mac's came from a third-party tap,
  wants a libass that has moved on, and brew refuses to touch the tap at
  all, so neither reinstall nor upgrade fixes it. The avatar service's
  own venv gets a static build from `imageio-ffmpeg`, and that is looked
  at first.

### Added — she is one person, not a new one in every picture

A companion built out of text-to-image calls is a different woman each
time: the same prompt and the same seed drift the moment the scene
changes, and a four-step turbo model drifts hardest. So her identity
does not live in the prompt any more. It lives in one file.

- **An anchor portrait, and everything else is an edit of it.** Draw
  candidates from one description (~15s each, cheap enough to be picky),
  adopt one, and from then on "her in a kitchen" and "her in a red coat"
  are *instruction edits* of that picture. Identity comes from the input
  image, which is the only thing that actually holds it.
- **Three models, three jobs**, because a text-to-image model cannot
  edit at all — Boogu, Krea, ERNIE, Lens and Ideogram ship only a
  txt2img path in mflux. Measured end to end on the box: a turbo model
  draws her (**14s**), FLUX.2 klein 4B changes her scene or clothes
  while keeping her face (**10–22s**), LTX-2 films her (**83s** for four
  seconds). Three addresses in Settings, because OllamaDiffuser serves
  one model per process. FLUX.1-Kontext does the same editing job at
  181s from twice the download, which is why klein won.
- **A normalising pass when a candidate is adopted.** Without it the
  anchor is one model's rendering and every scene is another's, so her
  skin and the light change between pictures even though her face does
  not. The candidate goes through the editor once — "same woman, neutral
  background" — and *that* is the anchor. 20s.
- **Her scenes use a seed made from the instruction**, not a random one.
  The same request gives the same picture — "her in the kitchen" is a
  thing she has, not a dice roll — and big random seeds are where an
  editor was caught returning undenoised latents: FLUX.1-Kontext int8
  drew the portrait at seed 1234 and coloured static at 473366517, same
  weights and prompt.
- **A day, in two minutes.** 「长一天」 fills the mood folders with eight
  ordinary scenes; measured, eight edits took **130s**.
- **Clips are image-to-video**, from a scene picture rather than from
  words, so the person who moves is the person in the picture.
  `video_generate` takes an `image` path for this, and the clip lands in
  the same mood folder — where an mp4 is already a moving background.
- **「长一天」** fills the mood folders with eight ordinary scenes —
  morning kitchen, autumn park, rainy window, a bus stop in the rain —
  each filed under the mood it belongs to, so the companion's existing
  matcher shows the right one when the conversation turns that way.
- **Four more panel tools** (`character_show`, `character_new`,
  `character_adopt`, `character_scene`), so the agent can introduce her,
  dress her and film her without being handed a picker.
- **Her sheet and anchor live in the art folder** under a dot-prefixed
  name: the rotation skips it, and pointing the folder at an external
  disk takes her with it.

Real-time generation is not on the table and the design says so: 15s a
picture and ~20s per second of video. What works instead is a library
that grows in the background and a conversation that *picks* from it
instantly, with a generation queued only for something she has never
been asked for before.

### Added — and she films her own backgrounds

An mp4 in her art folder has been a moving background since the Pexels
work, so a generated clip needed no new plumbing to show up — only
somewhere to come from. LTX-2 on the box makes one with sound.

- **「拍 4 秒」 next to 生成**, same field, same folder. A clip made
  under 温柔 is what moves behind her when she is gentle.
- **`video_generate` and `video_status`**, tools nine and ten. Measured
  on the box with an LTX-2.3 int4 pack: **4 seconds of 704×448 in 83s,
  2 seconds in 37s** — about 18s of compute per second of video — with
  a 48 kHz stereo track the model generates jointly, not dubbed on.
- **Filming is a job, not a call.** The kernel gives one MCP round trip
  60 seconds and *closes the client* when it overruns, which would take
  every other panel tool down with it. So `video_generate` answers with
  the path the file will land in and leaves; `video_status` says what is
  still filming, what landed, and what failed. The picture path stays
  synchronous — 15s fits.
- **Its own address**, because OllamaDiffuser serves one model per
  process: pictures on `:8000`, video on `:8001`, both settable.
- **Her art folder was already settable to anywhere**, which for video
  means an external disk — and an external disk is the kind that is not
  plugged in on a Tuesday. Unasked, that looked like "she has no
  pictures" and like an unreadable write error. Settings names the drive
  to plug in, and both generators refuse with that sentence instead of
  an errno.

### Changed — clicking the icon summons the panel

⌥⌘K is still the way in, but an app whose only surface is a hotkey panel
should not be unreachable to someone who has forgotten the hotkey: the
Dock icon used to bounce and show nothing. `applicationShouldHandleReopen`
now shows the panel, which also makes `open -a KinClawMac` work.

### Changed — the real person is a wardrobe too, and the cartoon no longer stands in front of her

The 3D character shipped drawing over the digital human — both on meant a
cartoon in front of a person — and the person, who is the one anybody asked
for, had four looks hardcoded in a list.

- **One face or the other, enforced where it is stored.** Turning either on
  turns the other off in the setter, not at the call sites: there are two
  menus, two tools and a restore-on-launch path, and each of them would have
  had to remember.
- **Real-person looks are scanned, not listed.** The avatar service's four,
  plus any folder under `~/.kinclaw/avatars-real/` holding `01.mp4` and
  `combined_data.json.gz`. A look is a folder, so a new one needs no build —
  the same shape as the 3D wardrobe beside it.
- **「用一段视频做新形象…」** runs DH_live's two preparation scripts on a video
  you pick, with `--matting` so she is a figure rather than a rectangle of
  somebody's living room, and wears the result when it is done. No training:
  a minute of someone talking to a camera is the whole input. It checks ffmpeg
  first, because a broken one arrives as a Python traceback about SIGABRT —
  measured on this Mac, whose Homebrew ffmpeg had lost `libass.9.dylib`.
- **`avatar_wear` covers both wardrobes.** Real people first: a name that
  matches both far likelier means the person than the model. And the tools now
  say whether she is actually on screen rather than whether a server is up.

What a real person cannot do is change clothes by prompt: her clothes are in
the video. Another outfit is another video of her — a phone recording, stock
footage, or a generated clip — run through the same two scripts.

### Added — the companion has a body: a 3D character, and clothes she can change

Companion mode was a picture that changed with her mood. It can now be a VRM
character standing in the panel — the format Desktop Mate and Grok's Ani both
use underneath, which is the point: VRoid Hub publishes tens of thousands of
characters and outfits in it, so "change her clothes" is a file rather than a
modelling job.

- **A wardrobe, not a costume system.** Drop `.vrm` files in
  `~/.kinclaw/avatars/` and the 3D menu in companion mode lists them. A VRM
  carries its clothes baked in, so an outfit *is* a model — which is also how
  Desktop Mate's DLC costumes and VRoid Hub's paid outfits arrive. The app
  ships no character: they are somebody's work, licensed per model.
- **She reacts to the conversation already in place.** The `[情绪·主题]` tag
  that picks the art now also picks her face, mapped onto the five VRM standard
  expressions — happy, relaxed, surprised, sad — and the voice's own level
  opens her mouth while a reply is being spoken. Blink, breath and eyes that
  follow the pointer come from the stage itself.
- **Asking works.** Two more panel MCP tools, `avatar_outfits` and
  `avatar_wear`, so "换条裙子" reaches the wardrobe the way it reaches Ani's.
  Names match loosely; the answer says whether she is on screen to see it.
- **Local, like everything else.** three.js, its glTF loader and
  `@pixiv/three-vrm` are vendored in the bundle (2.3 MB) rather than fetched:
  a companion that needs a CDN is a companion that stops working on a plane.
  They are a folder reference in the project on purpose — Xcode flattens
  resources, and the glTF loader imports `../utils/BufferGeometryUtils.js`.
- **Measured**, on the stage page with a sample model: loads and renders,
  reports the eighteen expressions the model carries, `happy` closes her eyes
  into a smile and `mouth(0.9)` opens her mouth, and the scene sizes itself
  from its element — a host that reports an inner size of 0 (one preview does)
  used to leave the canvas blank.

Not yet: an idle animation. She stands in a relaxed pose the stage poses her
into, which beats the T-pose a VRM arrives in but is not Desktop Mate's sway.
VRM animation files (`.vrma`) are the next step, along with the transparent
always-on-top window that would put her on the desktop rather than in a panel.

### Added — the agent can open a page and read your terminal

The panel now offers the kernel five tools of its own, over MCP: `browser_open`,
`browser_read`, `browser_tabs`, `terminal_tabs`, `terminal_read`. Ask Pilot to
look something up and it opens the page in the Web tab — the browser you are
signed into, not a fetch from nowhere — and reads what rendered. Ask what went
wrong in the Term tab and it reads the screen, scrollback included.

How it is wired, and why that way:

- **The server is this app's own binary.** The kernel's MCP client speaks stdio
  to a process it spawned (kinclaw `pkg/mcp`), and the state these tools
  describe — live web views, running terminals — is inside an app it did not
  spawn. So `~/.localkin/mcp.json` gets a `panel` server whose command is
  `KinClawMac --mcp-stdio`: the same binary, started by the kernel, doing
  nothing but carrying JSON-RPC lines to the running app over loopback. Same
  binary because it is then always exactly as new as the app it talks to.
- **Loopback, and a token.** Any process on this Mac can reach a loopback port,
  and "open a URL in the user's signed-in browser" is not a thing to leave
  open. The port and a per-launch token live in `~/.localkin/panel.json`, mode
  0600; a request without the token gets a 403. Measured: refused from another
  machine on the LAN, 403 on loopback without the token.
- **Read mostly.** The agent can open a page, read a page, and read a terminal.
  It cannot type into your shell. `mcp_*` skills ask before running, by the
  kernel's own default, so the first call raises an approval card in the panel.
- **It reads what you see.** `terminal_read` counts its lines back from the last
  line with something on it, not from the bottom of the screen — the first
  version did the latter and reported an empty terminal for a terminal with a
  prompt in it. Measured against a flooded shell: `lines: 5` returns lines
  196–200 of 200, `lines: 120` starts at 81, from the scrollback.

### Added — a Web tab: a browser in the panel, and the page handed to the agent

The two panes beside Claude Desktop's conversation, as far as they make sense
here: a browser, and your own shell in the Term tab.

- **Tabs, an address bar, back and forward.** Pages live in
  `WKWebsiteDataStore.default()`, so a sign-in lasts across launches, and the
  web views are held outside the view tree the way the terminals are — a tab
  survives a trip through Cowork and back with its scroll position and its
  half-filled form. A link asking for a window of its own gets a tab of its
  own. A typed word that is not an address goes to the kernel's own
  `SEARXNG_ENDPOINT`, so the browser searches the index `web_search` searches;
  DuckDuckGo when there is none.
- **给 agent 看这页** hands the page over: the text this browser rendered —
  after the JavaScript, behind the sign-in — written to a file under
  `~/Library/Caches/kinclaw/pages/` and attached to the chat, with the URL on
  a line of its own for a soul that would rather fetch it with kinbrowser. The
  panel switches to Cowork for it, where the agent can read a path; Chat keeps
  Chat, where it cannot.
- Not a replacement for Safari: no downloads, no extensions, no bookmarks, and
  nothing here drives the browser but you. The agent reads what you send it.

### Added — your own shell in the Term tab

The Term tab ran agents; the terminal button in its tab strip now opens a tab
running your login shell — `zsh -l -i`, in the folder that tab is pointed at,
no host and no model. Half of what a terminal beside the conversation is for
is the command you would otherwise have gone to another window to run.

An agent tab still needs a model picked and still says so; a shell tab has no
machine or model menu, because it talks to neither. And "no agent installed" is
no longer the Term tab's empty state: the shell is always here.

### Changed — the panel is an ordinary window, not always on top

The panel floated above every app, which suited a quick question and not a
Term tab running an agent for an hour beside the editor it works on. It is a
normal-level window now: it comes to the front when summoned or clicked, and
other windows go over it when they are. Settings, which had to float with the
panel or open behind it, is normal-level too.

- **⌥⌘K and the 🦞 item hide a panel you can see and bring forward one you
  can't** — hidden, or on screen under another window. Hiding a panel the user
  pressed the hotkey to find would take two presses to get it back. Whether
  it is covered is read from the window server's stacking order, not from
  key status, which clicking the menubar item can take away from a panel
  that is plainly in front.
- **A click raises it.** The panel still never activates the app — the
  agent's keystrokes must not land in it while it drives another app — and a
  window that does not activate is not raised by activation, so the click
  raises it explicitly.
- Still on every Space and beside full-screen apps, as before.

### Added — a Term tab: another agent, on the model you picked

`ollama launch claude` works because Ollama serves three dialects, not
because the launcher is clever: Anthropic's Messages API is there at
/v1/messages (measured on 0.34.0 and 0.34.1 — a real `message_start` /
`content_block_delta` stream, `thinking` blocks included), so aiming
Claude Code at it is two environment variables and nothing else.

So the panel has a fourth pill: **Term**. It runs the agent in a real
terminal — SwiftTerm's PTY view — with `ANTHROPIC_BASE_URL` pointed at
the host picked in 「模型来自哪台机器」 (this Mac, or the box on the LAN),
the model the menu is showing, and the folder Code is pointed at as the
working directory. Both model menus carry a row that opens it there:
在 Term 里用这个模型开 Claude Code. Measured end to end: `claude --model
kimi-k2.6:cloud` through this Mac's Ollama answered in 3.9s. Aiming it
at the LAN box is the part `ollama launch` cannot do — it only ever
knows the Ollama on the machine it runs on.

The tab keeps its own machine and model, both picked in its own header —
this Mac, any remembered box, or whatever a LAN scan turns up — because a
session started against the box on the LAN should not move when Cowork
switches its brain back to this Mac. Changing machine carries the model
over when the new host has it, falls back to the same family when it does
not (ornith-1.5:35b → ornith-1.5:9b), and otherwise says so and waits,
rather than handing the agent a model name that host never heard of.

**Codex is in too**, and it took a different shape: its endpoint goes in
as config overrides on the command line (`-c model_provider=…`), not as
environment, because rewriting somebody's ~/.codex/config.toml would need
an undo. Three things the attempt taught, all of them only findable by
trying (0.154.0): `wire_api = "chat"` is refused outright now ("set
wire_api = \"responses\""); Ollama does serve /v1/responses, so that is
fine (measured — 200, proper Responses body); and the built-in `ollama`
provider will not take a base_url override ("Built-in providers cannot be
overridden"), so the tab declares a provider of its own — which is also
what lets Codex talk to the box on the LAN instead of only this Mac.
Measured end to end: this Mac + kimi-k2.6:cloud, 2.8s; the LAN box +
qwen4exp-local, 74s for its ~9K-token opening prompt (a 4K-context model
cannot run Codex at all).

Whether a machine can serve an agent is asked of the machine, not assumed
from what it is: kinfer learned /v1/messages and /v1/responses in 86ba172,
and a box can be running a build from before that. A POST naming a model
that cannot exist gets a JSON error back from a route that exists and the
router's plain-text 404 from one that does not — the status is 404 either
way, so the body type is the answer — and the header says "没有
/v1/responses，Codex 用不了这台 —— 更新那台的 kinfer" before the terminal
has to find out.

The agent picker appears in the header as soon as more than one agent is
installed; with one, it stays a label.

The folder is the tab's own too, picked in the same header: its recent
folders and Code's recent repos, a folder picker, "follow Code's repo", and
"show in Finder". Changing it restarts the agent — a working directory is
fixed when a process starts, and an agent still running in the old folder
under a header naming the new one is worse than a restart. Opened from
Code's model menu, the agent starts in Code's repo.

**Tabs.** Several agents at once, each with its own agent, machine, model
and folder; + opens one set up like the tab you are on. The terminals
belong to a session object rather than to the view tree, which also fixes
what the single tab got wrong: leaving Term ended the agent, because
SwiftUI tears a view down when it leaves the hierarchy. Now only closing a
tab does. Tabs are remembered across launches and start their agent the
first time they are shown, so a restored set does not launch every agent
at once. A model menu opens the tab already set up that way, or a new one
— never by replacing the agent you were talking to.

A terminal rather than our own transcript with our own cards, because
these are interactive TUIs: their own approval prompts, their own
scrollback, their own ^C. `claude -p --output-format stream-json` has no
approval callback to hang cards on, so a pane that swallowed the agent
would be strictly worse than the real thing. The tab keeps a
「在外部终端打开」 button for the one thing the embedded version cannot
do: the child is spawned by this app, so a permission prompt it triggers
is attributed to KinClawMac.

The agent runs under your login shell, interactive. A GUI app inherits
launchd's PATH — /usr/bin:/bin:/usr/sbin:/sbin — and the first thing this
tab ever printed was `env: node: No such file or directory`: the agent
itself was found by absolute path, but the MCP servers and hooks *it*
starts were not. `zsh -l -c` would not have fixed it either, because this
Mac keeps PATH and nvm in .zshrc, which a non-interactive login shell
never reads. Measured: `env node` fails under launchd's PATH, resolves to
/opt/homebrew/bin/node under `zsh -l -i -c`.

Not in yet: agents that want somebody else's config file rewritten
(Codex's `model_providers`, Cline's VS Code settings) — a different
promise from exporting a variable, and it needs an undo.

SwiftTerm is pinned to 1.10.1, the last release that builds with nothing
extra installed: 1.12+ carries a Metal shader that Xcode 26 compiles
only after a multi-gigabyte `xcodebuild -downloadComponent
MetalToolchain`, and 1.19+ adds a build-tool plugin that a command-line
build refuses to run untrusted.

### Fixed — `make build` said "✓ Built" when the build had failed

The recipe piped xcodebuild through `grep` and ended in `|| true`, so the
exit code was grep's. A FAILED build printed the tick and `make run`
happily launched the previous binary — found by wondering why a new tab
had not appeared. Full output now lands in `/tmp/xcodebuild.log`, the
filtered summary still prints, and the status is xcodebuild's own.

### Fixed — the app could crash within a second of launch

`OllamaCatalog.probeAll()` probes every remembered host at once, and each
probe wrote the shared health cache from whatever thread its task finished
on. Two writes landing together corrupted the dictionary: two crash reports
on 2026-09-16, at 08:55 and 16:44, 0.3 and 0.4s after launch, both at that
write — once as a bad pointer inside the dictionary's storage, once as a
message sent to something that was no longer what it had been. The cache
is behind a lock now. It came in with the LAN health probes on 2026-09-12.

### Streaming speech and barge-in (2026-09-07)

### Added — you can interrupt it

The mic stays open while the agent talks, and speaking cuts it off. The
naive version of this hears the speakers and interrupts the agent with
its own voice, so `BargeInMonitor` runs the input through
`AVAudioEngine` with voice processing enabled — macOS's acoustic echo
canceller subtracts what is playing from what is heard, and what
remains is the room. A trigger still needs speech both above a measured
noise floor and sustained for ~140ms, so a keyboard clack or a closing
door does not stop the reply.

Interrupting also cancels the turn when the model is still writing. Not
only because you are redirecting it: the listener that reopens the mic
refuses while a turn is in flight, so without that the interruption
would silence the agent and then leave the mic shut.

Armed off `isSpeaking` rather than at each call site, so streamed
replies, whole replies and the system-voice fallback are covered by one
rule. Hands-free surfaces only — with push-to-talk the mic is yours to
open, and cutting a reply off because someone spoke nearby would be
worse than waiting.

### Fixed — companion mode could open with no agent to talk to

Reached from the menubar, or from the Code tab which has no agent
picker, companion mode opened on a character whose only message was
"pick an agent first" — inside a view with no way to pick one. It now
selects the Cowork default (Pilot) and switches the panel to match.

## [Unreleased] - 2026-09-07 (evening) — Streaming speech

### Changed — it starts talking while the model is still writing

The reply was spoken only after the whole turn finished: the model
streamed tokens for several seconds, the speaker sat silent, and then
synthesis and playback started from zero. That wait is most of the gap
between this and a realtime voice assistant, and none of it was the TTS
model being slow — Kokoro renders 6.75s of Chinese in 1.0s.

Each sentence is now handed to the speaker as it completes, so the
first words land about a second after the model starts writing.
`SpeechSynthesizer` gains `beginStream` / `stream` / `endStream` around
the play queue it already had; synthesis is serialized rather than
parallel, because one worker at 6x realtime stays ahead of playback and
serial order is the order the sentences are spoken in.

Sentence boundaries are CJK and Latin terminal punctuation or a
newline. A Latin period needs whitespace after it, so "3.5" and
"kinclaw.dev" are not cut in half; a run with no punctuation at all is
released at a comma, or after 160 characters, because the alternative
is silence until the model happens to write a period.

Both transports stream: Cowork's `text_delta` events and the Chat tab's
cloud tokens. A reply that arrives in one piece, or whose text came
only from tools, still gets spoken whole.

Fenced code is held back until the fence closes, then dropped. Cleaning
happens per chunk now, and a block opened in one sentence and closed
three later would otherwise have neither marker in view — the contents
would be read out, brackets and semicolons included.

## [Unreleased] - 2026-09-07 (later) — Companion mode

### Added — ⇧⌘M: a picture and a voice

The panel becomes a character and a halo. No transcript, no buttons, no
typing: you speak, it listens, it answers out loud, and the ring around
the middle says which of those is happening — breathing when idle,
tracking your voice while the mic is open, spinning while it thinks,
pulsing while it talks. The last reply shows small underneath, for when
the room was too loud to catch it. Esc leaves and the window returns to
exactly the size and place it had.

Voice was already built (VoiceRecorder, SpeechSynthesizer, WakeWord,
the kernel's /api/voice/*); this is a presentation of it, so entering
turns the voice loop on rather than leaving the user to find a mic
button in a view that has none.

### Fixed — companion mode was waiting for a wake word it never mentioned

With a wake word set (`小美` here), hands-free mode discards anything
that does not contain it. Companion mode turned hands-free on and said
"说话就好", so speaking did nothing and the halo just sat there
breathing. The word exists so background chatter cannot trigger the
agent while you are doing something else; deliberately turning the
panel into a face and talking to it is not that case, so companion mode
now bypasses it entirely — entering is the wake.

The state label also stops lying: a denied microphone, no selected
agent, or voice being off is printed under the halo in orange instead
of "说话就好". A view with no other controls cannot afford a silent
failure.

Removed the "Voice-mode auto-continue" toggle from Settings: it was
wired to nothing, and the behaviour it named already happens
unconditionally.

### Added — art that fetches itself

Pictures live in `~/.kinclaw/companion/` (or a folder you pick in
Settings → Backend → Companion mode). Drop anything in and it is used.
Name files `idle`, `listening`, `thinking` or `speaking` and each state
gets its own; everything else rotates.

"Go get a few" searches for backgrounds without leaving the app:
**Wikimedia Commons** by default, which needs no account, so this works
on a machine that has never been configured; a free key from
pexels.com/api in Settings swaps in a better-looking source with no
attribution requirement. Results come back as a grid, one click keeps
one, the credit line is written next to the file, and anything under
900px wide is rejected because a thumbnail stretched to fill a window
looks like a smear.

## [Unreleased] - 2026-09-07 — Cowork: folders with their sessions

The same shape as Code's sidebar, one day later, for the tab where the
folder is the workspace rather than a repo.

Cowork sessions are stored per agent, so grouping by folder needed the
folder recorded on the session: `ChatSession` gains an optional
`workspace`, written on every save from now on. The left pane lists the
folders Pilot has worked in, each expanding to its conversations
(title, relative time, and the agent when it differs from the one you
are talking to). Clicking one restores the folder, the agent and the
transcript together, and resets the kernel's own history so the model
is not answering from a conversation you just navigated away from.
Each folder gets a **New session** row; right-click a folder to work
there, start a session or reveal it, and a session to open or delete it.

Conversations saved before the workspace field group under **No
folder** — they are still yours, they just predate the folder. That
group is filtered to the local KinClaw souls, since Chat-tab
conversations with cloud agents did not happen in a folder at all, and
every group shows its newest 15 with the rest one click away.

The active folder's files stay below in the collapsible **Files**
section.

## [Unreleased] - 2026-09-06 — Code: folders with their sessions

### Added — the Code sidebar lists folders, and sessions under them

Code has always stored conversations per repo — one directory per repo,
many session files inside — but the UI only ever resumed the newest one,
so every earlier conversation about a folder was on disk and unreachable.
On this machine that was 21 sessions across three repos, including a
142-message one about kinclaw.

The left pane now lists every folder you have worked in (those with
stored sessions, plus ones you picked but have not talked to yet).
Expanding a folder shows its conversations, titled by their first
message with a relative timestamp, newest first; clicking one opens it,
switching folders if needed. Each folder has its own **New session**
row, so starting fresh somewhere else is one click and does not disturb
the conversation you were in. Right-click a folder to open, start a
session, reveal in Finder, or drop it from the list (sessions on disk
are kept — removing a folder from a list should not delete work).
Right-click a session to delete it.

The active folder's files stay below in a collapsible **Files** section,
the same tree Cowork shows, with the files touched in this conversation
marked.

The recents cap went from 5 to 20: it was a dropdown of shortcuts, and
it is now the list of everywhere you work.

## [Unreleased] - 2026-09-05 (night) — folded tool calls, folder pane

### Changed — long tool-call runs fold into one row

A turn with three or more tool calls now shows a single "Ran N tools ›"
row (Claude Desktop's "Ran 6 commands ›") instead of a wall of cards;
click to expand. While the turn streams, the header reads "N tools ·
web_fetch running…" and the call in flight stays visible underneath, so
you still see what the agent is doing right now. A failure count shows
in red. Same fold in the Code tab for consecutive kincode tool rows.
`todo_write` stays outside the fold, and only the latest checklist
renders — each call replaces the whole list, so older ones were stale.

### Changed — composer footer, cards bottom-left

The model picker moved out of the top bar into the composer's
bottom-right corner next to Send, in both Cowork and Code — the top bar
is about who (agent / repo) and where (workspace); the composer footer
is about what brain. Approval and question cards now sit bottom-left,
capped at 480pt, so they read as a prompt attached to the composer
rather than a banner across the panel.

### Added — source switch and search-engine health

Both brain menus open with a **Source** section: This Mac, and every
LAN Ollama you have used, one click to flip. The model list reloads
from the new host and the running brain is re-pointed at it when the
same model exists there; the composer badge shows `local` or the host.
The Cowork bar gains a magnifier with a status dot: click for what the
last `web_search` actually got — backend, engines that answered,
engines that were CAPTCHA'd or rate-limited and why — plus **Probe
now**, one search restricted to the major engines, never on a timer.
The kernel now also prefixes weak results with a note naming the down
engines so the model stops treating wiby's output as an answer.

### Added — Ollama host setting

Settings → Backend → Sidecars gains **Ollama host**. Both brain
dropdowns (Cowork and Code) list models from it and Ollama brain
switches carry it as the endpoint — kinclaw takes the base URL, kincode
the full chat-completions URL, the setting handles both. Empty means
this Mac; a LAN inference box looks like `http://192.168.0.21:11434`.
The kincode supervisor passes `-endpoint` too when it spawns with a
saved default brain.

### Added — folder pane (Cowork and Code)

A left column in both Cowork and Code, on by default, ⇧⌘L to hide: the
workspace (or repo) folder at the top (click to change), **This session** — every file the agent read,
wrote or edited, newest first, with an eye / plus / pencil marker —
and **Files**, the folder's contents as an expandable tree with touched
files highlighted. Click reveals in Finder; right-click opens or copies
the path. Reloads after every turn.

## [Unreleased] - 2026-09-05 (evening) — workspace, questions, diffs, notifications, Routines

Second pass, pairing with kinclaw's deferred skills / workspace /
ask_user / routines. Same rule as the morning: all of it degrades to
nothing on an older kernel.

### Added — workspace picker

A folder button in the Cowork agent bar (next to the context meter)
shows the current working folder and opens a picker; the choice goes to
`POST /api/workspace`. The agent's relative paths and shell commands
live there, and writes outside it now ask first — Cowork's "the folder
you granted".

### Added — question card

When the agent calls `ask_user` (`question` SSE), a cyan card above the
composer shows the question with its options as chips — one click
answers — plus a text field for anything else (⌘⏎). Answered via
`POST /api/answer`.

### Added — diffs for file edits

`file_edit` / `file_write` tool cards render the kernel's unified diff
with the same DiffView the Code tab uses for kincode, and open expanded:
the diff is the information.

### Added — notifications

When the panel is hidden and the agent finishes a turn, needs an
approval, has a question, or a detached spawn returns, a macOS
notification says so; clicking it summons the panel. Asked for
permission once at launch.

### Added — "Always" on the approval card

Four answers now: Deny · This session · Always · Allow. Always saves a
narrow rule (`shell(git*)`) to `~/.kinclaw/permissions.json` so it
survives restarts.

### Added — Settings → Routines

Scheduled runs over the kernel's `/api/routines`: list with schedule,
last run, enabled toggle, Run now, log tail, remove; an add form with
Every day / Weekdays / Weekly / Every hour / Every N minutes presets.
Same registry as `kinclaw routine`.

## [Unreleased] - 2026-09-05 — Cowork gets Claude Desktop's manners

Pairs with kinclaw v1.18 (permission gate, plan mode, compaction, usage
events). Everything here degrades gracefully on an older kernel: the
events simply never arrive and the new controls stay idle.

### Added — approval card

When the kernel's permission gate stops a call (`permission_request`
SSE), an orange card appears above the composer: what Pilot wants to
run in one monospace line, why the gate stopped it, an expandable
params view, and three answers — **Deny** (Esc), **Always this
session**, **Allow** (⌘⏎). The turn is parked on the kernel until you
answer; Stop cancels the wait and the card. This is the Cowork
equivalent of Claude Desktop's "Allow this tool?" sheet, inline so your
eyes stay on the conversation.

### Added — plan mode for Cowork

A clipboard button in the agent bar (⇧⌘P) flips the kernel's read-only
gate — the same `POST /api/plan_mode` the Code tab already used for
kincode. While on, an amber banner explains that the agent investigates
and proposes but nothing on your screen changes, with an **Act** button
to leave. State reconciles from `plan_mode` events and `GET /api/state`.

### Added — context meter

A small capsule + percentage next to the connection dot, fed by the
kernel's per-call `usage` events: how full the model's window is. Green
→ yellow → orange past the compaction threshold, so an automatic fold is
never a surprise. Primed from `GET /api/state` on entering Cowork and
refreshed after every turn.

### Added — compaction dividers

When the kernel folds older conversation into a summary (`compacted`
event) a centered dim divider marks the spot in the transcript. System
markers render as dividers, not as bubbles from either party.

### Changed — kernel notices no longer end the turn

kinclaw ≥ 1.18 sends circuit-breaker trips, hook blocks and permission
denials as `notice` events instead of `error`. The Cowork stream loop
stops on `error` (correctly — the turn is over), which meant a mid-turn
`[SYSTEM]` warning used to truncate the rest of the turn in the UI.
Notices now render as a quiet ⚠︎ blockquote inside the bubble and the
turn plays on.

### API client

`KinClawAPIClient` gains `respondPermission(id:decision:)`,
`compact()`, `fetchKinClawState()`; `KinClawEvent` gains `reason`,
`context_length`, `before_tokens`, `after_tokens` and the kinds
`permissionRequest`, `permissionResolved`, `usage`, `compacted`,
`notice`.

## [Unreleased] - 2026-08-26 — Settings gains MCP, Harvest and Skills

Three new tabs, all built on one principle: show configuration **and** what
actually happened to it. A settings screen that reads only config files can
display a server which has been failing to start for a week and look perfectly
healthy doing it — which is precisely the failure mode these exist to expose.

### Added — MCP tab

Manage Model Context Protocol servers: add, remove, enable/disable, and see
each one's live state pulled from the kernel's `GET /api/mcp`. A failed server
shows its error inline plus a button to open its own stderr log, which is
usually where the real reason is ("missing API key", "package not found").

Editing writes `~/.localkin/mcp.json` in the ecosystem-standard `mcpServers`
format, so configs move freely between this app, Claude Desktop and kincode.
Arguments are entered one per line rather than space-separated — MCP arguments
are usually paths, and paths contain spaces.

Changes take effect on the next kernel restart, and the UI says so in an amber
banner rather than pretending to be live: MCP servers are launched at kernel
start, and a screen that looked live would be lying.

### Added — Harvest tab

The nightly skill-harvest job, made visible. Sources with what each has staged,
candidates awaiting review with the curator's reasoning, and an **Accept**
button that forges one into `skills/` — asynchronous, since the coder agent
takes up to four minutes, with all four outcomes reported honestly (`forged`,
`filed under library/`, `duplicate`, `failed`) rather than collapsed into a
checkmark.

Two things it deliberately surfaces:

- **The schedule's actual arguments**, not just whether it is loaded. A
  `--no-judge` entry looks perfectly healthy in `launchctl list` while doing
  only half the job — that is how a stalled harvest went unnoticed for three
  months. The tab flags it explicitly.
- **Sources producing nothing.** Three of six have staged zero candidates,
  usually because the library is written as prompt templates rather than
  command wrappers — a shape mismatch that re-scanning will never resolve,
  while still costing a clone and a scan every night.

### Added — Skills tab

What the active soul can actually use, out of everything the kernel loaded.
Two numbers, deliberately not merged: for pilot it is **25 exposed / 189
loaded**. Every "the skill is installed but my agent says it can't do that"
question is that gap, and it was previously visible only as one line of startup
output in a terminal nobody watches.

Ticking a skill grants it to the active soul **without editing the soul file**
— it goes to `~/.localkin/skill_extras.json` and takes effect immediately, no
restart. Souls are hand-authored (pilot's enable list is interleaved with
comments explaining each entry) and a checkbox that machine-rewrote that file
would eventually mangle the reasoning to save one text edit.

Soul-granted skills show a fixed checkmark instead of a toggle: the overlay is
additive only. Removing one stays an edit to the soul, where git can see it —
an overlay that subtracted would leave a soul file no longer describing the
running agent.

The tab also flags enable entries matching nothing loaded. Pilot currently has
one (`kinthink`) — the soul claims a capability the agent silently lacks.

### Changed — Settings window

Resized from 620×460 to 820×620 (resizable to 1100×900). The old size was set
when Voice was the busiest tab; MCP and Harvest rows carry a command line, a
status and an error message, which wrapped into unreadable stacks.

### Fixed — Settings opened behind the spotlight panel

`SpotlightWindow` sets `.floating` while Settings used the default `.normal`
level, so it opened *underneath* — indistinguishable from not opening at all.
Both now float; the most recently activated one wins.

---

## [Unreleased] - 2026-07-30 — Hands-free voice conversation

Voice mode was already wired into the UI — a mic button, a waveform, a TTS
toggle — and it produced audio every time you used it. It just never worked,
in three separate ways that each looked like success from the outside.

### Fixed — Chinese replies were spoken as "Chinese letter, Chinese letter…"

Local Kokoro (`/synthesize`) reads `speaker` + `language`. The cloud gateway
(`/v1/tts`) reads `voice` + `speed`. We sent the gateway's shape to both. Kokoro
never saw a speaker, fell back to an English default, and that voice pronounces
Chinese by *naming each glyph*.

Nothing surfaced the mistake: HTTP 200, a valid WAV, audio plays. Confirmed by
sending the output back through SenseVoice — the old payload transcribed as the
recital, the new one as 「施舍是信仰的试金石」, at a third of the bytes because
it stopped narrating every character.

### Fixed — recording kept running long after you stopped talking

The symptom looked like slow transcription. It wasn't; the VAD simply never
fired, so every utterance ran to the 15-second safety timer.

Measured instead of guessed, which mattered — the first hypothesis (room noise
sitting permanently above the threshold) was wrong. Room tone here averages
**-40.5 dBFS**, comfortably under the hardcoded -35 line. But it *peaks* at
**-32.0**, and any tick above the line reset the silence counter to zero. The
average stayed quiet while stray peaks crossed every few ticks, wiping the
count before it could reach the 0.5s stop. That also explains why it felt
intermittent rather than consistently stuck.

Two changes, since either alone is fragile:

- The noise floor is now measured per-recording — median of the first 0.5s, so
  one early cough can't skew the whole session.
- The counter decays (`-2`) instead of resetting, so a single keystroke can't
  undo half a second of accumulated silence.

Replaying recorded audio through both versions: the old logic **never stopped**
in three of four noise profiles; the new one stops at 0.5s in all four,
including a dead-silent room (no regression where the old code did work).

### Fixed — the "Silence threshold" slider did nothing

Settings → Voice wrote to `kinclaw.voice.silenceThresholdDB`. No code read it.
The detector had -35 compiled in, so the slider had never had any effect since
it shipped. It now sets the margin above the *measured* room noise — the knob
that actually helps when the default doesn't suit your room.

### Fixed — silence was being transcribed, and came back as words

Saying nothing produced messages. The recorder sent **every** recording to STT,
including the ones that stopped precisely *because* nobody had spoken —
`hasSpeechStarted` already knew the answer and it was being discarded.

Speech models don't return empty for empty input; they return their most likely
utterance. Feeding this build two seconds of digital silence:

    silence.wav  → SenseVoice returned  「그.」
    roomtone.wav → SenseVoice returned  「그.」

An invented Korean syllable, from a model being used for Chinese and English.
Which is the point: hallucinated output is unpredictable across languages, so a
list of known bad phrases cannot be the fix. Empty rooms were holding
conversations with the agent, and in hands-free mode that loops — the mic
reopens after every reply.

Two changes:

- Recordings where no speech was detected are dropped instead of transcribed.
- `hasSpeechStarted` now needs **3 consecutive ticks** (300ms) above the
  threshold rather than a single one. One spike — a cough, a door, a key — used
  to mark an otherwise-silent recording as worth transcribing.

Simulated against measured room tone: quiet room, a one-frame cough, and a
two-frame door all stay out of STT; a real utterance still goes through.

A short list of known hallucination phrases ("thanks for watching", "谢谢观看",
bare "I") is kept as a backstop for audio that crosses the threshold without
being speech. It is exact-match and deliberately small — "ok" and "嗯" are
excluded despite being common hallucinations, because they're also common
replies, and silently dropping something the user said looks like a broken mic,
which is worse than letting one stray "I." through.

### Added — mixed-language replies get the right voice per language

Kokoro voices are single-language: `zf_xiaoxiao` reading English produces
mangled phonetics, `af_bella` reading Chinese produces the glyph recital above.
Most real replies mix both, since technical terms stay in English.

Replies are now split into language runs, each synthesized by a matching voice
and played back to back. This is a **port of localkin's `pkg/tts/split.go`**,
not a reimplementation — that version is already in production behind
`kin_speak` and carries fixes worth inheriting (neutral punctuation attaching
to the following run; one- and two-letter English labels like multiple-choice
"A"/"B" folded into the surrounding voice instead of voiced alone).

Two refinements on top, both cost-only and verified not to change pronunciation:
punctuation-only runs fold into the preceding segment (CJK punctuation carries a
`zh` tag, so a lone `。` between two English runs would otherwise cost a whole
HTTP round-trip), and the resulting same-voice neighbours merge.

Markdown and emoji are now stripped on **both** output paths. The system-voice
fallback previously handled four markers and let emoji through to be announced
by name ("sparkles", "check mark").

### Added — optional wake word for hands-free mode

Hands-free mode sent everything it heard, including a phone call in the same
room or the recogniser's best guess at an air conditioner. A wake word turns
"always listening" into "always listening, rarely acting".

Empty and **off by default** — a wake word the user hasn't been told about is
indistinguishable from voice mode being broken.

**The wake word opens a conversation; it doesn't guard every sentence.** Say it
once and the session is open: what follows goes straight through, no name
needed, for as long as the exchange keeps going. After a configurable quiet
period (default 45s) the session lapses and the word is required again. Gating
every single utterance would mean a five-turn conversation needs the name five
times, which is not what "hands-free" should feel like.

The lapse timer counts from when the **reply finishes**, not from when the user
stopped speaking. A two-minute answer would otherwise expire the session while
the user was still listening to it, and they would have to say the wake word to
respond to what they had just heard.

Matching folds away case, spacing, and punctuation. STT output for a short name
is unstable (「小美」comes back as 小眉, 小mei, with or without a trailing
comma), and exact comparison would have the user repeating themselves while a
correct match sits one punctuation mark away — a worse failure than the rare
false accept it prevents. The word must lead the utterance, so discussing the
agent mid-sentence doesn't trigger it. Push-to-talk is exempt: pressing the
button is already the deliberate act a wake word exists to require.

Waiting-for-wake and conversing are drawn differently (amber vs red mic, with
the help text naming the word). Both states have the microphone open and only
one of them acts on what it hears; without the distinction the user speaks a
full sentence into what looks like a live mic and gets nothing back.

---

## [Unreleased] - 2026-05-12 — Studio tab (open-core private-soul hosting)

Adds a 4th main tab (`Studio`) for self-hosted private workflows.
KinClaw Mac is Apache 2.0 — the tab framework + UI shell ship in this
public repo. The *souls* the tab lists live in a sibling private repo
(family-private `localkin` checkout, optional) and never enter this
codebase. This is the open-core pattern at solo-founder scale: VS Code
ships the editor, extensions are user-owned; KinClaw Mac ships the
4-tab shell, Studio's contents are user-owned.

### Added

- **`Services/PrivateSoulLoader.swift`** — runtime sibling-repo
  discovery. Mirrors the Makefile's `LOCALKIN_REPO` search order
  (`../localkin`, `$HOME/Documents/Workspace/localkin`, `$HOME/code/localkin`,
  `$HOME/dev/localkin`, `$HOME/src/localkin`). First hit with both
  `.git/` and `souls/private/` wins. Enumerates `*.soul.md` and parses
  just enough YAML frontmatter (`name`, `version`, `description`) for
  the card view — no Yams dependency added.
- **`Views/Studio/StudioView.swift`** — the tab body. Two states:
  - Empty (no sibling repo or no private souls): explains the
    self-hosted contract + lists the 4 candidate paths the loader
    checks. Public clones land here.
  - Populated (sibling found, souls listed): scroll view of
    `PrivateSoulCard`s with name + version + description + mtime +
    Reveal-in-Finder. Run button is wired but disabled in Phase 1
    (spawn integration lands in Phase 2).
- **`LocalKinApp.swift`** — 4th `.tabItem("Studio", "lock.shield")`
  between KinBook and Settings, tinted `AccentGreen` like the others.

### Design notes

- **Why a tab, not a toggle**: Studio's contents are first-class
  workflows (cron-driven, multi-phase pipelines), not a setting.
  Putting it inside Settings or behind a hidden feature flag would
  pretend it's experimental — it's not, it's the *production-tool*
  surface for power users who maintain their own soul library.
- **Why empty state has documentation, not a marketing pitch**: the
  tab is for users with their own private workflows. The empty state
  IS the docs for how to populate it — not a "buy a license to unlock"
  paywall. Anyone can populate it locally; there's nothing to unlock.
- **Why Phase 1 disables the Run button**: shipping a half-wired Run
  that crashes when clicked is worse than shipping it dimmed with a
  clear "Phase 2" tooltip. The full spawn-into-supervised-kinclaw
  wiring (with tail-log + retry + state machine) is its own commit.

### Phase 2 (next)

- Wire the Run button → spawn `kinclaw -soul <path>` via
  `KinClawSupervisor`, surface stdout in a per-soul tail-log panel.
- Per-soul state badge (last run time, success/fail, phase state for
  multi-phase pipelines that write a `.state` file).
- Optional: per-soul custom UI panel (declared via a `ui.json` next
  to the soul file — soul declares "I need a queue.md editor" or "I
  need a progress chart" and the Studio renders it).

## [0.4.1] - 2026-05-06

**Patch — spawn_done bubble was being dropped silently.**

`UI/SpotlightContentView.swift::handleLocalEvent` had a stale-index
guard at the top that early-returned whenever `assistantIndex` no
longer pointed at a valid `messages` row. The guard was correct for
mid-turn events (`text_delta`, `tool_call`) — those need an active
assistant bubble to write deltas into.

But `spawn_done` arrives 3-5 minutes AFTER the turn that dispatched
the spawn has ended (the whole point of detached spawn — pilot's
turn ends in 200µs, the user keeps chatting, and the child returns
later). At delivery time, `assistantIndex` is stale, the guard
fires, the event is dropped, and the user's research deliverable
disappears into the void.

Real bug observed 2026-05-06 19:55:

```
user: "分析一下因信称义"
pilot: "我派 researcher 去了 (job 149370)" (turn ends, OK)
... 1m52s of researcher running ...
user: "?"  (waiting)
pilot: "researcher 已完成 (用时 1分 52秒). 报告应该以独立消息显示在
        你的对话界面上了 ..."
        ↑ pilot's history HAS the synthetic injection
        ↑ but no report bubble ever showed in the UI
```

### Fix

`spawnDone` now handled at the TOP of `handleLocalEvent`, before
the stale-index guard. It appends a fresh standalone bubble (does
not need any active `assistantIndex`) and returns.

Pairs with kinclaw v1.12.0+ — kernel-side queueing into pendingSpawn
+ SSE push were already correct; this was purely a Mac-side UI
plumbing miss.

## [0.4.0] - 2026-05-06

**Cowork delivers deep research end-to-end.** Pairs with kinclaw v1.12.0
to make pilot's spawn-driven research workflow actually usable from
Cowork tab — non-blocking dispatch, live checklist rendering, sticky
brain dropdown, source-of-truth soul handling.

### Added — Detached spawn UI handling

`KinClawAPIClient.swift` adds `spawnDone = "spawn_done"` SSE event
case. `SpotlightContentView.swift` renders the event as an inline
assistant bubble:

```
🔬 researcher (job ab12cd) finished in 287s

[child agent's full markdown report — typically a TL;DR + path]
```

Pairs with kinclaw 1.12's detached-spawn mode: pilot dispatches a
researcher with `spawn(soul=researcher, prompt=…, timeout_s=300)`,
its turn ends within 200µs, the user keeps full chat interactivity
(can ask other things, dispatch parallel researchers, etc.). When
each child finishes minutes later, this code path appears the
result without re-prompting pilot.

`Views/Chat/ChatView.swift` also adds the case to its exhaustive
switch (Chat-mode no-op since spawn is Cowork-only).

### Added — `~/.localkin/souls/` cleanup, repo-as-source-of-truth

`Services/KinClawSupervisor.swift`: soul lookup priority flipped.
Was preferring `~/.localkin/souls/` (legacy install.sh copy) over
the dev repo; now the dev repo at `~/Documents/Workspace/kinclaw/
souls/` wins when present. Multi-day debugging session traced to
exactly this — edits to repo souls weren't reaching the running
helper because install.sh copied with `cp -n` (no-clobber) and
the supervisor's old priority gave the stale family-dir copy
preference.

Pairs with kinclaw 1.12's `install.sh` change which now actively
`rm -rf`s `~/.localkin/souls/` instead of copying into it.

### Added — `KINCLAW_SOUL_DIRS` + `SEARXNG_ENDPOINT` env injection

`Services/KinClawSupervisor.swift` now sets two env vars when
spawning the kinclaw helper subprocess:

- `KINCLAW_SOUL_DIRS=<install.soulsDir>` — kinclaw's spawn skill
  resolves "researcher" / "eye" / "critic" against this. Without
  it (e.g. when launched from `.app` Launch Services rather than
  shell), pilot's `spawn(soul=researcher)` would fail with "soul
  not found in [./souls, ~/.localkin/souls]".
- `SEARXNG_ENDPOINT` — read from `@AppStorage("kinclaw.backend.
  searxng")` (Settings UI value), with `http://localhost:8080`
  Docker default. Without this, `web_search` falls through to the
  now-broken DDG html-scrape path.

### Added — Makefile reads souls + skills directly from repos

`Makefile` `start-helpers` now passes:

- `-soul $(KINCLAW_REPO)/souls/pilot.soul.md` to kinclaw helper
- `-soul $(KINCODE_REPO)/souls/coder.soul.md` to kincode helper
- `KINCLAW_SOUL_DIRS=$(KINCLAW_REPO)/souls` env to kinclaw
- `KINCLAW_SKILL_DIRS=<repo>/skills:<localkin-sibling>/skills` env
- `SEARXNG_ENDPOINT=http://localhost:8080` (auto-detected via
  `curl :8080/`)

`PILOT_SOUL` / `CODER_SOUL` Make vars now point at repo paths
(was `$(HOME)/.localkin/souls/...`).

### Fixed — Cowork "New session" actually clears server history

`SpotlightContentView.swift`'s `startNewSession()` previously
only cleared `messages = []` client-side — kinclaw's per-session
sqlite history kept the prior turn's tape, so a "New session"
click followed by `你好` produced the prior task continuing
(researcher trying to keep finding apartments after we'd asked
something completely different).

Now `startNewSession()` POSTs `/api/session/reset` to kinclaw
(in Cowork mode only — Chat mode is stateless cloud SSE,
already clean). Best-effort: failures don't block the local
clear (user clicked "new" and expects the UI to be empty
regardless), and the endpoint returns 501 on older kernel
builds without exploding.

`Services/KinClawAPIClient.swift` adds `resetSession()`. The
exhaustive SSE event switches in `SpotlightContentView` and
`ChatView` get `case .sessionReset` handlers (no-op for the
local UI — the local clear already happened — but needed so
multi-window setups stay in sync).

### Fixed — TodoChecklistView decode

`UI/TodoChecklistView.swift`: `TodoItem.activeForm` was a non-
optional `String`. After kinclaw 1.12 made activeForm optional
in the kernel-side todo_write skill (auto-falls-back to content
when omitted, which is common for Chinese todos), the SSE
`tool_call` event's params no longer always include
`activeForm` — Swift Codable decode failed silently and the
checklist degraded to the generic "blue pill" tool-call render.

Now `TodoItem` uses an Optional storage with a computed
property that falls back to `content` when missing. The
checklist now renders properly even when the model emits
todos without activeForm.

### Fixed — Cowork brain dropdown reads from Settings

`Services/KinClawSupervisor.swift` SearXNG endpoint resolution
priority changed from "env > hardcoded default" to "env >
Settings UI value > hardcoded default" so the user's customized
endpoint actually gets used. Same pattern will likely apply to
other Backend tab settings as we add more.

### Fixed — KinCodeSupervisor doc

`Services/KinCodeSupervisor.swift` line 18-22 comment used to
say "kincode has no souls / no `-soul` flag — system prompt is
built-in". Outdated: kincode added soul support (cmd/kincode/
main.go takes `-soul`) and ships `coder.soul.md` in its own
repo. Comment updated to match reality + Makefile now passes
`-soul $(KINCODE_REPO)/souls/coder.soul.md` so dev edits to
that file are immediately live.

## [0.3.0] - 2026-05-05

**Code mode polish + stable build loop.** Five additions, four of
them surfacing kincode v0.10.0 capabilities in Code mode plus a
build-infra fix that ends the "我每次都要授权吗" TCC re-auth pain.

### Added — Inline TodoWrite checklist UI

When kincode's agent calls `todo_write`, instead of the generic 🔨
blue tool-call pill we render the todos array as an inline checklist:

  ☐ pending      — outline circle, primary text
  ◐ in_progress  — orange half-filled, uses `activeForm`
                  ("Building ..." instead of "Build ...") for
                  present-continuous reading
  ☑ completed    — green check + strikethrough

Header shows N/M done so progress is visible at a glance.

### Added — Image input (paperclip + drag-and-drop)

Drop a screenshot from Finder onto the input bar, click the new 📎
button to pick from disk, or paste from clipboard. Up to 8 images
per turn. Chips show 28pt thumbnails + media type + × to remove
individually.

Pipeline: Mac encodes each file to base64 → POSTs `{message,
images:[{media_type, data}]}` to kincode's `/api/chat` → kincode
translates to Anthropic image content blocks / OpenAI image_url
parts → vision-capable models (claude-3+, gpt-4o) see the image.

### Added — Plan-mode toggle + banner

📋 list-bullet button next to the paperclip in the input bar. On =
orange icon + thin orange banner above the input ("Plan mode —
read-only, no edits / shell. Tap to disable."). Either path toggles
off — icon and banner are both buttons.

Server-state sync via SSE `plan_mode` events — multi-window UIs
stay in sync. Optimistic update on toggle, revert + error message
if `POST /api/plan_mode` fails.

### Added — Stable `make` build/sign/run loop

`Makefile` + `scripts/sign-app.sh` close the TCC re-auth loop. Every
rebuild ad-hoc-codesigns the .app and the helper binaries (`kinclaw`,
`kincode`) with stable bundle identifiers, so macOS Accessibility /
Screen Recording grants survive across builds.

```
make help     — list targets
make run      — kill old → build all → sign all → launch (the flow)
make sign     — same minus the launch
make build    — just xcodebuild (no signing)
make kill     — stop KinClawMac + kinclaw + kincode
make doctor   — show signing state + running PIDs (first thing
                to run when something looks off)
make clean    — drop DerivedData
```

Stable identifiers re-applied on every signing pass:
  - `dev.localkin.kinclawmac` — KinClawMac.app
  - `dev.localkin.kinclaw`    — `~/.localkin/bin/kinclaw`
  - `dev.localkin.kincode`    — `~/.localkin/bin/kincode`

Helper binaries are signed by their own `scripts/install.sh` in the
sibling repos. The Makefile orchestrates — runs each `install.sh`
inside-out, then signs the .app with hardened runtime + deep mode
via `scripts/sign-app.sh`. `pgrep -x` (executable basename only)
avoids the self-match foot-gun in `make kill` / `make doctor`.

### Why this matters

v0.2.0 shipped the three-mode integration. v0.3.0 makes Code mode
actually pleasant to use day-to-day:

- TodoWrite checklist UI turns kincode's plan-tracking into a real
  artifact you can read at a glance instead of a pill that says
  "todo_write [{...}]".
- Image input lets you drop a screenshot and ask "what's wrong with
  this UI" — the most-cited workflow that was awkward without it.
- Plan mode adds the safety valve: hand kincode a non-trivial task
  and have it research + draft a plan first, instead of yolo-modify.
- Stable build loop = no more re-authorizing AX / Screen Recording
  every rebuild. `make run` is the one command you need.

Paired with [kincode v0.10.0](https://github.com/LocalKinAI/kincode/releases/tag/v0.10.0)
(image input + plan mode kernel-side) and [kincode v0.9.0](https://github.com/LocalKinAI/kincode/releases/tag/v0.9.0)
(named subagents at `~/.kincode/agents/<name>.md`).

---

## [0.2.0] - 2026-05-04

**Three-mode integration shipped.** KinClaw Mac is now the spotlight
shell for the whole kernel family — one window, one hotkey, three
distinct surfaces:

- **Chat** → 98 cloud agents (Selah / Heal / Core / Faith)
- **Cowork** → kinclaw kernel + 5 claws (Pilot / Coder / Critic / etc.)
- **Code** → kincode kernel + repo-aware coding (kimi-k2.6:cloud default)

The three-pill ModeBar lives in the titlebar (mode is the primary
choice — what kind of work). Each tab carries its own agent pool;
switching tabs swaps pools cleanly without bleed-through.

17 kinclaw-mac commits over the day, plus paired changes in
[`kincode`](https://github.com/LocalKinAI/kincode) (rename + serve
mode + soul brain) and [`kinclaw`](https://github.com/LocalKinAI/kinclaw)
(screen capture wiring, orphan watch, boot-time AX prompt).

### Added — Mode infrastructure

- `Models/ChatMode.swift` — Chat / Cowork / Code enum with UserDefaults persistence
- `UI/ModeBar.swift` — three-pill segmented switcher in titlebar
- Per-mode last-agent persistence (`kinclaw.chat.lastAgent`,
  `kinclaw.cowork.lastSoul`)
- Mode-scoped agent picker — Chat shows only cloud groups, Cowork
  shows only KinClaw souls, Code shows static "🦞 kincode" identity
- Synchronous message-clear on mode change so switching tabs feels
  instant, not "old mode's content briefly visible"

### Added — KinCodeSupervisor (`Services/KinCodeSupervisor.swift`)

- Spawns `kincode -serve -port 5002 -soul ...` alongside kinclaw on
  app launch (parallel boot, independent of each other)
- Same lifecycle pattern as KinClawSupervisor (start/stop/State,
  one-shot crash recovery, /api/health probe)
- 5-path binary search (bundle Resources/ → dev repo → Homebrew →
  ~/go/bin)
- Autostart toggle via UserDefaults (`kinclaw.kincode.autostart`,
  default true) — power users can disable from Settings

### Added — `UI/CodePane.swift` (Code mode body)

- Repo picker dropdown with 5 most-recent
- Status dot (green=connected, orange=reconnecting) + tooltip with
  detail (no inline error text crowding the row)
- Streaming text deltas with markdown rendering (same `MarkdownView`
  as Chat surface — fenced code, lists, headings)
- Inline tool-call pills (🔨 hammer + tool name + summary) for bash /
  glob / grep / web_*
- Real diff viewer (`UI/DiffView.swift`) for `file_edit` results —
  parses kincode's ANSI-colored unified diff, renders red/green
  tinted rows with +N/−N counts in the header
- Per-repo session persistence
  (`~/.kinclaw/code-sessions/<repoHash>/<id>.json`) — switching repos
  swaps sessions; "+ new session" button preserves current
- Visual primitives match `chatBody` exactly — same bubble shapes,
  same input bar pill, same welcome-card chips, just with kincode-
  specific contents (🦞 avatar, repo picker, no voice/attachments)

### Added — Settings → Backend → Kincode card

- Autostart toggle (writes `kinclaw.kincode.autostart`)
- Port field (5002 default)
- Live status indicator that probes `/api/health` then `/api/state`
  for the model label ("Running — kimi-k2.6:cloud")
- Both kernels' status probes run concurrently in the same `.task`

### Added — DisclaimedProcess (`Services/DisclaimedProcess.swift`)

The TCC fix that was the day's big debugging arc. macOS's
"responsibility chain" attributes subprocess permission checks back
to the parent .app — so `kinclaw` running under `KinClawMac.app`
was checking against KinClawMac's TCC entries (none) instead of
kinclaw's own (granted from the user's prior CLI runs).

`Services/DisclaimedProcess.swift` is a Foundation.Process replacement
that uses `posix_spawn` directly + the private SPI
`responsibility_spawnattrs_setdisclaim(attrs, 1)`. Subprocesses
spawned through it own their own TCC identity — same identity as
when run from Terminal. Same trick Slack / Tailscale / Karabiner
helper apps use.

KinClawSupervisor + KinCodeSupervisor both updated to use it.
Process-shaped surface (terminate, isRunning, terminationHandler,
processIdentifier) so call sites didn't need rewrites.

### Changed — Layout

- ModeBar promoted to titlebar (was: secondary row below header).
  Hierarchy now matches concept — mode is the primary choice, agent
  is secondary.
- Titlebar reservation 28pt → 22pt; ModeBar internal vertical padding
  4pt → 0pt; titlebar-overlay vertical padding 3pt → 1pt. Net ~10pt
  closer between green Code pill and the secondary row.
- Settings window 540×460 → 620×460 to fit 7 tab labels on one line
  without wrapping. Tab Text views now `.lineLimit(1).fixedSize()`.
- Code mode skips the global agent secondary row; CodePane's own
  repoBar serves that role with same height + paddings as agentBar
  in Chat/Cowork (visual consistency across all three modes).

### Fixed — STT routes local agents to SenseVoice :8000 directly

`VoiceRecorder.serverSTT` was always building
`https://<hostname>/v1/stt`, which produced bogus URLs like
`https://localhost-kinclaw/v1/stt` for local KinClaw souls in
Cowork mode. Now mirrors the existing TTS local-routing fix: detect
`localhost-kinclaw` / localhost-prefix → POST to
`http://localhost:8000/transcribe` (configurable via
`kinclaw.backend.stt`). Cloud STT keeps `/v1/stt` + Bearer auth.

### Fixed — Cowork agent stops getting stuck in cloud-land

When switching from Chat → Cowork before kinclaw souls finished
loading, `applyAgentForMode` returned nil → `selectedAgent` stayed
on Selah (cloud) → menu showed only KinClaw souls but the dropdown
label still read "Selah". Now `applyAgentForMode` always assigns
(even nil), and `loadAgents` re-validates on every catalog refresh —
once souls land, the agent swaps to Pilot.

### Polish

- Removed ScreenFeedView from Cowork: the screen IS the user's
  desktop, embedding a 220pt JPEG copy on top is redundant. Cowork
  is now structurally identical to Chat (different agent pool only).
- Removed file-tree sidebar from Code: kincode navigates the repo via
  `glob`/`grep` tools as it goes, same as Claude Code; no need for
  a 160pt sidebar that broke the three-tab visual symmetry.
- Subprocess orphan-watch — `kill -9` of the parent .app no longer
  leaks kinclaw + kincode children with bound ports (the children
  poll `os.Getppid()` every 2s and self-exit when re-parented to
  launchd). 525 lines of dead code removed alongside.

### Stats

29 commits today across kinclaw-mac (17), kincode (9), kinclaw (3).
Net +~3000 lines of Swift / Go (CodePane + DiffView + DisclaimedProcess +
KinCodeSupervisor + ScreenFeedView-experiment-since-removed).

## [0.1.0] - 2026-05-04

**Open-sourced under Apache-2.0.** Repo flipped public.

Prior to this, KinClaw Mac was a private Proprietary repo while the kinclaw kernel sat public Apache-2.0 nearby. Decision tonight after Jacky asked whether to open it: kinclaw-mac is structurally the **native shell of an already-open kernel** (kinclaw can do everything kinclaw-mac surfaces — kinclaw-mac is just the macOS native packaging). Same stack, should be same license.

LocalKin platform (swarm core, cloud agents, ios Pro client) stays private — that's the moat. KinClaw stack (kernel + Mac shell + future Linux/Win shells) all goes Apache.

License + repo changes:

- `LICENSE` swapped from custom Proprietary text to standard Apache-2.0 (matches kinclaw kernel exactly)
- `Info.plist` `NSHumanReadableCopyright` → "© 2026 LocalKinAI. Apache-2.0 licensed."
- `README.md` rewritten:
  - Apache-2.0 badge + macOS / Swift badges in header
  - Status moved from "Planning" placeholder to "v0.1.0 shipping"
  - Family section split into "KinClaw stack (all open)" vs "LocalKin platform (closed)"
  - Added Build from source section
  - Added Contributing section
- GitHub repo visibility flipped private → public

All 40+ commits between scaffold and v0.1.0 stay in history — fork heritage from localkin-ios is transparent and intentional.

Trademarks: `KinClaw` name + lobster mark held by LocalKinAI; code Apache-licensed for use, name reserved for upstream-faithful builds. Standard OSS pattern.

## [Unreleased]

### Planning kicked off — 2026-05-03

Initial repo scaffolded. No code yet — see [`docs/spotlight-shell-plan.md`](docs/spotlight-shell-plan.md).

**Planned milestones**:
- M0: Fork [`localkin-ios`](https://github.com/LocalKinAI/localkin-ios), retarget to macOS 13+, build green
- M1: `KinClawAPIClient` adapter (`/api/chat` + `/api/events` for local kinclaw serve)
- M2: `SpotlightWindow` (NSPanel + nonactivating + glass blur)
- M3: Global hotkey (⌘⌥K) + menubar (🦞 NSStatusItem)
- M4: `KinClawSupervisor` (subprocess management + auto-restart)
- M5: Polish (animations, position/size memory, settings UI)
- M6: Codesign + notarize + DMG (blocked on $99 Apple Developer cert)

Estimated 4 days of dev + 2 days of signing/distribution work after cert lands.
