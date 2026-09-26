# Changelog

All notable changes to KinClaw Mac.

## [Unreleased] — Companion mode, and a panel that says what it is doing

A day and a half on two things: making the companion mode something you
can actually talk to, and making Cowork and Code tell you what the
agent is allowed to do.

### Added — 放逐之城: a town that has to get through its winters

"做城市建造吧". Jev tab → 建造 → 放逐之城 — Banished-like, played with the mouse.

- **A year in twelve months** (`Games/CityEngine.swift`, Foundation only): a
  64 × 40 map with a river and two fords, a pond, woods, rock and ore.
  Everybody eats a food a month. Fields are planted in spring, grow through
  summer and come in in autumn — what is not in by winter is lost; gatherers
  pick berries and mushrooms in the woods from spring to autumn; fishermen
  fish all year, slower in winter. From the first month of winter to the
  first of spring every house burns two firewood a month, split from logs at
  the woodcutter's; a family without it freezes, and so does anybody without
  a house. Hunger and cold kill in three or four months. Children are born
  into houses with a couple and room, grow up at twelve and work until
  sixty-five; young couples move out of crowded houses into empty ones;
  newcomers arrive in spring when there are three free places and half a
  year of food. Tools wear out with work; without them every job is 40%
  slower — a mine and a smithy make more.
- **Eleven kinds of building** — houses, storage, fields, gatherer's hut,
  lumber camp, woodcutter's, quarry (on rock), mine (on ore), smithy,
  fishing hut (on water) and the town hall. The people with no other job put
  everything up: they fetch the logs and the stone from a storage, carry them
  to the site and build. Workers carry what they make to the nearest storage,
  so where a storage stands matters; families fetch food and firewood home.
- **Played with the mouse** (`Games/CityView.swift`): pick a building, click
  the map (⇧ to keep placing); drag roads — people walk faster on them;
  拆除 takes a building down and gives half back; click a building for what it
  does, who works there (−/+) and what it made this year. The computer sets
  how many work where unless you do. Pause to 8×; the town waits for 开始.
- **Who is mayor**: 我, 电脑, Jev or 大模型. The computer weighs each need by
  how urgent it measures — a roof before winter, food, firewood for the cold
  months, logs and stone, tools, room to grow — and builds and staffs in that
  order, never spending the wood for the first lumber camp on anything else
  (the first Jev test starved a whole town that way). Jev and chat models
  choose which need comes first every ten seconds, each option with the
  measurements — months of food, firewood against the coming winter, the
  homeless, tools per worker; whatever they choose, people about to die come
  first. Jev 参谋 tells the person what to build where, with 照做.
- **Measured**: the computer on twelve maps for twenty years — every town
  alive with 95–129 people, 3 starved in all, none frozen. Jev as mayor on
  three maps for fifteen years: 94, 85 and 96 people to the computer's 104, 89
  and 100, nobody starved or frozen.
- `city_play` (mayor, speed, a new town) and `city_status` in the panel's tools.

### Changed — the building games, drawn properly

"游戏画面太糙了啊，都优化一下啊". 帝国时代 and 放逐之城 share one painter
(`Games/GameArt.swift`): from above at three-quarters, lit from the top left,
shadows to the lower right, all vector and sharp at any zoom.

- **A camera**: pinch or ⌘-scroll to zoom, two-finger scroll, drag or the
  arrow keys to move, = and - and the buttons in the corner; it starts close
  on your town.
- **Land**: grass with tufts and flowers when close; water as one body with a
  sandy shore, shallows and deeper water and glints; roads as trodden paths,
  round where they bend and meet; woods of pines and broadleaves with trunks,
  layered crowns and shadows; rocks, gold and ore as boulders; berry bushes.
- **Buildings stand up out of their plots**: front walls of plaster and
  timber, logs, planks or stone; gabled and hipped roofs of shingles, thatch
  or slate; doors and windows, chimneys with smoke, scaffolding and the
  materials piled while they go up. The town hall has a bell tower and a flag;
  the storage its goods in front; the smithy a glowing forge, an anvil and
  sparks; the quarry terraces, blocks and a crane; the mine a timbered mouth,
  rails and a cart; the fishing hut a jetty and a boat.
- **放逐之城's year**: fresh grass and blossom in spring, deep green in summer,
  gold grass and orange, red and yellow trees in autumn with leaves falling,
  snow on the ground, the roofs and the pines in winter, bare broadleaves,
  frozen water, snow falling; windows lit and chimneys smoking in the houses
  that are warm; fields that sprout, ripen to gold and are cut to stubble.
- **帝国时代's towns change with the age** — wood and thatch, then timber and
  shingles, then stone and slate — with the team's banners on every building;
  a mill whose sails turn, a stone tower with battlements, fire on a building
  half destroyed.
- **The turn-based 帝国 is drawn the same way**: houses, keeps, halls, towers
  and camps from the same drawings, in the style of its four ages — the last
  marble walls under gold roofs — with fields, woods, gold and berries, and
  villagers and ranks of soldiers as figures. Chess pieces are larger, ivory
  and ebony, with a shadow at their foot.
- **People** with legs that step, arms, faces, hair and hats by their work —
  straw hats in the fields, hoods among the berries, helmets in the mine and
  the ranks — carrying logs, stone, baskets and tools; spearmen with spear and
  shield, archers with bows, knights on horses.

### Added — Montage: OpenMontage on the box, where it can be seen

"openmontage看不见怎么用啊": installed on the box and tested, OpenMontage was
a folder there and nothing here. Studio → Montage is where it shows.

