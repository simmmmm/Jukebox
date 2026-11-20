# Jukebox: more soul

What makes a Jukebox screen feel made by someone: a record shop's care, not
a template's. The photographer, 14 November 2026: "niet 'minder ai' maar
vooral meer ziel". (The list began on 8 November 2026 as the answer to "Kun
je het design iets minder ai maken?"; these are the same rules, said as what
to reach for.) Sketch D first drew them, on Home, Now Playing and Radio;
the app's own screenshots show them now.

| # | Reach for | In place of |
|---|---|---|
| 1 | Light means on air. Only the station playing is lit; every other arch is two flat bands (Copper outside, Glow inside) and a flat core. | Glow on everything: tubes, bloom, glowing buttons, cards, cores, lamps. |
| 2 | Flat grounds: `#121110` by night, warm paper `#F6F3EE` by day. Now Playing's ground is its record's (the album's side as land, or a wall and a floor of the cover's colours; Cabinet `#1E0A07` without a cover). Demo art looks human: typographic sleeves, one-colour prints out of register, grainy duotones of plain things, a plain sleeve with a sticker, in ochre, olive, brick, cream, slate and black. | Purple-pink gradients, synthwave covers, vignettes and mesh gradients behind screens. |
| 3 | Titles in a serif, as on sleeves: New York on Apple (`.fontDesign(.serif)`), the system's serif on Linux, regular weight. Everything else in the system's sans. Tabular figures for times. | A face nobody chose, or the season's wide display face. |
| 4 | Sentence-case headings in the serif ("Mixes", "Played lately", "Stations"). One small label a screen at most ("On air"). | Tracked uppercase eyebrows on every block. |
| 5 | Facts: "Made at 06:00", "Yesterday", "Played Thursday", a mix's artists. The radio's reasons in the queue, where they are asked for. The dial shows its two ends. | Slogans, a subtitle under every card that repeats its title, a reason under every row. |
| 6 | Content on the ground, separated by hairlines and space. One radius: 6 pt for artwork, and concentric where one shape holds another (a tile's hover, 8 past its art: 14); the system's own controls keep the system's shapes. Text buttons or plain symbols. One prominent action a screen: a plain filled button (6 pt corners on the iPhone, GNOME's own on Linux), 36 tall; the action beside it (Shuffle, New Picks, Stop) its twin on a faint ground of the accent. Home's Your Station and the music to go on with each on the raised ground, corners concentric with the art's (18 at 12 in). | Cards in cards, rounded panels, pill buttons with icon and label, shadow plus border. |
| 7 | The sleeve and its record, drawn: printed card with grain and a soft shadow from above, black vinyl with fine grooves, one faint pair of sheen wedges that do not turn, the label a flat colour printed in one ink. | A glossy 3D render: chrome arm, specular streaks, a spotlight. |
| 8 | Left-aligned, editorial: titles, rows and Now Playing's text start at the margin. Shelves peek off the edge. Centre what the platform centres (the transport). | Centred symmetry everywhere. |

Before a screen ships, walk it, then the parity checklist in `SYSTEM.md`, where these rules become tokens and components:
- Is the only light the station on air?
- Is every heading sentence case, with one small label at most?
- Does every line tell something not already seen?
- Do only artwork and the one filled button carry Jukebox's radius, and what holds them a concentric one?
- Is there one filled button?
- Are the titles in the serif?
