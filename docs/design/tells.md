# Jukebox: less AI

The photographer, 8 November 2026: "Kun je het design iets minder ai maken?"
These are the tells our own screens had, and the rule for each. Sketch D
(`sheet-d.png`) shows them applied to Home, Now Playing and Radio.

| # | Avoid | Do instead |
|---|---|---|
| 1 | Everything glows: tubes, bloom, glowing buttons, cards, cores, lamps. | Light means on air. Only the station playing is lit. Every other arch is two flat bands (Copper outside, Glow inside) and a flat core: no blur, no bloom. No button glows. |
| 2 | Purple-pink gradients, synthwave and AI-art covers; radial vignettes behind screens. | Flat grounds: `#121110`, or Cabinet `#1E0A07` for Now Playing; warm paper `#F6F3EE` by day. No vignettes, no mesh gradients. Demo art looks human: typographic sleeves, one-colour prints out of register, grainy duotones of plain things, a plain sleeve with a sticker, in ochre, olive, brick, cream, slate and black. |
| 3 | A face nobody chose (Inter), or the trendy wide display face. | Titles in a serif, as on sleeves: New York (`.fontDesign(.serif)`), regular weight. Everything else in SF Pro. Tabular figures for times. |
| 4 | Tracked uppercase eyebrows on every block. | Sentence-case headings in the serif ("Mixes", "Played lately", "Stations"). At most one small label a screen ("On air"). |
| 5 | Slogans and explaining micro-copy; a subtitle under every card; a reason under every row. | Facts, not slogans: "Made at 06:00", "Yesterday", "Played Thursday", a mix's artists. Cut a subtitle that repeats its title. The radio's reasons appear only in the queue. The dial shows its two ends and nothing else. |
| 6 | Cards in cards, rounded panels, pill buttons with icon and label, soft shadow plus border. | Content on the ground, separated by hairlines and space. One radius: 6 pt for artwork; nothing else rounded but the system's own controls (tab bar, mini player, toolbar). Text buttons or plain SF Symbols. One prominent action a screen: a plain filled rectangle, 6 pt corners, no glow. |
| 7 | A glossy 3D render: chrome arm, specular streaks, a spotlight. | The turntable is drawn: a matte platter and the picture disc at the same angle, one faint wedge of sheen, the arm a flat two-tone shape with a pivot circle and a hard offset shadow, one soft falloff on the deck. |
| 8 | Perfect centred symmetry everywhere. | Left-aligned, editorial: titles, rows and Now Playing's text start at the margin. Shelves peek off the edge. Centre only what Apple centres (the transport). |

Before a screen ships, check:
- Is anything lit that is not on air?
- Is there an uppercase label, or more than one small label?
- Does any line tell me what I already see?
- Is anything rounded that is not artwork or a system control?
- Is there more than one filled button?
- Is a title set in the sans?