- **The board** — OpenMontage's own Backlot: the production as it happens
  (stages, script, scene cards, takes, renders) and a library of every
  project. The app starts it on the box if it is not running and brings it
  here through an ssh tunnel (it listens on the box's 127.0.0.1:4750 only).
  Once the agent opens a project the board follows it; back, home — the
  library ("openmontage应该可以回到首页啊") — and reload sit above it, and the
  Safari button opens the same board in a browser.
- **The agent** stands on the tab's left, as on every Studio tab (below). It
  runs on this Mac and works ~/OpenMontage on the box through a bridge,
  `Resources/om_bridge.py`: an MCP server the app installs on the box and
  the agent starts over ssh — list, read, look (a picture, or a clip as a
  contact sheet), write, run (a command in OpenMontage's venv, up to 15
  minutes), and start + job for renders, H3 and music. So it can think with
  this Mac's Claude subscription instead of the box's Claude Code, which
  bills by use. It is briefed to follow OpenMontage's own guide, checkpoints
  and approval gates, to generate with the box's qwen_image, h3_video and
  minimax_music instead of paid APIs, and to say what a plan costs in time.
- **Tools**: `montage_ask` (so "用 OpenMontage 拍…" said to her starts one),
  `montage_status` (board, agent, the terminal's last lines), `montage_stop`.
  Quitting the app ends the agents and the tunnel.
- **scripts/openmontage**: the three tools that plug OpenMontage into the
  box's ComfyUI — `qwen_image` (Qwen-Image 2.1, edit mode composes first
  frames), `h3_video` (MiniMax H3 from portraits, first frame pinned, `hold`
  pins start, middle and end) and `minimax_music` (MiniMax Music 3) — and the
  skill that says how to film with them. Tested on a shot of 五饼二鱼: first
  frame in 135 s, the shot in 712 s with frame 0 exactly the pinned picture,
  a 14 s cue in 982 s.
- The first film made this way, 海边漫步者: twenty seconds, vertical — a cast
  portrait, first frames composed on it, four H3 shots, a MiniMax score and a
  Remotion cut, from one sentence.

### Added — An agent on each Studio tab

"这个真的很酷啊，我们的film和comfyui我就想要这种啊，就是通过agent来操作啊":
Film, Motion, Comfy and Montage each have an agent standing along their
left. Say what you want in a sentence, watch it work in its terminal and
the result land on the tab beside it, answer when it asks.

- **One each, kept apart.** Tried as one agent for all four and taken back
  ("我后悔了……他们是独立分开的"): each has its own conversation, its own
  folder, and its own choice of agent and brain.
- **Claude Code or Codex** ("而且应该也可以用codex"), thinking with its own
  sign-in — the Claude subscription, ChatGPT — or a model from this Mac's
  Ollama, the box's Ollama or the box's kinfer. The menu says whether a
  sign-in is a subscription or billed by use.
- **Only its tab's tools**: Film's agent the film tools (film_guide first:
  the method this studio's films are made by) and Comfy's; Motion's
  motion_find, motion_make and motion_status; Comfy's the comfy tools —
  each through the panel's MCP relay cut down with `--mcp-stdio --tools
  a,b`, which lists only those and refuses the rest. Claude Code's file
  editing is off.
- **A column, not a strip** ("对话agent应该在左侧竖立着"): about 85 columns
  wide to start, its edge dragged wider or narrower, put away while it keeps
  working. Once it runs, its own prompt is the one place to type
  ("为什么有两个输入框呢").
- **接着上一次 and 重启** ("加个可以重启的按钮"): back into its last
  conversation, found by id where the harness keeps it — Claude Code's by
  folder, Codex's by the folder each session names — and offered only when
  there is one. After it stops, its screen stays, with 重启 and 新开一个
  under it, and words typed go on in that conversation. It used to die with
  "No conversation found to continue" and "退出码 256" — an exit code of 1,
  as waitpid gives it — and nothing to click.
- **What needs you is said in words** above the terminal: the folder-trust
  question, a sign-in that has run out. Neither is answered for you.
- **The wheel scrolls Claude Code** ("不能在claude code里面滚轮啊"): a TUI on
  the alternate screen asks for the mouse, and SwiftTerm never passed it
  the wheel. It gets buttons 4 and 5 now; a program without the mouse gets
  arrow keys.
- **A server's model, everywhere**: with an Ollama or kinfer brain, every
  model name Claude Code asks for — its default, the aliases, the small
  model for its chores, its subagents' — is that model. The messages typed
  while it answered went out as its default, claude-opus-5-5[1m], and the
  box said model_not_found. The Term tab aims Claude Code the same way.

### Changed — The panel's look: one theme, four groups, a film tab laid out for watching

"你能把kinclaw-mac的UI搞一下吗": 整体视觉更精致, 标签太多重新组织, 片场 Film
用起来更顺.

- **Why it looked flat**: the panel was drawn for dark glass and forced dark
  with `.preferredColorScheme(.dark)`, which an NSHostingView in a plain
  NSPanel never passes to its window. On a Mac in light mode it came up grey,
  and every `Color.white.opacity(…)` meant as a card vanished into it.
  `Theme.swift` now has the few values everything is drawn with — one accent
  (the app's jade, a shade deeper), canvas, sidebar, card, well, hairline, a
  type scale — each with a light and a dark side, and Settings → General →
  外观 sets 跟随系统 / 浅色 / 深色 on the app itself. Each tab's own green,
  blue and purple became the one accent.
- **Four groups instead of nine tabs**: Talk (Chat, Cowork) · Work (Code,
  Term, Web) · Studio (Film, Motion, Montage, Comfy) · Jev, centred in the
  title bar and level with the traffic lights. The open group shows its
  members; a closed one is one word and goes back to the member used last;
  right-click one to go straight to any member. The blank band that sat
  under the bar is gone.
- **Film**: the player takes the video's own shape (an H3 film is 928×544,
  and a player cut to the stills' 16:9 had black bars) and no longer starts
  over every two seconds while a film is being shot. Shot cards are in the
  film's shape and cut to it — a wide picture used to fill past its cell and
  lie over the next card. The English prompts moved into a tooltip and a
  folded 「片子是怎么写的」. The header keeps 接着拍 and the folder; the rest is
  in a ⋯ menu, in words (重做旁白和配乐, 重新检查每个镜头). While shooting, a
  bar says which shot is doing what, with 停 beside it. The ten controls
  under the idea are chips that say what they are set to, and 钉帧 shows
  only for H3.
- **Motion, Comfy, the conversations**: Motion laid out like Film (the
  player in the video's shape, the reference, the scene and the button in
  rows that read); Comfy's ask bar and welcome with examples; Chat, Cowork
  and Code read in a centred column instead of lines 1900 points long.

### Fixed

- Comfy showed an empty "Choose an agent" row: it was missing from the list
  of tabs without an agent picker.
- Full screen did nothing, and the panel sat on top of every other window
  ("不能全屏……窗口不要总是放在最前面"). It is an ordinary window on one Space
  now, and the green button takes it full screen. There the mode bar sits
  below the strip AppKit keeps for the title bar, which took every click on
  it ("全屏模式下，没有办法点最上面的菜单"); and tools that switch tabs no
  longer bring the panel over what you are doing.
- `make sign-app`'s smoke test launched the whole app for a second. That
  instance started the panel bridge and rewrote ~/.localkin/panel.json with a
  token that died with it — every panel tool the kernel had then got a 403
  from the app really running — and its cleanup pkill'd whatever kinclaw and
  kincode were left, which with the app open were the app's own. It now runs
  the binary as the MCP relay (`--mcp-stdio`), which loads every library the
  same way and starts nothing.

### Added — 帝国时代: a real-time strategy game you build with the mouse

"我要的是真的建造类游戏啊": the turn-based 帝国 was orders from a list with
the buildings placed for you. This one is played on the map. Jev tab → 建造 →
帝国时代.

- **帝国 stays**, first in the list: the same game in rounds of ten seconds,
  one order a side each round — two villagers to a job, three moved from one
  job to another, a building, the next age, a batch of soldiers, march, come
  home, wait. For a model each order is measured: what it does to income and
  population, what it leaves at home, and how any fight it leads to would come
  out (the engine fights it in advance). A fallen town centre loses; after 100
  rounds, the stronger empire. Either side can be any player, a person too;
  `jev_play` takes it as `empire`, with `blue` and `red`.
- **A 48 × 30 map, in real time** (`Games/RTSEngine.swift`, Foundation only):
  two towns across a lake with two fords, forests, gold, stone and berry
  bushes, mirrored so neither side is favoured. Villagers walk (A* over the
  tiles) to a tree, a bush or a rock, gather, and carry the load to the
  nearest building that takes it — the town centre, a mill, a lumber camp, a
  mining camp — so where a camp stands matters; trees fall and rocks run out.
  Buildings are laid as foundations and put up by the villagers sent to them;
  farms are fields a farmer works for ever. Houses give room for five; the
  town centre researches the Feudal and Castle ages; barracks, an archery
  range and a stable train spearmen, archers and knights, which beat one
  another in a circle. Soldiers fight what they see; town centres and towers
  shoot arrows. The side whose town centre falls loses.
- **Played with the mouse** (`Games/RTSView.swift`): left click or drag a box
  to select, right click to send — to a tree to chop it, to a foundation to
  build it, to a farm to work it, to an enemy to attack it, to open ground to
  go there; a building's right click is its rally point. A villager selected
  shows the buildings; click one, then the map — green where it fits, red
  where it does not, ⇧ to keep placing. Train and research from the town
  centre and the military buildings; 闲置村民 finds the idle; 全军出击 sends
  every soldier. Speed 1×/2×/4×, space pauses, Esc lets go.
- **Drawn** (`Games/RTSScene.swift`): trees that shrink as they are cut, rocks
  that shrink as they are mined, a lake that ripples, buildings in the style of
  their owner's age with scaffolding while they go up and a mill whose sails
  turn, villagers swinging their tools and carrying what they gathered,
  spearmen, archers and knights, arrows in flight, blows, the fallen.
- **Who plays each side** ("帝国时代除了我也可以选对战对象"): 蓝方 and 红方
  pickers at the top right — 我, 电脑, Jev, or 大模型 (a chat model on an
  Ollama, chosen from a menu). One person at most; with nobody it is a game to
  watch, both stocks shown. The choice is remembered.
- **The computer** (`Games/RTSBrain.swift`) plays a build order — villagers
  first, houses before the cap, camps by the trees and the gold, farms when
  the bushes run out, barracks, the next age with the food kept for it,
  soldiers that beat what it sees, an attack when the army is big enough —
  and defends when raided. Against itself on 40 maps: blue 20, red 19, one
  unfinished at 25 minutes; Feudal at 6–7 minutes, Castle at 11–15, a town
  centre down at 12–23.
- **Jev and chat models command** (`Games/RTSCommander.swift`): every five
  seconds of play (ten for a chat model) one question — which way to lean:
  grow the economy, build up the army, advance an age, attack, or defend
  (offered only when raiders at home outmatch the guard). Each option carries
  what the program measured: villagers against what the age wants, income a
  minute, what the next age costs and how long saving takes, both armies and
  which is stronger by how much, what defends their town and the odds of an
  attack. The computer's hands carry it out; saving for an age is seen
  through unless home is in danger. Jev against the computer on three maps:
  three wins, in 18–23 minutes — it is the harder opponent. kimi-k2.6 answers
  with a bare key in 1–3 s; glm-5.3-flash thinks aloud first and ends with one.
- **Jev 参谋** for the person: specific moves ("a lumber camp at 12,20: 31
  trees within four tiles…") with a 照做 button; a saving plan followed is
  bought by itself the moment there is enough.
- **Fixed on the way**: soldiers on the tile next to their target counted as
  arrived while still out of reach, so whole armies stood facing each other
  for minutes — they close the last step now. Ties in where to build and which
  tree to cut went to the left, the map's edge for blue and its middle for
  red — placement and search now mirror. Soldiers with nobody left to fight
  went for the nearest farm; they go for the town centre, then towers, then
  military buildings. The counter-pick trained knights against spearmen;
  archers now.

### Added — Jev: driving, a shooter and Flappy Bird, drawn properly — and a seat for you

Three games that move ("飞行或者射击类游戏啊… 开车啊"), and anybody at the
keyboard can play any of the ten ("我也可以玩啊").

- **开车** — a five-lane highway from above. Each tick: a lane either way,
  a speed either way (30–120 km/h). Trucks and cars keep to their lanes and
  slow behind slower ones, so everything on the road is where the program
  says it will be; fuel burns a unit a tick and the cans that refill it come
  by the mile, so a driver who dawdles runs dry. The words say what is ahead
  in the lane and how fast it closes, whether there is room to brake behind
  it, whether a lane beside is open, whether a move gets a lane closer to the
  fuel — and, since the traffic's future is known, whether a crash can still
  be avoided at all. The evaluator looks four ticks ahead over every
  combination of moves.
- **飞机大战** — a plane on the bottom of the sky against fighters (straight
  down), swoopers (diagonal, off the walls) and bombers (slow, dropping bombs
  on a beat); a gun that fires every other tick, so a shot that hits nothing
  costs something; three lives. The words say whether the plane is hit this
  tick, whether a hit can still be dodged, how long it is safe where it
  stands, what a shot fired now will hit and when, and what the next one
  would.
- **像素鸟** — flap or glide. The bird's future is arithmetic, so the words
  do it: where each choice puts it, where gliding on would meet the next pipe,
  and whether any way of flapping still gets it through, with how much room.
- Measured, seeds 100–102: the evaluator drives ~1,500 rows in 400 ticks, a
  random driver crashes at ~90; it shoots ~1,100 points in 400 ticks against
  random's 120; it passes ~100 pipes in 600 ticks where random falls at the
  first. Jev on its first go: 330 points in 150 ticks without losing a life;
  30 pipes in 200 ticks (the evaluator's pace); and dry at 136 rows — the words
  mentioned fuel only in the lane it was already in. They say which way the
  fuel is now, and the tank is 60, a can 25. It still ran dry, at a crawl: it
  read "closing 2 rows a tick" as danger and sat behind a car at its speed with
  the next lane empty. Said as a driver would — "slower than you (you catch it
  in about 8 ticks, with room to brake behind it)", "going your speed: you are
  stuck behind it" — and with speed ranked above everything but safety and fuel
  in the judging, it drove 954 and 927 rows in 250 ticks, agreeing with the
  evaluator 92% and 88% of the time (the evaluator: ~975).
- **They are drawn, not gridded** ("你这画面也太弱了"). A game can paint
  itself (`JevPainted`): a SwiftUI Canvas sixty times a second, each frame part
  of the way from the last tick to this one, so the car slides into its lane,
  the stars stream and the bird arcs while the game itself still moves a
  question at a time. A road with kerbs, lane dashes, trees rolling past, cars
  with glass and lights, lorries, a glowing fuel can, a speedometer and a fuel
  gauge; a starfield with jets, lasers, bombs and fireballs; sky, towers,
  clouds and bushes at their own speeds behind proper pipes and a bird that
  beats its wing and noses up and down.
- **All ten are drawn now** ("其他七个也换成画出来的画面"). Tetris: a well
  of bevelled blocks, the piece falling onto the board it was dropped on,
  the rows it filled flashing before they go, the next piece beside, and a
  dashed shadow where a person's piece will land. 2048: the familiar tiles,
  sliding to where they go, a merge swelling, a new tile growing in. Snake: a
  blue snake with eyes that look where it is going, sliding a square a tick
  over checkered grass, an apple that shrinks into its mouth. 21 点: a felt
  table, real cards dealt from a shoe in dealing order, the hole card turned
  over when the dealer plays, a finished hand left on the table a moment with
  its verdict before the next is dealt, chips. 五子棋: a wooden board with its
  coordinates, glossy stones set down, a line of light through five.
  Chess: a classic board with coordinates, the last move and a king in check
  lit, the piece sliding, dots for where a picked-up piece may go. 中国象棋:
  a wooden board with the river and the palaces, men as wooden discs, the man
  sliding. Clicks on the pictures land on squares and points
  (`JevPainted.spot`), and a script played a person's keys and clicks into
  every game — Tetris dropped by the cursor, e2–e4, 炮二平五, a stone on
  H8 and one in the far corner.
- **我** — a seat for a person, in every game. Games that move by themselves
  run on a clock and read the keys held or pressed during the tick (driving:
  ←→ lanes, ↑↓ speed; the shooter: ←→ and space, held for automatic fire;
  Flappy: space or ↑; Snake: the arrows, and a person can steer into a wall);
  the others wait — 2048 the arrows, 21 点 H/S/D, Tetris a cursor (←→ move,
  ↑ turn, ↓ or space drop, a shadow where it lands), and at 五子棋, chess and
  中国象棋 a click on the board (a piece, then where it goes; every legal
  move, not the models' shortlist). Or click one of the options listed beside
  the board. A key starts the game; 速度 sets the clock.
- **A click that cannot move says why** ("那几个炮连到一起的时候…我不能移动棋子").
  Nothing had been wrong with the rules — a man that is one of two screens
  between an enemy cannon and its general cannot leave the file — but a click
  on it did nothing, which looks like a bug. Now a line over the board says
  why: 这个马被牵制了 / 你正被将军：这个车解不了将 (and the men that can answer
  a check are ringed) / 车这样走完，你的帅会被将军 / 炮吃子要正好隔一个子 /
  还没轮到你：Jev 在想. The same at chess; at 五子棋, 这里已经有子了. While the
  other side is thinking the tab says so. Checked on four set positions
  (`JevXiangqi.setUp(fen:)`); `jev_status` now prints the position of a game
  for two.
- **The same seed, the same game** — under the board, the best score each
  player has made on this seed: "种子 100 最好成绩：启发式 358 · 我 279".
  Kept across launches.
- `jev_play` knows the new games, and will not move for a seat that is 我.

### Changed — Film: H3 shots are filmed from a pinned first frame

Every H3 shot now starts from a picture made and checked before it is filmed,
pinned to its first frame (ComfyUI's `MiniMaxH3AddGuide`, on the ref2va model
the box already has). A shot with people in it gets its first frame composed
by Qwen-Image 2.1 edit — the set as image 1, the portraits of who is in it
after — from the storyboard's picture of the moment, counted where the shot
counts things (too many is changed once for the count, then composed afresh
once — a hand over a loaf or two fish lying together is not a fault). A shot
with nobody in it starts from its set; one that counts things is pinned at its
middle and its end as well: pinned only at both ends, the twelve baskets
wandered to another slope in between and came back; pinned three times, the
shot held — twelve at every half second, the mist moving on the lake.
The cast portraits and the set stay H3's references, as before.

Tested on 五饼二鱼 before it was built: the boy's first frame came out right
the first time (his face, five loaves, two fish, the hands coming in), and the
pinned take never showed more than five loaves — and H3 brought Jesus's face in,
smiling at the boy, a better beat than hands alone. Side by side, both
pinned takes looked more natural than the old ones (the baskets had been a
camera moving over a still, steady and lifeless); they are in the film now.

Takes are counted every second rather than at five fixed moments (the wandering
baskets were counted right at 1.3, 2.6 and 3.9 s and were fourteen at 2 and 4),
and the reviewer is asked whether a shot jumps to another place or arrangement
half way (it had passed one that did with a ten). A shot pinned to hold its
picture is quiet on purpose, and the reviewer is told so: it had called the
three-times-pinned baskets "a frozen still image" and had them filmed again.

A first frame is made again when its set or its picture changes (a reshoot
with new words, a retake that redraws the set); `film_fix_picture from: start`
changes it by hand, and a reshoot films from the changed one. 「钉帧」 in the
tab turns it off. A shot with people takes about two minutes longer.

### Added — Film: the director's work after the first cut, as tools

Everything done by hand on 五饼二鱼 between the first cut and the one its owner
accepted — six loaves where there should be five, a thirteenth basket, shot 7's
bread not shot 4's, one shot brighter than the rest, music too quiet — as tools
and as steps of the pipeline. The reviewer had passed every one of those takes
with a ten.

- **`film_frames`** — a shot as one picture: a frame a second, the time on each,
  other shots beside it to compare, or the set it is filmed from. The line
  `image://…` in the answer is how the kernel attaches a picture to a tool
  result, so a brain that can see looks at the take itself.
- **`film_count`** — counted one frame at a time, one box per object: kimi-k3
  was right on every test frame, twice, in 2–8 s; asked for a number, models
  counted one loaf twice as often as not (kimi-k2.6 also said four for five).
  In a take only *more* is a fault — a hand over a loaf is not — and it must
  show in two frames; in a set every one must be there. "Could not count" is
  never read as right.
- **`film_fix_picture`** — Qwen-Image 2.1 edit through ComfyUI: a set, or a
  frame of the take that becomes the first frame the shot is filmed from, with
  other shots given as image 2, 3… (`like`). With `counts` it counts the set
  first and refuses to touch one that is already right (a right set, changed
  anyway, came back as six pale pitas), and counts the result. `from: new`
  draws the set afresh three times and keeps the one that counts right: an edit
  keeps the old picture's crowded layout (twelve baskets asked for four times
  gave 14, 14, 15, 15).
- **`film_reshoot`** takes `counts` (the pipeline counts the set, repaints or
  redraws it, films, counts the take, films again when there are more), `match`
  (`{thing: bread, like: 4}`: the first frame of the take is changed to look
  like shot 4's, described by the model that can see from shot 4's own frame,
  and filmed from on LTX — how shot 7's bread came to be shot 4's; H3 keeps
  faces, not things, even with the loaves as a reference picture), `method`
  `animate` / `move` (no video model: the camera glides over the picture, the
  replaced take's sound kept — nothing can be added to it), `h3` words, and
  `later` (several shots set up, filmed in one run).
- **`film_grade`** measures every shot and matches one to another; the cut by
  itself evens out a shot brighter or darker than both its neighbours when
  those agree (a trend, like evening falling, is left alone).
- **Every cut is mastered**: −16 LUFS integrated (BS.1770-4 gating, computed
  in the app — this Mac's ffmpeg does not run), peaks held under −1.5 dBTP by
  a look-ahead limiter; ffmpeg's ebur128 on the box measured the result at
  −16.0 LUFS, −1.9 dBTP. `film.premaster.mp4` keeps the cut as it came out.
- **Counts in the pipeline**: the storyboard lists `counts`, the photographer
  and H3's prompts state them, every set is counted before it is filmed, every
  take after (a second count confirms); a shot with nobody in it whose count H3
  will not keep is glided over its counted set instead.
- **The cut scales every clip to fill the frame**: H3 comes out 928×544, LTX
  1024×576, and a clip of another size used to sit in the frame's corner.
- **`film_guide`** — the playbook: what to look at, which tool fixes what,
  what the models can and cannot be trusted with.
- Tools answer within the kernel's 60 s: long work runs in the background and
  `film_status wait: true` waits for it, starting with the time (three
  identical answers in a row trip the kernel's no-progress breaker).
  `comfy_run` used to wait twenty minutes and the relay answered "timed out".

Tried and set aside: the Pilot (kimi-k2.6) directing a fix round on its own.
In five runs on a copy of 五饼二鱼 it looked, counted and fixed shot 4 by
itself, but its judgment was the weak part — it put "five loaves" on the shot
where the bread is being broken, redrew a set that was already right, and went
round an edit that could not reach twelve baskets. Films are directed by
Claude, with these tools.

### Added — other people's best image prompts, and a named look for every film

- **提示词库 in the Comfy tab.** devanshug2307/Awesome-AI-Image-Prompts (MIT,
  235 prompts in 17 categories, each with its example picture), fetched from
  the repository and kept. Search, open one in Qwen 2.1 (or Qwen edit for the
  51 written for your own photo), put it into the open workflow, or
  **换主题**: the writer keeps its structure, camera, light, textures, look and
  negative list and changes only what it is of. One of its prompts is itself a
  guide full of code fences, so numbered headings start entries whatever the
  fences say (a fence-trusting parse found 60).
- **Film's photography pass learned from them.** It is the director of
  photography *and unit still photographer* on a high-budget feature, first
  names one real film whose cinematography the whole film should look like —
  "In the visual tone of … (year), cinematography by …" — then writes every
  shot against it: at least five textures you could touch, and a closing
  "Must not appear:" list. The look is kept on the film, shown on its page,
  and given to every H3 prompt.

### Added — Film: a narrator, and music under the film

The voice-over was read in her voice — the companion's, bright and young,
over the feeding of the five thousand — and there was no music at all. The
box's kin audio has both, so each film is now given a narrator and a score
once, by the writer, from what the film is about:

- **The narrator** is a voice picked from the box's TTS server's own list
  (`/voices`) and an `instruct` — how to read it, in words ("用低沉、庄重、
  缓慢的语气，像在讲述古老的经文"). For 五饼二鱼 it chose Uncle Fu · 成熟男声.
- **The music** is a MusicGen description in the story's own time and place
  ("oud and ney flute with frame drum and sustained drone, adagio,
  reverent… instrumental, no vocals"), made on the box by `kin audio music`
  and laid under the whole cut: looped if the film is longer than 30 s,
  faded in and out, and lowered while the narrator speaks. 配乐 toggle.
- **The film narrator is its own tier.** Chat keeps the fast voice (qwen3-tts
  0.6B on :8101); films get a *designed* voice — Qwen3-TTS 1.7B VoiceDesign as
  its own box service on :8102 (Settings → 盒子上的服务), made from a sentence
  the writer composes for each film ("老年男性，嗓音低沉温润如古木……像在黄昏
  中亲口讲述自己少年时亲眼所见的神迹"). Chosen by ear against VoxCPM2 and the old
  voice. And the voice-over is no longer four captions read one by one: it is
  ONE continuous passage, written to the film's length and read in one go —
  the take that won the listening test was the long sentence, not the short
  lines. Laid from 0.6 s over the whole film; a passage slightly too long is
  read up to 12% faster (pitch kept) rather than cut, because the writer does
  not always keep to the length it is given (70 characters for 59 once).
- **重新配音配乐** (and `film_rescore`) does it for a finished film without
  filming anything; the old voice files and cut are kept aside.
- Two fixes found on the way: a slow narrator's line (4.9 s) ran into the
  next shot's and the overlap stopped the export ("Operation Stopped") — a
  line now waits for the one before it; and the first voice request of a run
  went out on a kept-alive connection the server had closed and was never
  retried — it was always shot 1's line that was missing. It is retried once.

### Added — Film: stories shot on MiniMax H3, with a cast

What the video model could not do was keep a person: every still was drawn
on its own, the man in shot 3 was not the man in shot 5, and the story
rules learned to hide faces — hands, backs, silhouettes. H3 films from
references, a picture of each person and a picture of the place, and keeps
the faces and the clothes. "H3（人物一致）" beside the story picker:

- **Cast first.** The writer names the people the story is about (at most
  four) and what each looks like in the period; each is drawn once as a
  chest-up portrait on a plain backdrop, and shown on the film's page.
  The storyboard is told the film has a cast and to show their faces.
- **Every still is the set.** The photographer's pictures are passed once
  more through a single-job rewrite that takes the people out — told only
  as an override inside the long brief, it drew headless torsos; told
  "take them out", it hung their robes on posts; told "the place before
  anyone arrived, never name clothes or posts", it drew the place.
- **Each shot in H3's own words.** One call writes every shot's prompt in
  the six-part form of MiniMax's official guide for reference mode (fetched
  from their repository), with the portraits and the set labelled per shot.
- **Two passes, because 96 GB is not both.** All portraits and sets are
  drawn while the image model is loaded; then the diffusion servers are
  stopped and every shot is filmed on H3 (4-step LoRA, about 5 s a shot,
  native sound). A retake that needs a new set brings the image model back
  for it. The graph is built directly — no ComfyUI page in the way.
- The reviewer does not count a face against an H3 shot.
- **Props carry across shots.** A shot's `props` names pictures in the film
  folder (`shot-04.png`, the basket with the five loaves); H3 gets them after
  the portraits and before the set, labelled "must look exactly like it".
  Described only in words, the bread in 五饼二鱼's shot 7 came out as pale
  white rolls beside shot 4's golden-brown barley loaves.

### Added — Comfy: ComfyUI's ready-made workflows, as forms

ComfyUI on the box does things nothing else here does, and it asks for a
node graph. Most people who want what it makes do not build graphs — and
do not need to: it ships about three hundred workflows that people who do
built and tested. The Comfy tab lists them (thumbnail, what it does, how
many gigabytes of models), opens one as a form, runs it on the box and
brings back what it made to the art folder's `comfy/`, with the exact
graph and prompt beside it so any run can be opened again.

- **The graph lives in ComfyUI's own page**, in a web view that is usually
  off screen. A template is a UI workflow — subgraphs, widgets promoted out
  of them — and the server runs an API prompt; the conversion is the
  frontend's own code, always the version that matches the server, so it
  is asked rather than imitated. The form is the page's widgets; "编辑器"
  shows the same page, and what is changed there is what runs.
- **Words instead of a template.** "说你想要什么" has the writer model pick
  the template and fill it; with one open, it changes what was asked and
  nothing else, and a length or a shape goes into the setting that holds
  it, not only into the prompt. It is told the inputs are the user's and
  unseen — the first try described the template's sample picture (a boy
  in a red cape) as if it were theirs.
- **Official prompt guides.** For MiniMax H3 the writer is given MiniMax's
  own prompting guide (fetched from their repo once and kept, not shipped),
  and writes H3's structure: `subject_definitions`, `summary`, … .
- **What is missing is said before running.** Models the workflow names
  that the box lacks are listed with their size; the box downloads one
  only after a confirm that names it. A loader still pointing at the
  template's sample file (which is not on the box) blocks the run until a
  file is chosen.
- **Which ones run is on the list.** Every local template's graph is read
  (240 of them, five seconds) and checked against the box's model folders
  and node types: ✓ 能跑, 缺 N 个模型, or 缺插件, what runs sorted first and
  a "只看能跑的" filter. Measured the day it was built: 3 of 240.
- **Workflows from elsewhere.** Import a .json, a PNG ComfyUI made (the
  graph is in its text chunks — drop it on the tab), or a link (GitHub
  page links are turned into raw ones); API-format prompts load too. Custom
  nodes a community workflow needs that the box lacks are named, and block
  the run. "去哪找工作流" links the official and community collections.
- **Pulling models from the tab.** "全部拉取" gets everything the open
  workflow lacks after one confirm listing each file and the total; "拉模型…"
  takes any Hugging Face file link, guesses the folder from its path
  (Comfy-Org repos use ComfyUI's folder names) and shows the size and the
  box's free space. The box downloads with its own Hugging Face login, read
  there and never sent to the Mac, and resumes a broken download.
- **Half a download is not a model.** curl -o writes under the final name
  as it goes, so a download that broke off (the H3 transformer: 8.75 of
  20.97 GB, connection reset) looked present to a check of names and could
  not be loaded. Every present file is now checked against the size its own
  safetensors header promises; a short one is listed as "只下了 42%" and
  resumed from where it stopped.
- **ollamadiffuser's models in ComfyUI workflows**, through the node pack in
  ollamadiffuser's `integrations/comfyui` (text to image, edit with up to four
  references, video with first frame / audio / control video / LoRA), which
  calls its HTTP API rather than loading its MLX weights; four starter
  workflows in 我的. Qwen first frame → LTX 2.5 clip: 130 s.
- **Ollama's models in ComfyUI workflows** — `scripts/comfy/comfyui-ollama`,
  one node (Ollama · Chat): text and pictures in, text out, from whatever the
  box's Ollama serves (local and :cloud), instead of ComfyUI's LLM templates
  loading another copy of a language model. Tasks: image prompt, video
  prompt, H3 prompt (MiniMax's guide), translate, describe the image. Three
  starter workflows; one Chinese sentence → kimi writes both prompts → Qwen
  first frame → LTX clip, 199 s.
- **What the box already has is linked, not downloaded again.** ollamadiffuser's
  models are MLX conversions ComfyUI (PyTorch) cannot read, but a file it
  keeps in the original format — the LTX IC-LoRAs — and single files in the
  Hugging Face cache are found by name and symlinked into ComfyUI's folder.
- **Memory is shared, not fought over.** A run first stops the Film tab's
  draw/edit servers (they come back on demand); Film and Motion ask
  ComfyUI to let go of its models before they shoot; a run is refused while
  either is shooting.
- **For agents:** `comfy_templates` (with `runnable`), `comfy_run` (template /
  ask / changes / files), `comfy_import`, `comfy_status`, `comfy_stop`. Measured: Qwen Image 2.1 text-to-
  image at 768×1376, 133 s; the same picture edited to night, 192 s.
- ComfyUI is a service in Settings → Backend → 盒子上的服务, started with
  `AIOHTTP_NOSENDFILE=1`: with sendfile on, every file it serves over the
  network arrives without headers (fine on the loopback, which is why it
  looks fine on the box).

### Added — Jev's book shelf, and smaller things from the same days
- **书架 in the Jev tab.** A folder of books (.txt/.md/.pdf/.epub) is listed
  from filenames alone — `书名-朝代-作者` gives the title, dynasty and
  author — and each book is one Choice question to Jev with the shelves as
  options. A probability for every shelf comes back, so a book the model is
  unsure of is set aside rather than filed quietly. About 150 ms and 400
  tokens a book. MCP: `books_scan`, `books_sort`, `books_status`.
- **The TypeSafe key from outside the app.** `TYPESAFE_API_KEY` or
  `~/.typesafe_key` is used first — no Keychain dialog after every rebuild.
- **Voice pickers list the TTS server's own voices** (`GET /voices`), with
  Kokoro's list only when the server can't say. Sixteen Kokoro names had
  folded onto a handful of Qwen3 speakers.
- **The mouse wheel reaches full-screen programs in the Term tab.** SwiftTerm
  never passes the wheel on in the alternate screen; it is forwarded as the
  mouse reports the program asked for (Claude Code scrolls again).
- **Motion's 「停」** (and `film_stop`, which stops Film or Motion): a take
  can be called off; what is filmed stays, 「接着拍」 carries on.
- kinclaw's web UI voice follows Settings → Backend (`STT_ENDPOINT` /
  `TTS_ENDPOINT`); a picture is cut to the film's shape before it becomes a
  first frame; the draw server picks its own step count per model.

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

### Added — Jev: a decision model plays games, one multiple-choice question a move

An eighth tab, grown from the `jev-tetris` example: TypeSafe's Jev answers
typed questions — here, one Choice per move — in about 150 ms, with a
probability for every option and never an illegal one. What the example
learned is the design: *the measuring happens in the program and only the
judgment is left to the model.* Jev reads text and is weak at arithmetic, so
a game does not hand over a board; it lists the legal moves, works out what
each one does, and says it in words — small counts as numbers, larger
quantities as named buckets ("stack 12 rows high (high); surface bumpy").

- **Three games, one shape** (`JevGame`: what it is, how to judge a move, the
  position in words, the options in words, a grid to draw): **Tetris**, the
  example's, ported — every straight drop of every rotation, described by
  lines, holes, height and surface; **2048** — four moves at most and a long
  way to look, described by what merges, how much room is left, whether the
  big tile keeps its corner, how orderly the board is; **Snake** — a choice
  about space: closer to the food or not, and how many free cells lie ahead
  against how long the snake is ("a trap"). Adding a game is writing those
  five things.
- **Players are interchangeable, because the point is the comparison**: Jev
  (the user's own key, typed into the tab, kept in the Keychain, sent only as
  the Authorization header); **Laya**, the open local model of the same kind,
  through `scripts/laya_judge.py`; a local chat model asked the same question
  and told to answer with the option's key; the game's own evaluator, as the
  yardstick; and random, as the floor. The same seed deals the same game to
  all of them. Beside the board: what was chosen, the probability the player
  gave each option, its confidence, the milliseconds, and whether it agreed
  with the yardstick; underneath, the running totals, and for Jev the tokens
  and what they cost.
- Measured on seed 100/101, Tetris: the evaluator 2000 pieces and 796 lines
  and still going; a local chat model 83% agreement at three to four seconds
  a move; Laya, zero-shot, 8% agreement and dead at 23 pieces — which is what
  its own card says to expect, and why it is a player here rather than a
  judge anywhere else. Jev itself is untested from the app: it needs a key
  only its owner can enter. The wire format is the example's, which works.
- Two things the first build got wrong, both about lists. Options were capped
  at sixteen "to bound tokens", which cut the best placement off the end and
  had the yardstick lose a game it should play for ever (451 pieces). And
  moves that *read* the same are one option — a model cannot tell them apart
  — played by a plain tie-break rather than the evaluator's favourite, or
  every model would be quietly playing with its help; but the yardstick must
  judge the moves themselves, so an option carries both.
- **Chess, and games for two** ("可以让jev和laya一起玩chess吗… 对阵那种，在包括大模型"). A
  game can have sides, and any player can sit on either: Jev against Laya, a
  chat model against the yardstick, one chat model against another (a seat
  whose player is 本地大模型 gets its own model menu). The rules are a real
  engine (`JevChessEngine`, no SwiftUI in it so it can be compiled alone):
  castling, en passant, promotion, check, mate, stalemate, threefold
  repetition, fifty moves, dead positions — and its move generator agrees
  with the published perft counts on five standard positions, which is the
  only way to know. The division of labour is the same with more to measure:
  for each legal move the program looks at the opponent's best reply, and one
  recapture past it, and says what it found — what is captured, check or
  mate, what it does for development, and how the material stands afterwards
  ("after the best reply comes out 3 behind in material: it loses
  material"). The players choose among a dozen candidates: a dozen because
  that is what Laya can read at once and both sides must be asked the same
  question; and not the evaluator's best dozen, which would be the evaluator
  playing — every castle, the checks and the tempting captures are in the
  list whether they are good or not. First results: the yardstick mates a
  random mover in 24 moves and draws itself by repetition; Laya, zero-shot,
  cannot mate a random mover in 200; a chat model against Laya was 15 points
  up after 14 moves. Jev needs its owner's key and has not played yet.
- **The box's Ollama can be picked too** ("加盒子ollama可选"). Wherever a chat
  model is chosen — a 本地大模型 seat in the Jev tab, 分镜 in the Film tab — the
  menu is grouped by machine: 本机, 盒子. A seat remembers the machine as well
  as the name ("host|model"), because the same name is on both and the point
  of choosing the box's is that it runs there: its local 35B plays chess at
  1.7 s a move, costs this Mac nothing and no cloud quota (cloud models are
  marked ☁︎). What is picked *automatically* still comes from the configured
  host and this Mac, so adding a machine to the menus changes nobody's
  default.
- **Laya lives on the box now** ("把laya部署到盒子上，这样节省本机资源"). Earlier the
  advice was to keep it on the Mac, because it had no job; it has two now, and
  measured, the box is simply better at it: 23 ms a question on the box's GPU
  and about 45 over the LAN, against 150–490 on this Mac's CPU — and the Mac
  gets back the gigabyte and a half two resident checkpoints were holding. It
  is a sixth row in Settings → Backend → 盒子上的服务 (start, stop, started when
  something needs it), in its own virtualenv under `~/.kinclaw/laya` so that
  the diffusion servers' torch is nobody's to move; with a box configured and
  no address typed in, the app uses the box's. Found on the way: its options
  were being sent as a dictionary, so they reached the model in a different
  order every time and one seed played four different games — a model that
  leans toward the first thing it reads was answering the shuffle. Written in
  order, the same seed is the same game three times out of three. And one
  legal move is no longer a question: a snake in a corridor asked Laya to
  choose among one option and got an error from inside torch.
- `jev_play {game, player, moves, seed}` for her and for agents; it plays at
  full speed, stops at 55 seconds whatever happens, and says so. The board is
  redrawn at most thirty times a second — drawn once a move, a game that
  takes a second took two minutes.
- **中国象棋.** Xiangqi is the fifth game and the second for two. The engine
  (`JevXiangqiEngine.swift`, Foundation only) knows the blocked horse, the
  elephant's eye, the cannon's screen, the palace, the river, the generals
  who may not face each other, and that a side with no move has lost whether
  or not it is in check; its move generator agrees with all 44 published
  perft counts — eleven positions, four plies deep, 6.9 million leaves. The
  players are asked in English and coordinates, a dozen candidates a move as
  in chess; the person watching reads the move under the board the way every
  xiangqi book writes it — 炮二平五, 马8进7, 前车退一 — and the men are discs
  with characters on them, on a board with a river and two palaces.
  The evaluator looks further than chess's does, because it had to: one
  recapture past the reply was enough to make it open every game with 炮八进七,
  cannon takes horse through the screen — the chariot beside the horse takes
  the cannon back, and counting half of that twice looked like winning two
  horses. It now plays the captures out (four plies, either side free to stop)
  before it says how a move comes out. And "has the side any move at all" is
  asked after every reply with a test that stops at the first legal move:
  listing them all cost twice the time, and only looking when few pieces
  were left was wrong — 困毙 happens with a full palace, and the shortcut
  changed the evaluator's own game at move 59. The yardstick mates dice in 7
  moves as Red and 32 as Black; a move costs about 120 ms in a debug build.
  `jev_play {game: "xiangqi", red, black}`.
- `jev_status` looks without touching: which game, who is playing, whether it
  is running, how it stands. `jev_play` deals a new game over whatever is on
  the board, so there was no way to find out that somebody was in the middle
  of one except by ending it.
- **Jev judges film takes too.** Settings → Backend → 片场 · Jev 判断, off by
  default. Jev cannot see any more than Laya can, so the split is the one the
  review already had — the vision model writes down what her body did, and a
  text model judges that description against the plan — with Jev asked the
  same four things as Laya (follows the plan, the activity done properly,
  leaves, how much of her moves), its line under Laya's on the shot card and
  in `film_status`, a purple badge beside the blue one. Choice is the only
  question type this app has seen Jev answer, so a yes-or-no is two options
  and the number is the probability of the yes; "how much" is three options
  and the number is where the probabilities balance between 0 and 2 — which
  makes the two judges' numbers mean the same thing. The description, the
  planned movement and the film's idea go to api.typesafe.ai when it is on,
  and the card says so.
  The first eight takes it read, against what the reviewer had made of them:
  the three that were a different movement from the planned one (hands over
  the head instead of to the chest; frozen; stood up and turned away) it gave
  0.02, 0.00 and 0.28 for "follows the plan", the other five 0.56 to 1.00 —
  and "how much of her moves" came out at exactly 1.0 for the four takes whose
  descriptions say only the arms moved, 0.36 for the frozen one, 2.0 for the
  three with bent knees and shifting weight. Laya gave all eight 0.78 to 0.95
  and called arms-only takes whole-body. Four questions are one request of
  about 430 tokens: the eight takes cost $0.0003.
- **Shown by default; it can be made to count.** A second switch, 让它的判断
  算数（试验）, adds one rule, and only downward: a take the reviewer let
  through is failed (4/10) when Jev reads the reviewer's own description as a
  different movement from the plan (follows < 0.30), and is retaken from the
  same words — the reviewer had no complaint to rewrite them by — within the
  usual retake limit. Jev never rescues a take the reviewer failed; it cannot
  see an extra arm or a changed coat. The model that looks is good at saying
  what it saw and moody about what that amounts to; comparing two pieces of
  text is what Jev is for.
  「只问第二意见」 (and `film_review {opinions_only}`) asks Laya and Jev again
  about descriptions already written: a second a shot, no frames looked at,
  none of the vision model's quota. A judge that is off, or does not answer,
  leaves the numbers it gave before where they are — the description has not
  changed, so they still stand.
- The Jev API call moved out of the arcade into `JevClient` — any number of
  Choice questions in one request, asked one at a time if the server will not
  take several — so a game move and a film verdict are the same code.

### Fixed — a password dialog at every launch, waiting to happen

- The TypeSafe key is in the Keychain, this app is signed ad hoc, and to the
  Keychain an ad-hoc app is its exact bytes: every rebuild is a stranger to
  the item the last build stored, and reading the secret raises "KinClaw Mac
  wants to use your confidential information". The Jev tab read the secret
  when its view was made — at launch — merely to know whether to say 换 key
  or 填 key. Now "is there a key" asks for the item's attributes, which no
  access list guards and no dialog attends; the secret is read once a launch
  and kept; and a read that nobody is there to consent to — a film reviewed
  shot by shot, a tool call — is made with the Keychain's dialogs off, so a
  refusal is an error that says what to do (-25293, seen on the first try)
  instead of a dialog in the middle of somebody's evening. Only 开始 and
  走一步 in the Jev tab may raise it: somebody just pressed them.
- Laya's film questions reached it in a different order at every launch: the
  request was serialized from a dictionary, as the games' once were. One
  description of one take scored 0.09 for "the activity, done properly" on
  one launch and 0.83 on the next. Written out in order now, by hand, and the
  same description gets the same numbers.

### Added — Motion in three dimensions: a set, and a camera that moves

The skeleton route films her from where the reference was filmed, because a
flat skeleton is all it has. The Motion tab's 机位 menu now has three more
cameras — 3D · 固定, 3D · 环绕, 3D · 推近 — and a 布景 beside them:

- **Her body, in 3D** (`MotionPose3D`). Vision estimates seventeen joints a
  frame in three dimensions — a separate guess for every frame, and four
  repairs make a movement of them. *The pose*: the joints are in the pelvis's
  own frame, turned to the camera's by the camera matrix (the matrix, not its
  inverse — the camera looks down −z). Side-on, front and back look alike to
  one camera, and for a few frames the estimate is the depth-mirrored body,
  or has left and right swapped, or is neither; each frame is compared with
  the last one believed, as it is and in its three disguises, the nearest
  taken if a body could have got there in the time, and otherwise the frame
  is dropped and filled in (Brush Knee, ten seconds: 222 as they were, 3
  mirrored, 16 dropped — before this, its right ankle "jumped" a metre and
  the take was refused). *Where she is*: Vision's own estimate of where the
  pelvis is, steady to millimetres sideways and in height and wandering by
  centimetres in depth, so depth is averaged over most of a second. The first
  idea — chain her feet, each planted foot carrying the body — turned a
  sidestep into a metre's walk away from the camera: the relative depth of
  two feet is what one camera sees worst. *Upright*: the reference camera's
  downward tilt is undone from the fact that she starts standing straight
  (10.5° on the first clip). *Feet on the ground stay put*, as a correction
  and no more: a planted foot's drift is taken out of the whole body,
  smoothly; a lock that would drag her more than ten centimetres is let go;
  what the feet ask for fades; both feet down, a small slow turn is allowed.
  "Is the foot down" is asked of heights averaged over five frames, with six
  centimetres' margin and three frames' persistence — asked of raw heights,
  a foot "lifted" for one frame and was locked again somewhere else.
- **A set, in the box's Blender** (`MotionStage`). Headless over ssh: a
  blockout — ground, a pavilion, trees, a bench, a hedge; or open ground — a
  mannequin of capsules keyed to the joints on every frame, and one camera
  move from the first frame to the last however many stretches it is filmed
  in. Rendered as depth, near is white (an emission shader fed by the camera
  distance, view transform Raw), which LTX's union-control LoRA follows as it
  follows a skeleton; 97 frames in 39 seconds. Blender 5.2 lives at
  `~/.kinclaw/blender/` on the box; the script is embedded in the app and
  kept, with its two prototypes, in `scripts/motion3d/`.
- **Her first frame** is the blockout's first frame, plainly lit, re-rendered
  by the image editor as a photograph with her in it. Asked to "turn this
  blockout into a photograph" it composed its own picture — pavilion to the
  middle, hands in her pockets; told that nothing moves, it kept the layout
  and her stance. Then the usual head pass.
- First result: the same woman, clothes and pavilion for 97 frames while the
  camera walked thirty degrees round her, the pavilion sliding behind her
  with parallax — and the stance, the shift of weight and the rising hands
  followed. About three and a half minutes for four seconds.
- **She may walk and turn.** The camera keeps its path round where she
  started and turns its head after her, a second behind. A track in which a
  joint still moves a quarter of a metre between frames after all of the
  above is refused, with a sentence that says to use the skeleton camera —
  the last resort, not the rule it was for the first day.
- `motion_make {camera: static | orbit | push, place: park | open}`.

### Added — two minds at one board

"Why can't Jev beat the yardstick at chess?" Because what it reads about each
move is the yardstick's own two-move search, put into words; nobody beats a
judge by reading the judge's notes, and the moves it chooses differently are,
by the only measure either has, worse (46% agreement, mated in 54). Jacky's
answer: Jev should do what Jev is for, and a big model should judge. So:

- **Jev＋大模型** and **Laya＋大模型**: the fast judge rates every option as
  before; at 0.75 or more for its favourite, that is the move and nobody else
  is asked; under that, its best three go to a chat model — any Ollama model
  on this Mac or the box — which is told that the descriptions come from a
  shallow search. It may think first if the tab's 大模型先想再答 is ticked:
  off by default, because a local 9B thinking about one chess move took
  forty-four seconds.
- The chat model is shown **the board**: a game can now say its position
  (`JevGame.position`) — chess as FEN, a diagram and the moves so far; xiangqi
  as FEN, a diagram in the men's own characters, and the moves as a book
  writes them. Shown only the words, two minds would know what one does.
- If the slow judge does not answer, the fast one's choice stands and the
  game goes on.

### Changed — xiangqi: what it takes for a reader to beat the evaluator

"Jev＋大模型 still cannot win, but the chat model alone can." One game had
said so. Replayed outside the app — same seed, same model, same words — the
chat model was mated in 58: a chat model's answers are drawn at random, and
one game is an anecdote. Six seeds each, the box's 35B as Red against the
evaluator, no thinking:

    what the reader was given                          won  drawn  lost
    the words (the app's 本地大模型)                     0     1     5
    the words and the board                              0     2     4
    + what each move threatens, judging rules in order   0     1     5
    + moves the words already condemn taken off the list 0     5     0*
    + the words look three plies on, not one             3     3     0

    * a sixth game was unfinished at move 82

- **Why it lost.** Not steadily: by one move a game whose own description
  said "it loses material" — preferred, typically, to a retreat, because the
  rules also say to avoid retreating. Saying the rules in strict order did
  not cure it. So **the program no longer asks what it already knows**: for
  a reader, moves that come out worse in material than another move on the
  list are taken off it, and a forced mate is the only option offered. What
  is left to judge is what measuring cannot settle. Losses became draws.
- **Why it then won.** A reader beats the evaluator only by knowing
  something the evaluator does not, and the program is where that comes
  from: for a reader the words now look three plies past the move (plain
  alpha-beta, captures settled at the end) where the evaluator that plays
  looks one; they say what a move threatens, and when it repeats a position;
  and the moves that look best further on are on the shortlist. The
  evaluator that *plays* is untouched — `JevGame.prepare(reader:)` tells a
  game who the next options are for — so it is still the same yardstick, and
  its own games came out move for move as before.
- In the app, the box's 35B against the evaluator: mate in 35, then a draw
  by repetition it was told about and walked into anyway. Jev has not been
  tried on this yet (its key locks with every rebuild).
- **Chess the same way**, and more plainly still: the box's 35B as White
  against the evaluator, six seeds — with the old words 0 won, 1 drawn, 5
  lost; with what a reader gets now 5 won, 1 drawn, 0 lost. The engine gained
  the same three things xiangqi's has (captures settled, alpha-beta to three
  plies, what a move threatens), stalemate counted as the draw it is; its
  perft counts are unchanged on all five positions. In the app: mate in 56.
- The app is compiled optimized, Debug or not: looking three plies on took
  eleven seconds a turn unoptimized and a fifth of a second optimized.

### Added — 五子棋, and what did not transfer

Gomoku, free style, on 15 by 15: the third game for two, and the first where
the chess recipe did **not** work. Worth writing down.

- The engine asks one question — *what does a stone on this point make along
  this line?* — of the nine points through it, and answers by trying rather
  than by listing shapes: a line is a four if one more stone makes five, an
  OPEN four if two different stones would, an open three if one more stone
  makes an open four, and so on down. Broken shapes (X·XX) come out right
  with nobody naming them; all 3⁹ answers are kept. Checked against the
  shapes every player knows.
- The words say what a player would say: "makes a four and an open three at
  once: a winning double threat", "takes the point where the opponent would
  make an open four", "makes an open three, which threatens an open four".
  The evaluator that plays is the classic one-look one — what the stone
  makes and what it denies — and is the yardstick.
- **The recipe from chess: looking further, saying more, and not asking what
  the program already knows.** For a reader the program also finds forced
  wins by continuous fours, searches four stones on among each side's best
  few points, and takes off the list the moves it can already see lose. The
  box's 35B against the evaluator, six seeds each colour: with plain words
  0 won, 0 drawn, 8 lost; with all of that, 1 won, 1 drawn, 10 lost. It
  stopped losing in twenty stones and started losing in seventy, and that
  was all.
- **Why it did not work.** At chess the yardstick is a two-ply search that
  can be out-seen. At gomoku the one-look evaluator is already most of the
  game — it blocks every four and every open three the move it appears —
  and a four-stone beam search past it is not enough to out-see it. The
  claim from the chess work survives, but with its condition showing: a
  reader beats the yardstick only when the words know more than the
  yardstick does, and here they do not yet.
- **深算** is a new player, in every game: the program itself, following its
  own deeper opinion of each option (three plies at chess and xiangqi, four
  stones at gomoku) rather than the evaluator's. It is the top of the ladder
  随机 < 启发式 < 深算 that a model can be placed on — and at gomoku it is
  not above 启发式, which is the same finding again.

### Added — 21 点: a test of judgment about risk, with a yardstick that is right

Chess taught two things about testing a model with a game: one game is an
anecdote, and a yardstick that is only a shallow search says little about
who disagrees with it. Blackjack has neither problem. Every hand is its own
game and two hundred are a minute; and what each action is worth is worked
out exactly (an endless shoe, the dealer stands on every 17 — the numbers
agree with the published tables to four places: hard 16 against a 10 is
−0.5404 to stand and −0.5398 to hit; a dealer's 6 busts 42.3% of the time),
so a disagreement with the yardstick is a mistake of a known size.

- The player is told what can be measured at a glance — how often the dealer
  busts from that card, how often one more card busts the hand, how often
  standing wins — and is NOT told what each action is worth: a program that
  knows that has nothing left to ask. Weighing a 60% chance of busting
  against losing three times in four by standing is the judgment. No
  splitting, no surrender; a natural pays three to two.
- The number to read is **因为选错少拿** — chips given up by choosing worse
  than the best action, summed over the session — which takes the luck of
  the cards out. Same 200 hands, seed 7: the yardstick 0; the box's 35B 39
  in 139 decisions (79% agreement); dice 787, broke at hand 187; Laya 990,
  broke at hand 144, agreeing 6% of the time — worse than dice, which is
  what choosing the same wrong thing every time looks like.
- `jev_play {game: "blackjack", player}`.

### Added — a film can be deleted

Eight films on the shelf, five of them experiments nobody will watch again,
and the only way to be rid of one was Finder. There is a trash button on the
film itself, one on each row of the library under the pointer, and 删除整部影片…
in the row's menu. All three ask first, and what they do is move the film's
folder — storyboard, stills, clips, the takes set aside, the cut — to the
Trash, where Put Back still works: a film is a quarter of an hour of the
box's time and sometimes the only good take of something. The film being
shot is not offered; nothing is while the studio is reviewing.

Laya's card says where Laya runs now — on the box when there is one, the same
service the Jev tab plays against — instead of "on this Mac", which stopped
being true when it moved.

### Added — Motion: a movement from a real performance, performed by her

An evening went into asking a video model for tai chi in words, and what it
gave back, however the asking was refined, was a woman moving her arms; the
reviewer built that evening said so itself ("腿部没有屈膝下沉和重心转移"). Its
owner's conclusion: "似乎这种思路是错误的… 用已存在的视频". He was right, and it did
not need a face swap.

- **A seventh tab, Motion.** Drop in a video of somebody doing the thing — one
  person, whole body, a camera that mostly stays put — say where she is and
  what she wears, and she does it. Only the *skeleton* is taken from the
  reference: Apple's Vision tracks the body frame by frame on this Mac
  (`MotionPose`; a body in 241 of 241 frames of a performer 65×144 pixels
  tall), and it is drawn as the OpenPose stick figure that LTX's IC-LoRA
  union control was trained to follow. Nobody's face, clothes or garden comes
  along, which is the difference from a face swap — and the swap models worth
  having are non-commercial anyway.
- **Her starting still** is an edit of her anchor shown the reference's first
  frame for the pose and the distance, then given her face back by the head
  pass; the skeleton is then *fitted onto her* (least squares on shoulders,
  hips and knees, one scale) because an editor's idea of "the same position in
  the frame" is a little lower and a little to one side.
- **As long as the reference.** Filmed in ten-second stretches, each starting
  on the last frame of the one before and following the next ten seconds of
  the same performance, joined end to end with no dissolve — the joins are
  continuous in picture and in motion already. Measured on the box's everyday
  q4 model: 4 s in 97 s, 10 s in 273 s (q8: 120 s for 4, no visible gain), two
  tens joined with no seam to be found frame by frame. The first clip made this
  way was recognisably tai chi — bow stance, a hand rising, both arms pushing,
  knees bent throughout, feet planted — in her park, in her padded jacket.
- The player shows 成片 · 第 N 段 · 原视频 · 骨架, so what she did can be held
  against what she was shown. `motion_make` / `motion_status` for her and for
  agents. Where the movement came from is kept with the take (`credit`) and
  shown under it: the first reference was a Creative Commons tai chi form, and
  CC BY asks to be named.
- **A link instead of a file** ("我可以粘贴youtube连接吗"). Paste an address and
  the tab reads what it is *before taking any of it* — title, author, length,
  licence — and shows it. A Creative Commons video can be fetched, and the
  credit line fills itself in. Anything else is somebody's work under the
  site's standard terms, which do not allow taking it and making something
  from it: the tab says so, and fetches only once 我有权使用这段视频 is ticked
  (`motion_make {url}` refuses likewise unless the user has said, in the
  conversation, that it is theirs). Picture only, 480 lines at most, an mp4
  that needs no merging — a skeleton does not need more. The app installs
  nothing: it runs the `yt-dlp` already on the Mac (`kinclaw.motion.ytdlp` to
  name one), and when that one is too old for the site — YouTube breaks old
  ones every few months, and "HTTP Error 403" is how it says so — the error
  carries the line that fixes it.
- **A topic instead of a link** ("我给主题，智能找符合的视频，然后我勾选就可以用").
  Type 八段锦 and the tab finds references that can be used *and* tracked:
  the writer model turns the topic into three searches for one person
  demonstrating it (the topic's language and English — a bare topic finds
  talks, history and group classes); YouTube is searched with its Creative
  Commons filter on, read flat, nothing fetched; and the model that can see
  looks at the thumbnails, six at a time with their titles, and says whether
  each is the thing asked for and how good a reference it would make out of
  ten — one person, whole body, a steady camera — with a sentence of why.
  The grid is sorted by that; 用这个 reads the real licence field (a filter is a
  claim, the field is the record), fetches it and fills in the credit. About
  seventy seconds from a topic to fourteen ranked videos; a group class scored
  3, a lone performer head to foot 9. `motion_find {topic}` for her — she is
  told to show the list and let the user choose.
- A stretch says how long it has been running. Ten seconds of film is five
  minutes of one unchanging sentence, and its owner took the second stretch
  for a hang ("是不是卡住了啊"); the line now counts up beside what the last
  stretch took. And the model is no longer streamed from disk when the box
  has memory to spare (`low_ram=false`): 266 s for ten seconds against 295.
- Needs, on the box: ollamadiffuser with the control-video mode (below) and
  `ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors` (654 MB, LTX-2
  community licence) under `~/.ollamadiffuser/models/ltx-loras/`.

### Changed — a film is one place and one movement, not four postcards

"她在公园里打太极" came back as a pavilion, a stone house, a lake she stood
waist-deep in and a wood — in two pairs of shoes, doing four things none of
which was tai chi. Then, with the place fixed, as four unrelated poses in one
place. Both were the pipeline, not the models:

- **One place, and the first shot is its master.** A storyboard now has a
  `place`, said once, and its first still is always a wide frame of her in it.
  Words alone do not hold a location from one still to the next; a picture
  does. The edit server took one reference image; it takes several now
  (ollamadiffuser: `images` on `/api/generate/img2img`), so a still can be
  made from *who* (her anchor) and *where* (another frame) at once.
- **Every shot starts where the last one stopped.** The previous clip's final
  frame is pulled out, a model that can see (the storyboard's writer when it
  has eyes — kimi does) puts her pose into words for the next camera and
  rewrites the planned movement to carry on from it, and the next still is
  that pose from the new angle: a match cut. It has to be read rather than
  planned, because the video model does not stop where the storyboard says —
  asked for a weight shift, it ended on one knee with her hands behind her
  back, and the next shot now begins there. "Keep her pose" alone is not
  kept (from behind, her raised arms came back down); the pose in words is.
  The reader is told what the film is *about*, too. The first version was
  not, and directed faithfully from what it saw: the video model ended a tai
  chi shot on a stray step, so the next shot "continues walking forward", and
  so did the one after — a perfectly continuous film of a woman leaving. And
  the master rides along as a third picture: three links into a chain without
  it, a padded jacket had become a jumper, because every frame of video is a
  slightly worse witness to the clothes than the one before.
- **The place and the clothes are not repeated in words once a picture carries
  them.** They were, at first, and every still came back as the same
  full-length wide shot whatever the storyboard asked: a sentence listing a
  pavilion, a willow, trousers and shoes can only be satisfied by a frame
  with all of them in it. Left to the picture, "medium shot from her left
  side, waist up" is one.
- **The brief says who reads it.** The writer was a good writer addressing
  the wrong reader: "hands pushing forward as if moving water" put her in the
  lake, "the opening gesture of tai chi" was a T-pose, "sound of distant park
  keepers sweeping" walked a man into the last frame. Storyboards are now
  asked for a `framing` per shot, the body described limb by limb, only what
  is in the frame, no similes, no names of techniques, ambient sound that
  names nothing not already visible, and a static camera whenever her body
  moves (asked for both, the video model trades her movement for a zoom).
  The brief's examples are from another subject than the one most likely to
  be asked for: a writer copies an example that fits. And because a simile
  still slips through about one shot in four — and gets drawn; there was a
  ball — "as if …" clauses are cut from what the models are sent.
- **Each shot's words can be rewritten.** 改提示词… on a shot opens its camera,
  pose, movement and voice-over; what is shown is what the shot was actually
  made from (the pose that was read, the movement that was played), and what
  is changed is used as written — nobody's model rewrites a director. Chinese
  is turned into the literal English the models read. Then 只重拍这一个, or
  从这个往后都重拍 — later shots were filmed from this one's last frame, and
  a new ending leaves them starting from a moment that no longer happened.
  A change to the voice-over alone is still two seconds. `film_reshoot` takes
  `framing` and `following` for the same, and `panel_show {mode: film, film,
  shot}` opens a shot's words from a conversation ("我想改第三个镜头").
- **Nobody has to write a prompt.** Two ways not to:
  - *A direction in a sentence.* 改这个镜头… opens with one field, 方向: "手放下来
    的时候再慢一点，脚不要动，不要转身". The model that can see looks at the
    current take and rewrites what has to change — and only that — then the
    shot is taken again. Measured on the shot that prompted it: before, she
    lowered her arms, turned side-on and stepped off; after, four seconds of
    arms coming down, feet planted, facing the lens throughout. The sentence
    stays on the shot as its `wish`, and whoever writes or judges the shot
    afterwards is told it outranks the plan. `film_reshoot` takes `direction`,
    so it can be said to her in conversation. The shot's actual words are
    still underneath for anyone who wants to type them, and typed words are
    still used as written.
  - *把关：N 次*, in the composer. Every take is watched — four frames across
    it, and the master for the place and the clothes — against the plan: does
    she do what the film is about or drift into something else; is anything
    there that should not be; does the camera do something wild; are the
    place and the clothes still the master's. A score out of ten and, under
    seven, a sentence on what is wrong and rewritten words; the shot is taken
    again, up to N times (one by default, 把关：关 for none), and the
    best-scoring take is the one the film uses — a worse retake does not
    replace a better first try. Asked about two takes of the same shot by
    hand, it gave the one where she turns and walks off 4/10 ("第四帧她转身走掉，
    完全偏离太极动作计划") and the one made to the direction 7. About ten seconds
    a look; a retake is two and a half minutes. The verdict is on the card.
  - *The reviewer reports facts; the app decides.* Its first form gave a mark
    out of ten and was a mood: three shots in four sent back, "ok: false,
    score: 7", a take marked down because its camera was not the master's.
    It is now asked only what it can plainly see — did she leave, did somebody
    arrive, is anything deformed, did the camera run off, did the clothes or
    the place change, did her face, was the user's wish ignored — and the
    score is arithmetic on the answers. On four takes whose faults were known
    it named both walk-offs, with the frame they happen in, and passed the
    good take three times out of three. What it cannot do is faces: shown a
    profile that turns to the lens as somebody else, it said nothing had
    changed. That needs a face-comparison model, which this Mac does not have.
    (And a model that thinks aloud answers, argues with itself, and answers
    again — the reply is read for the last JSON object that parses, not for
    everything between the first brace and the last.)
  - Found on the way: a direction given in conversation was accepted,
    acknowledged and dropped. `done?(reshoot(…))` reads as "reshoot, then tell
    whoever asked" and means "if nobody asked, do not reshoot" — an optional
    call does not evaluate its arguments, and the tool asks for no callback.
- **Her face stays hers.** "三脸也变了啊" — and cropped out and lined up beside
  the anchor, it had: in a full-length wide shot at 704 pixels her face is
  about fifty pixels across, and at fifty pixels neither the editor nor the
  video model holds an identity. The woman in the first three shots was nobody
  in particular, a little older in each clip. Asking for "medium shot, waist
  up" did not help, because the two pictures the editor was shown were wide
  shots and it composes what it is shown. So the references are now **cropped
  to the shot's framing before they are sent** — the camera is set by a
  rectangle, not by an adjective — and **her face is blurred out of every
  reference but the anchor**, because the last frame of a clip carries a face
  that has already drifted and with it in view the editor copies that one.
  Measured on one still, three ways: references as they were, a wide shot,
  face 57 px, not her; cropped, waist up, 128 px, a sharp portrait of the
  wrong woman; cropped and blurred, 138 px and recognisably her, same jacket,
  same park. (`FilmReference`, Vision for the face, Core Image for the rest.)
  Storyboards are asked to stay close after the opening shot, which itself is
  now full-length rather than wide; and the reviewer is shown her portrait
  and told how many pixels wide her face is, with a closer camera as the fix.
- **The camera is the film's, not her face's.** The paragraph above went too
  far, and its owner said so twice: "不要为了保持脸就拉近镜头" and "拉近镜头完全就不是
  太极动作了". It had. To keep her face large the brief told writers to stay
  close after the opening shot, anything unrecognised was cropped to the
  waist, and the reviewer's cure for a small face was a closer camera — and a
  film of tai chi became a film of a woman moving her arms. All three are
  gone: the references are cropped only to the framing the storyboard asked
  for, the brief asks for the framing the *action* needs (the whole body, in
  every shot, for anything done with the whole body; variety from the angle,
  not the distance), and the reviewer never moves the camera for a face.
  Her face is looked after where she stands instead — a **head pass**: when
  the face in a new still is under 110 pixels, the head is cut out and
  enlarged, the editor redraws the face from her anchor, and the face is set
  back into the still. Not as it comes: asked to change only the face, the
  editor hands back a fresh head-and-shoulders portrait, and pasted in as it
  was that was a face twice the size of the head it landed on. The face found
  in its answer is scaled and moved onto the face found in the still, and
  only a feathered ellipse inside the face is taken. On a full-length still
  with a 66-pixel face: sharper, the anchor's brows and eyes, no seam at the
  size it is shown. The still as first drawn is kept as `shot-NN.drawn.png`.
- **The action is the film.** "要强调动作啊." Four shots had scored ten out of
  ten in a film its owner watched and said was not tai chi, because the
  reviewer only looked for things going wrong and nothing had: nothing much
  had happened either. Three changes. Stills catch her *in the middle* of the
  movement — a wide stance, knees bent, weight on one leg, arms partway
  through their arc — because the video model continues the energy of its
  first frame and a neutral standing pose becomes a small gesture or a walk.
  `motion` leads with the movement and says what the legs, the weight and the
  torso do as well as the arms, with the constraints (on the spot, static
  camera, ambient sound) cut to a few words at the end — they had grown to
  outweigh the action they were protecting. And the reviewer now reports
  whether she performs the planned movement (no / partly / yes), whether she
  is frozen, and how much of her body took part against how much the plan
  called for; falling short costs points and sends the shot back with a
  larger movement written for it.
- **Tried: a text decision model as the judge** (`convaiinnovations/laya`,
  0.4B, runs here in ~200 ms). It cannot see, so the split was kimi describing
  what her body does and Laya judging the description against the plan. Kimi's
  descriptions were exact ("knees straight, weight stays centred, feet do not
  move"; "turns to the side, steps forward, and walks off to the right").
  Laya's readings of them were not: the walk-off scored 0.36 for "does she
  walk away", arms-only movement 1.88 of 2 for "her whole body moves", and
  "is this tai chi" sat between 0.81 and 0.92 for four of six takes whatever
  they showed. Its own card says as much — a base to fine-tune, not a
  zero-shot judge — so the facts are asked of the model with eyes and the
  arithmetic is done in code. The descriptions it would need to learn from
  are the ones now written for every take.
- **A shot can be watched the moment it is filmed.** Under the player: 整片 ·
  镜头 1 · 镜头 2 …, and a click on any finished shot's picture does the same;
  while a film is still being made the player shows the latest shot instead of
  nothing for a quarter of an hour. (Its first form was a small "看整片" beside
  a caption, and having clicked a shot its owner could not find the film
  again: "却没有最后的合成版了".)
- **Laya's numbers are shown beside the verdict** — asked for, so that they can
  be watched rather than argued about. The reviewer now also writes down what
  it *saw* her body do (`saw`, two plain sentences), and that, with the plan,
  goes to Laya behind `scripts/laya_judge.py` (a forty-line FastAPI wrapper on
  127.0.0.1:8005, `kinclaw.film.laya` to point elsewhere): 按计划 · 动作到位 ·
  走掉 · 幅度. Displayed, not obeyed; when the service is not running the card
  has one line fewer. It is **off by default**: Settings → Backend → 片场 · Laya
  打分 has the switch, the address, a live dot for whether the service answers,
  and the command that starts it (`settings_open {tab: "backend"}` lands
  there). And the numbers are on the picture now — 把关 N in green, amber or
  red, Laya's 动作到位 in blue — because the first place they were put, a ninth
  line of small grey text below the fold, was data nobody saw ("我怎么没有看见"). **重新把关** on a finished film (`film_review`) reviews
  every shot again without filming anything, which is how films made before
  tonight get their action verdicts and their Laya line.
- **Never from behind, and she does not turn round.** A shot that opened on
  her back and had her turn gave the video model a side of her it had never
  seen: it invented a face, and an open jacket over a white top, and because
  the next shot starts from the last frame, that became her outfit for the
  rest of the film. It is in the brief and in the rules every rewrite is
  given. Two more things from the same run: a model describing a frame adds
  what she is wearing however it is asked not to, and those words outrank the
  master picture, so "wearing …" is cut from a pose the way "as if …" is; and
  a shot that scores under five after its retakes is not carried on from —
  the next one is a fresh setup from the master, a cut away, which is what an
  editor does with a bad take. A still that predates the latest take of the
  shot before it is drawn again, too: redoing shot 2 alone used to leave shot
  3 opening on a moment that no longer happened.
- **What is left is the video model's.** It does not do slow, controlled
  choreography: asked for tai chi it gives unhurried arm movements and the
  occasional step nobody asked for, and with the place held by three pictures
  the camera mostly stays wide whatever `framing` says (a close-up comes back
  as a medium shot). A shot is about 2 min 40 s now — reading the last frame
  and a three-picture edit on top of the filming.
- **旁白：…** in the composer picks the voice-over's language — 自动 (the
  idea's own), 中文, English, 日本語, Español, Français, Italiano, Português,
  हिन्दी, or none. It is told to the writer, which had started answering an
  English brief in English, and it picks the voice: a Kokoro voice reads one
  language, so her usual voice is used only when it is a voice of that
  language. `film_make` takes `narration_language`.

### Fixed — Settings would not open, and the Film tab's composer was one row too few

- **Settings… did nothing.** Both doors — the 🦞 menu's Settings… and the gear
  in the panel — sent AppKit's `showSettingsWindow:` up the responder chain.
  On this macOS the action is *accepted* (`sendAction` returns true) and no
  window is ever made, which is the worst of both: nothing to see and nothing
  to catch. It was not a crash, not a hang, and not the new card in the Backend
  tab — all three were ruled out before the cause turned up, by listing
  `NSApp.windows` from inside the app. Both doors now post
  `.kinclawOpenSettings`, and the panel answers it with SwiftUI's own
  `@Environment(\.openSettings)`.
- **`settings_open` and `panel_show {mode}`** — two panel tools that came out of
  the hunt and stayed. The first opens Settings and reports the windows the app
  actually has, so "did it open" is a fact rather than a screenshot; the second
  brings the panel up on a named tab (chat, cowork, code, term, web, film),
  which is how any tab can now be looked at without a synthetic click.
- **The Film composer is two rows.** In one, at the panel's usual width, the
  idea field had room for three characters and the button that starts
  everything was an ellipsis. The sentence and 开拍 have the first row to
  themselves; who writes the storyboard, how many shots, and whether she is
  the lead sit underneath.
- **The kernel asks for Accessibility once per build, not at every launch**
  (kernel side; see its changelog). Every relaunch of the panel restarts the
  kernel, and an ungranted — or, after a rebuild, orphaned — grant meant a
  system dialog each time.

### Added — the box's model servers, started when needed and stopped when asked

They were started by hand in an ssh session and lost at the next reboot,
which is how a film gets four minutes in before anybody finds out the edit
server is not there.

- **They do not need to be resident, and the numbers say which ones matter.**
  Measured on the box: the three diffusion servers cost five to eight
  gigabytes idle between them and answer three to six seconds after being
  started, so keeping them up is cheap and so is not keeping them up. The
  expensive resident is a language model left in kinfer — thirty-five
  gigabytes for a 35B, with no endpoint to unload it — and that is exactly
  the memory the high-quality video model needs.
- **Settings → Backend → 盒子上的服务**: each service with what it runs, where
  it answers, what it costs, a status light and a Start or Stop button; the
  box's free memory underneath. `draw`, `edit`, `film`, `filmHQ` (the q8 video
  model) and `brain` (kinfer, through its own launchd job).
- **Started by whatever needs them.** A draw, an edit or a clip asks for its
  server first, and if it is not answering brings it up over ssh and waits
  for it to: a picture requested with the draw server stopped came back in
  twenty seconds, start and model load included. Off with one switch.
- **Over ssh, with the key the user already has.** `BatchMode`, so it works
  silently or fails at once and never prompts; no `accept-new`, so a box this
  Mac has never spoken to is refused in ssh's own words rather than trusted
  on the user's behalf. Started the way they always were — `nohup`, nothing
  installed on the box — with the two things that go wrong doing that over
  ssh put right: Homebrew is not on a non-interactive `PATH` (and the video
  model refuses to load without ffmpeg), and a server with no log leaves no
  evidence, which is why nobody can say for certain what killed the edit
  server earlier in the day. Logs go to `~/Library/Logs/kinclaw/` on the box.
  Model names and paths are stripped to characters a shell cannot act on
  before they go into a command on another machine.
- **`box_services`** — status, start, stop — so "把 kinfer 打开" is something
  she can be asked, behind the approval it should be behind.

### Added — a voice-over, from the user's own TTS

- **A line per shot, spoken on this Mac.** A storyboard can give a shot a
  `narration` — a storyteller's sentence, not a caption, short enough to say
  in three seconds — and the Kokoro already running on this machine says it:
  the same request the companion's voice uses, field for field, because
  `voice` instead of `speaker`+`language` is how Chinese gets read out as
  "Chinese letter, Chinese letter". About a second and a third a line.
- **Over the shot, not against it.** The line goes on a track of its own a
  quarter of a second into the shot, and the shot's own sound — the waves,
  the rain LTX wrote — sits at a third under it, carried through the
  dissolves at whatever level each side of them is at.
- **Rewording a line films nothing.** `film_reshoot` given only a
  `narration` speaks it and cuts again: two seconds, against a minute and a
  half to roll the shot. The old take of the voice is kept.
- **Checked with the other half of the audio stack.** The finished film's
  mixed audio, pulled out and given to the local SenseVoice, came back as all
  four lines in order — 「黄昏的时候,他一个人走到海边,风很大还很近。他回过头
  笑了一下,太阳落下去,他没有走。」 — the only differences homophones (她/他,
  海/还), which is what a clear voice over quiet waves transcribes as.

### Added — a finishing pass, and a say in who writes the storyboard

- **精修 (q8).** Measured against the everyday model on the same still, prompt
  and seed, four seconds at 704²: **104 s against 519 s**, about 45 GB while
  it works, a little cleaner in faces and fabric, the same composition and
  motion. So drafts stay on q4 and a shot already approved can be filmed
  again on q8 — a button on the shot, `hq` on `film_reshoot`. It refuses,
  saying why, when kinfer is up or the box is short of memory.
- **分镜：…** in the Film tab: who writes the storyboard. 自动 asks the Ollama
  the app is pointed at, then this Mac, and takes the most capable chat model
  it finds — ornith on the box while kinfer is up, kimi on this Mac when it
  is not; naming one pins it, host and all, since the same name can exist on
  two machines. `film_status` says who it would be.

### Added — Film: one sentence in, a short film out, on your own machines

The shape of Sora, not its model. What the box does is a four-second clip at
704 pixels in about eighty seconds; what that cannot be is a twenty-second
take with convincing physics. So a film here is what a film has always
been — a list of short shots, cut together.

- **A sixth tab, Film.** Say what you want to see; the brain the app already
  uses writes the storyboard — a title, a look every frame shares, and a few
  shots, each a frame to draw and what moves in it — and the studio gets on
  with it. Built around the wait, because the wait is the product: the
  storyboard appears at once, each frame turns up as it is drawn, each clip
  as it is filmed, and the cut arrives at the end. Everything on screen is
  what is on disk. A library down the side; any shot can be redone.
- **She can be the lead, and stays herself.** With her in it, every still is
  an *edit* of her anchor portrait — the only thing that has ever kept a
  generated person the same person from one picture to the next — so she is
  recognisably her in every shot. Without her, stills are drawn from the
  description.
- **Stills are filmed, with sound.** Image-to-video, so a clip is that frame
  moving, and LTX writes audio along with the picture: measured on clips it
  had already made, real content at −15 to −28 dB with harmonic structure,
  not noise. It had been thrown away until now — stripped for the loops,
  muted in the panel — and the shot's `motion` ends by saying what it should
  sound like.
- **The cut is AVFoundation's**, because the app has no ffmpeg to call: two
  video tracks and two audio tracks, shots dealt alternately between them —
  a dissolve needs both pictures to exist at once — each dissolving into the
  next over 0.4 s with the sound faded across.
- **Made to be interrupted.** Every step is written to `film.json` as it
  happens; a film being shot when the app quits is picked up at the next
  launch with its finished shots intact, and a reshoot keeps the old take
  beside the new one. If a shot fails, the rest are still cut: three good
  shots is a better answer after ten minutes than nothing.
- **She wears one thing per film.** Each still is an edit of its own, and
  left to themselves they dressed her differently every time — a long white
  dress walking the sand, a beige one at the water's edge, which reads as two
  women or two days. A storyboard now says what she wears once, in `wears`,
  and it goes into every frame she is in.
- **The first film**, 「海边的黄昏」: four shots, fifteen seconds, 704×704 at
  24 fps with sound — she walks away along the waterline, the wind lifts her
  hair and she brushes it back, she turns to the camera and smiles, she sits
  hugging her knees as the sun goes down — and is recognisably the same
  woman in all four. One shot failed on the first pass (see the ollamadiffuser
  note below), the other three were cut anyway, and `film_reshoot` filled
  the gap and cut again, keeping the three-shot version beside it.
- **One road from a sentence to a film.** The tab's button and `film_make`
  given only an `idea` are the same function: the studio writes the
  storyboard with a local brain and makes it. Two things that road taught on
  its first real use. The request as first written — JSON mode on, thinking
  left on — had not answered after **three minutes** on kimi, because a model
  that reasons first does all of it before the first byte when nothing is
  streamed; with thinking off and the shape merely asked for it is sixteen
  seconds, and the storyboard was better than the one written by hand to test
  the pipeline. And the writer is **discovered, not assumed**: there is no one
  "current brain" to read, and the obvious default — kimi on this Mac — is not
  there at all when the app is pointed at a kinfer on the LAN, which answered
  `no model matches` behind an error message that hid it. The configured host
  is asked what it has (ornith, here: eleven seconds), then this Mac, and the
  server's own words are what a failure says.
- **A service that goes away pauses the film.** On the second film the edit
  server died after the first still — the box was holding a 35B model, a
  video generation and a 43 GB file reassembly at once — and every remaining
  shot failed in two seconds, leaving a one-shot "film". A shot that could
  not reach its server is now not a failed shot: the film stops, says which
  service it could not reach, keeps what it has, and carries on from there
  (`film_reshoot` without a shot, or 接着拍 in the tab).
- **`film_make`, `film_status`, `film_reshoot`** — the brain writes the
  storyboard as the tool's arguments, the way it writes a motion, so "拍一个
  她在雨夜撑伞走的短片" is something she can be asked. Films live in
  `<art folder>/films/<title>-<stamp>/`.

### Added — things in her hands, and somewhere to sit

The part of "props and interaction" that needs to know nothing about the
photograph. That the sofa is *there* and the railing *here* is a harder
problem and a separate one; these are the things she brings with her.

- **Five things to hold** — a mug, a book, a phone, an umbrella, a flower —
  built from a few primitives rather than loaded, so there is no asset to be
  missing, and lit by the same lights as she is. Each has a way of being
  carried, written in the pose language, and a habit: she sips, keeps her
  head down over the page, glances up from the phone, smells the flower.
- **Placed by where her hand ends up, not parented to it.** Hand bones are
  oriented differently on every model, so the thing is put at the end of her
  forearm once the frame's pose is final and turned by what it *is*: a mug
  and an umbrella stay upright whatever the wrist does, a page and a screen
  face her eyes.
- **`sit`**: a stool appears under her and she sits on it, or she kneels on
  the floor; walking anywhere stands her up. Seated is a slider in the pose
  language too, so a motion the brain writes can sit her down. The seat's
  height is her own shin and ankle, so her feet reach the floor.
- **A skirt is cloth, so seated it is treated as cloth.** Sitting exposed her
  again, and worse than crouching had: a spring bone pulls back towards the
  direction it was modelled in, which for a skirt is straight down — where
  her thighs now are. Colliders push the panels out, the spring pulls them
  back, and the front of the skirt settles standing up off her lap like a
  fan. Cloth has no such spring. While she sits, the hip-hung joints lose
  their stiffness and gain weight and drag, and the skirt lies over her
  thighs the way fabric does; standing, they get their own settings back.
  She also sits turned three-quarters to the lens with her knees together.
- `avatar_move` takes `hold` and `sit`, together if wanted ("坐下看会儿书").

### Added — a mood is a face, a way of standing, and things she does

A mood used to be one of five face presets, switched. Nobody's face works
like that, and nobody's feelings stop at the neck.

- **Each mood is four things**: a face — a *blend* of expressions, eased; a
  way of standing, written in the pose language and laid lightly over the
  idle; how much she moves; and something she does now and then. Worried is
  sad eyes, head a little down and hands that have found each other and will
  not keep still. Sleepy is a hanging head and lids half way down, and every
  half minute or so a yawn — eyes shut, mouth open, both arms stretched
  overhead. Curious leans in with her head tilted. Happy cannot keep still,
  winks once in a while, and arrives with a little hop — once, not every
  time a reply repeats the mood. Gentle folds her hands in front of her.
- **Open eyes.** On a VRoid face "relaxed" and "happy" are smiles with the
  eyes *shut*. Half of either — the first weights tried — is somebody who is
  not looking at you, which is no way to spend the mood she is in most. A
  fifth of each is a soft look.
- **Expressions are asked for the way the model spells them.** A VRM 0.x
  model's "Surprised" is a custom clip with a capital S; asking for
  `surprised` got nothing, silently.
- **One pose layer.** Moods, the built-in acts and the motions the brain
  writes all go through `layPose`, so they agree about what a raised arm is —
  and each owns only the body parts it names. A motion that says nothing
  about her legs leaves them alone; it used to pin everything it did not
  mention to rest.

### Added — she changes clothes, into anything

- **The cut is the model's; the paint is free.** A VRM's clothes are a mesh
  and a painted texture. The mesh cannot be changed from here. The texture
  goes to the edit model as a flat UV atlas with the instruction to recolour
  the existing pieces and leave every one where it is — and it does: a deep
  red dress with white lace and gold buttons, a navy sailor uniform, black
  with purple ribbons and silver buttons, each with every island in place,
  so it maps straight back onto her. Twenty-three seconds at 1024 on the box.
  The repaint comes back opaque, so it takes the original's alpha — the lace
  along a hem is cut out of the texture by exactly that.
- **Every repaint is checked before she wears it.** It does not always
  repaint in place. Told about boots while looking at a dress, it painted
  boots into the dress; shown a small atlas of shoe parts it could not read,
  it drew a fashion plate. What a faithful repaint always keeps is the
  *empty* part of the atlas, so the pixels that were transparent in the
  original are measured in the repaint: still one flat colour, or something
  has been drawn where there was nothing. Measured — a faithful repaint 1.7
  to 2.9, the dress with boots 19.4, the fashion plate 89.9; the line is at
  10. A refusal gets one retry with another seed (on the first real run the
  dress needed it), and the refused paintings are kept beside the others
  under names that say what they are.
- **Each garment only hears about itself.** `repaint` describes the clothes,
  `shoes` the shoes; the prompt forbids drawing, adding or moving anything.
- **What cannot be repainted is recoloured.** The shoe atlas was refused
  every time, so a refused piece falls back to the original's own shading
  tinted to the first colour the words name — which cannot get the layout
  wrong because it never touches it.
- **Kept and remembered.** `~/.kinclaw/avatars/outfits/<model>/<name>/`;
  the outfit goes back on with the model at launch, `avatar_wear outfit:` puts
  on one she has, `"original"` the one she came in, and `avatar_outfits` lists
  them. A background job: the tool answers at once and she changes when it
  lands.

### Fixed — crouching, kneeling and jumping in a skirt

Reported as "蹲下时遮挡内裤啊", and it was worse than reported. Three separate
things exposed her, and only the first was a pose.

- **A deep squat lifts the front of a skirt.** Thighs raised towards the lens
  take the hem up with them. So a crouch is now what somebody in a skirt
  does: down to half way is a shallow athletic bend — knees forward a
  little, feet flat, the hem where it was — and past that she goes on down
  to her knees, thighs back under her and the skirt hanging straight in
  front, knees together throughout. "Pick something up" is a kneel and a
  reach. How far her hips come down is computed from her own thigh and shin
  lengths, measured when the model loads, so feet stay on the floor while
  she is on them and knees reach it when she kneels — for any character's
  proportions, not the one it was tuned on.
- **The skirt stayed in the air when she did not.** This one no pose could
  fix. Spring bones are simulated in world space, which is right for hair —
  jump, and it lifts — and wrong for cloth on somebody whose hips drop a
  third of her height in a third of a second: the skirt has inertia, stays
  where it was, and for those frames is round her waist. Every spring joint
  that hangs from the hips and not from the spine (a skirt, a coat's hem, a
  tail — eighteen joints on Vivi) now has the hips as its simulation centre:
  it still hangs by gravity, still swings when she turns, is still pushed by
  her thighs, and comes down with her. Checked mid-drop, at the top of a
  jump and on the landing. Hair is left alone, and still flies.
- **Motions the brain writes are held to the same standard.** A high kick
  towards the lens is the squat's problem again, so past a certain height
  she turns side-on for it — which is also how a kick is best seen. A leg
  lifted out to the side stops at thirty degrees. A deep bow with her back
  to the lens is limited. The writer is a language model with no eyes; it
  will not think of any of this, so the stage does.

### Added — she makes motions up

Seven things to do is a list. "比个心", "鞠个躬", "假装投篮" are not on it and
never will be, whatever the list grows to — so, like a place she has never
been, a motion she does not have is made on the spot.

- **A pose language, not bone angles.** A language model asked for Euler
  angles on seventeen joints produces arms through ribcages: it has no body
  to check them against, and a rig that is mirrored between VRM 0.x and 1.0
  wants the signs flipped besides. What it writes instead is what a person
  would say — how high an arm is raised, how far in front, how bent the
  elbow; how far the head is turned; how deep the crouch — about thirty
  sliders, each running over a range the joint can actually cover, so every
  combination is a pose a body can be in. An arm is two angles (how high,
  how far round) and the joint takes the shortest turn from rest to there,
  which makes hanging, straight ahead, overhead and across the chest all the
  same kind of thing. Seven hand shapes, the six expressions, a wink, lids
  and mouth ride along.
- **A motion is keyframes over those**, `{t, slider: value, …}`. Each slider
  has its own track, eased between the keys that name it, up from rest before
  the first and held after the last; the whole thing eases in over a third
  of a second from wherever she was and out over half to where she would
  have been anyway. A single frame is a pose: she moves into it, holds it
  two seconds and leaves. `avatar_move` takes it as `compose`.
- **Kept by name.** `~/.kinclaw/vrm/motions/<name>.json`, beside the .vrma
  files, and `play: "<name>"` does it again.
- **It is told what it got wrong.** Words the stage does not know are
  ignored and named in the answer rather than failing the motion. That is
  how the first real attempt was diagnosed: the brain wrote `armFront`,
  `armRaise`, `elbow` with no side on them — exactly what an anchor list
  that says "both arms" invites — so a limb slider with no L or R now means
  both.
- **Nine anchor poses, each looked at.** Hands together at the chest, over
  the head, at the cheeks; hand at the chin; salute; hands on hips; arms
  crossed; a waving arm; pointing ahead. Without them the brain's first
  heart was two forearms folded across her face — sensible numbers from
  something with no eyes. With them its heart is the over-the-head anchor
  with peace signs and a smile, and its basketball shot goes from arms out
  in front to elbows folded overhead and back.
- Measured with the real brain, three requests nobody wrote a motion for:
  a heart, "鞠个躬,然后挥挥手" (it composed the bow, then played the built-in
  wave — two calls, in order), and a basketball shot. All three played, and
  all three were on disk afterwards.

### Fixed

- **Every frame starts from rest.** The idle only wrote the joints it cared
  about, so whatever a motion left in the others stayed: a leg out to the
  side for the rest of the evening, fingers still in a peace sign.
- **A VRM 1.0 model stood with its arms in the air.** The idle lowered them
  with the sign that is right for a 0.x rig, and on a 1.0 rig that raises
  them. Nobody had looked, because the model in use is a 0.x.

### Added — she can stand on the desktop, and she moves

- **Her, on the desktop, in front of everything.** A second window,
  deliberately unlike the panel: no frame and no background, floating above
  other apps, on every Space and stationary, off until asked for. Drag her
  anywhere and the frame is remembered; 穿透 makes her ignore the mouse
  entirely, which is what you want while typing behind her. A web view
  swallows mouse events, so the window's own root view takes the hit and
  starts the drag. Her eyes follow the pointer across the whole screen, not
  only while it is over her. One web view exists for the character, so while
  she is out there the panel does not draw the stage. `avatar_desktop` puts
  her there from a tool.
- **Motion files, and a dance that needs none.** `.vrma` animations play
  through pixiv's `three-vrm-animation` (vendored, MIT) from
  `~/.kinclaw/vrm/motions/`; "dance" is bones on sines at 112 bpm, so that
  "dance for me" does something on a machine with no motion library.
  `avatar_move` drives both.
- **Standing still, alive.** Breath at its own rate, weight shifting on three
  sines that share no common multiple, a glance away every few seconds that
  comes back by itself — it is the unpredictability that reads as alive, not
  the amplitude. Arms down first of all: a VRM rests in a T, and anything
  that only adds sway to that keeps the T.
- **`avatar_stage`, `character_go`, `character_probe`** answer "what is the
  stage doing", "where is she and which words is each place reached by" and
  "what would this utterance or this tag do to her" without anybody at the
  keyboard.

### Fixed

- **VRM 0.x characters stood with their backs to you.** 0.x faces −Z and 1.0
  faces +Z; `VRMUtils.rotateVRM0` turns the old ones round.
- **One bad frame no longer stops her for good.** A null glance threw inside
  the render loop and the loop never ran again, silently. Each frame is now
  tried on its own, and the stage reports how many failed.
- **The soul list needed a click every launch.** The kernel starts alongside
  the app, so the first fetch often comes back empty — and empty was taken
  to mean "none". It now means "not yet", and is asked again for a few
  seconds.
- **Where she is became a decision made by events, not by the picker.** It
  used to be decided inside the art picker at the moment her state turned to
  "speaking" — a moment that, measured, did not arrive in twelve consecutive
  asks. What the user says and what a reply is tagged with now move her
  directly; the picker only reads the result.

### Changed — the places follow the conversation, and nobody has to say "去"

The goal is one continuous film of her that directs itself: every place
available, the picture going where the talk goes, clips chained so it never
reads as a cut. What shipped the day before was a switch that obeyed
commands, and for a day it did not even look like that.

- **Two of the eight places held the wrong footage.** 公园 was a byte-for-byte
  copy of the kitchen and 夜市 was a bookshop: the script that filled them
  took the first picture in a mood folder without anyone looking at it. So
  "去公园" moved her — every log said so — into a second kitchen, which from
  the chair is a switch that does not work. Five rounds of fixing the
  decision code could not find it, because the decision was right. Both
  were reshot from the right stills, and `character_go` now warns when two
  places hold identical bytes. The check that would have found it in a
  minute was a contact sheet.
- **She is told where she is.** Every companion turn carries one hidden
  line under the user's words — where she is, which place is home, a
  `key=place` list, and the rule that a tag's subject is a *place*. Without
  it the model tagged blind and the only reliable switch was the user naming
  a place out loud. With it, measured on kimi with nobody saying "去":
  tired → `sofa`, raining → `rain`, goodnight → `bedroom`, a walk → `park`,
  camping → `forest` (a place she lacks, so it gets built). The rule rides
  in the line rather than only in the soul: from the soul alone, a story
  about a dog came back tagged `dog`, which is a four-minute build of a
  place that is not a place.
- **A place on order is walked into when it lands.** The "a clip landed"
  notification was only heard by the picker sheet, so a place she had built
  stayed invisible until the panel was reopened and she never went there.
  The panel listens now, remembers what was ordered, and she arrives with
  the first clip; the talking clip joins a minute later, which is why the
  scan re-reads where she is instead of keeping the last copy. While the
  place is on order she stays in the scene she is in — the "two replies
  about nowhere and she goes home" rule is suspended, because a wait that
  changes the picture twice is not a wait, and the new place should cut in
  from the room the conversation was actually in. The user naming somewhere
  else in the meantime cancels the order; the builder giving up ends it.
- **A tag naming where she already is means "still here".** Repeats used to
  count as replies about nowhere, so she was sent home two replies into a
  conversation about the leaves. Believed six times, not forever: a small
  local brain repeats its last tag until the history scrolls away, and "she
  went to the beach once and lived there" is the bug this file has been
  fixed for more often than any other.
- **The talk clip no longer depends on mood folders existing.** The state
  hook only re-picked when there were groups, so a setup with scenes alone
  would wait silently through every answer.
- **Every clip loops without a seam, whoever made it.** A generated clip
  ends somewhere other than where it began, and played end to start that is
  a jump cut every four seconds. The first eight scenes had the seam
  dissolved into the file by ffmpeg; a place she builds for herself has been
  through no such thing, and the app has no ffmpeg to give it one. So the
  seam became the player's job: two players take turns, and half a second
  before one runs out the other starts from the top and fades in over it.
- **`companion_open`** shows the panel in companion mode from a tool. It is
  how she gets asked for by voice from another surface, and how a scene
  change gets looked at from outside at all — the day's bug hid for as long
  as it did partly because nothing but a person at the keyboard could put
  her on screen. Verified with it: nine moves, nine right pictures,
  including a forest ordered by a reply tag at 08:53 that she was standing
  in at 08:55.
- **The diagnostics log what was shown**, one entry per change with the
  time, instead of every ask — the microphone opening and closing filled
  twelve slots with `idle/listening` and said nothing about whether she had
  ever been seen talking. `character_go` also prints the exact line she
  will be told this turn.

### Added — the 3D companion stands in her places

Everything the filmed companion has — places, automatic switching, places
built on demand — now works for the 3D one, and one part of it works much
better.

- **A place has an empty plate.** Every clip and still has the generated
  woman in it, and a 3D character in front of those is two people. The edit
  model takes her out of a scene's own still in about eleven seconds and
  leaves the *same* kitchen — the window, the mugs, the light — as
  `plate.png`. Because the stills were waist-up portraits, what is left is a
  background at portrait distance and slightly out of focus: what a camera
  would see behind somebody standing there. The first time the 3D companion
  is on stage, plates are made for every place that predates her, one at a
  time, and the room behind her empties while you watch.
- **She is framed the way the plate was shot.** The stage framed the whole
  figure, which suits a desktop and turns a scene into a doll held up to a
  postcard. In a place she is cropped waist-up, where the photograph was.
- **She is lit by the place.** Swift reads the plate down to eight columns by
  four rows — average colour, brightness, which half is brighter — and the
  stage tints its lights with the hue, moves their strength with the
  brightness inside the range where a toon material still reads, and swings
  the key light to the side the window is on. Orange and side-lit at the
  beach, dim and warm at the night market, green in the forest.
- **A new place takes twenty-four seconds instead of four minutes.** The 3D
  companion needs nothing filmed: one edit for the still, one for the plate.
  Measured from a reply tagged `library`, a place that did not exist, to her
  standing in it. A place is now "usable" per companion — clips for the
  filmed one, a plate for the 3D one — and whichever half is missing is what
  gets ordered, so a place made in one mode completes itself the first time
  it is wanted in the other.

### Added — she walks around in her places, and plays

Standing waist-up in front of a plate is a portrait. The plate is what is
left of a portrait, too: a camera a metre and a half from where she stood,
and no floor anywhere in the frame. There is nowhere in it to walk.

- **A wide plate.** The edit model pulls the camera back from a place's
  plate — eye level, horizon across the middle, floor filling the lower half
  and running away from the lens — in about eleven seconds: the same kitchen
  from the doorway, the park path to its vanishing point. Made for every
  place the first time the 3D companion is on stage, and as the third step
  of a new one (still, plate, wide: about thirty-five seconds).
- **One fixed camera, and she is what moves.** It sits where the portrait
  camera would, so at the mark she is waist up exactly as before, and
  walking away she shrinks into the place with her feet on its floor —
  talking and wandering are one continuous shot. 40° rather than 30°,
  because a place photographed at 24mm and a figure rendered at 50mm do not
  share a floor. A soft shadow under her feet does the rest of the
  grounding, and thins when she jumps.
- **A stride as long as her legs.** The walk is bones on sines, like the
  dance, but its cadence comes from the distance covered rather than the
  clock — so the feet stay where they were put instead of skating over the
  floor of a photograph. She turns before she sets off. VRM 0.x and 1.0
  rigs swing a leg forward with opposite signs; both are handled.
- **Seven things to do**: wave, stretch, spin, jump, crouch to pick something
  up, look around with a hand against the light, dance.
- **Left alone, she lives there.** Nobody talking to her: she wanders, mostly
  the near half of the place — far away she is a dot, and a companion who
  spends the evening as a dot is not company — and plays where she ends up.
  A voice, or an answer on the way, and she walks back up to the lens; seven
  seconds after the exchange ends she is free again. It is the filmed
  companion's wait/talk rhythm, walked instead of cut. "A voice" is the
  recorder's own speech detection, newly published: an open microphone is
  open all evening, and the raw level sits above any fixed threshold in a
  room with a refrigerator in it.
- **Focus follows her.** The page draws the wide plate itself, because only
  it knows where she is: sharp around her out in the place, soft behind her
  at the lens, as for a camera focused a metre off.
- **How deep she may go depends on the place.** Out of doors — by the
  place's own words — down the path until she is small; indoors not past
  the back wall, or she is a small woman standing inside the cupboards. A
  place not recognised is a room.
- **`avatar_move` takes `walk` and `play`**, so "过来", "去那边看看" and
  "跳一下" are things she can be asked. A commanded move holds for a few
  seconds against the next sound in the room calling her back.
- **The hips bone rests at hip height, not at zero.** Every bounce and
  crouch is an offset from there; written straight into `position.y`, a
  two-centimetre bob puts her waist on the floor. The dance had the same
  flaw from the day before.
- `prepareStage` links her scenes and the animation module into the served
  folder, and now only ever replaces links of its own — whatever else is
  sitting under one of those names is left where it is.

### Fixed — the 3D companion never loaded at launch

- **The stage was declared ready before it existed.** The page is an ES
  module with a megabyte of imports, and `didFinish` can arrive before it
  reaches the line that publishes `window.kin`. Every call from Swift is
  guarded with `window.kin &&`, so the load did nothing and said nothing —
  this side recorded her as wearing Vivi on a page that had never been asked
  to load anybody. Ready now means `window.kin.load` is a function, polled
  for; `avatar_stage` reports this side of the bridge as well, because from
  the page alone "never asked" and "slow load" look the same.
- **The switch to 3D was swallowed by the anti-slideshow hold.** The stage
  server comes up a fraction of a second after the view's first pick, and
  the second pick fell inside the four-second hold, leaving the filmed clip
  behind the 3D figure until something else changed.

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
VRM animation files (`.vrma`) and the transparent always-on-top window that
puts her on the desktop rather than in a panel both followed — see above.

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
