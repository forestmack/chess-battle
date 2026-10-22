# Chess Battle

Chess with a gold economy. Each side starts with a king, 3 pawns and a knight, placed randomly and mirrored. Capture pieces to earn gold, spend it to drop reinforcements, and checkmate your opponent.

Play: https://forestmack.github.io/chess-battle/

## Rules

- **Your turn:** move one piece, or buy as many pieces as you can afford, then end your turn.
- **Gold:** you start with 3 and it carries over between turns. Captures pay: pawn 1, knight or bishop 3, rook 5, queen 9.
- **Shop:** pawn 1, knight 4, bishop 4, rook 6, queen 12. Pawns drop on your pawn row and everything else on your back row. You can't buy the same piece twice in a row, and you can have at most 8 pawns.
- **Suicide:** if your king is still in check when your turn ends, you lose on the spot.
- **Win:** by checkmate, suicide, resignation or time.
- **Stalemate wins:** if your opponent has no safe move and nothing to buy on their turn, you win.
- **Draw:** 30 turns each with no capture, buy or pawn move, or bare kings.

## Modes

- Bots: Easy, Medium and Hard
- Daily challenge: the same board for everyone each day
- Daily puzzle: mate in one
- Pass & play on one phone
- Online head to head via an invite link

## Nations and Legacy

- **Chess Nations:** new players spin to join one of four nations: Ember Dominion, Tide Republic, Grove Order or Dusk Throne. Online wins earn your nation 5 stars, losses cost 3, and a draw gives both nations 1. Your nation's home board shows whenever you play White online, and both armies wear their nation's colors.
- **Legacy:** stars also build your personal legacy, which unlocks five earn-only piece sets: Marble, Neon, Forged, Prism and Celestial. Online games pay the same stars to your legacy. Bot and daily games award legacy too (win +2, draw +1, loss −1, up to 10 a day), but only online games count for your nation.

## Online

- **Quick match** pairs you with whoever else is searching. Live games run over Supabase Realtime and are saved on the server, so anyone can watch them from **Live now**.
- **One-move-a-day games** with friends: 3 days per move, several games at once, listed under **Your games**.
- **Friends** with 8-character friend codes, plus live and daily challenges.
- If an opponent leaves a live game on their turn for 2 minutes, you can claim the win.
- **Nation war:** a 16-region territory map where your wins fight for the front you pick, double nation stars on war weekends, an end-of-month ceremony, each capital's council and recruit links.
- **Training:** Puzzle Rush (3 minutes, 3 strikes, daily leaderboard), game review and shareable video clips.

See `docs/NEXT_STEPS.md` for push notifications, app stores, payments and the retention report.

## Nation Guards

Each nation has 25 Guards: labeled bots that defend it while the player base grows.

| Rank | Count | Rating | Points for beating one |
|---|---|---|---|
| King | 1 | 1600 | 5 |
| Queen | 2 | 1420–1460 | 4 |
| Rook | 3 | 1310–1370 | 3 |
| Bishop | 4 | 1210–1290 | 2 |
| Knight | 5 | 1100–1180 | 2 |
| Pawn | 10 | 1000–1090 (Medium bot strength) | 1 |

- **Quick match** always pairs two searching players first. If nobody else is searching after 6 to 12 seconds, a random Guard from another nation takes the seat. It's always shown with a Guard badge.
- **Beating a Guard** scores its points for your nation and your legacy. A loss costs 1 legacy and gives the Guard's nation 1 point. Up to 12 Guard games a day count. Leaving one part way through counts as a loss.
- **Playstyles:** Ember attacks the king, Tide banks gold and guards its king, Grove builds pawn walls and promotes, Dusk searches deeper for tactics.
- **Guard battles:** every 30 minutes two Guards from different nations play a game (`server/war-runner.mjs`, run by `.github/workflows/war.yml`). The game plays out live in the app at one move every 6 seconds, then the winner's nation scores the loser's rank. A drawn battle goes to the side with an army (pieces plus gold) at least 3 bigger.
- Guard ratings move with results but stay within 80 of their rank's base, so a king always outranks a queen.

## Under the hood

- Single-file app (`index.html`), with no build step and no backend
- Games are played peer-to-peer through PeerJS. A Supabase backend (`server/schema.sql`) handles guest accounts, nation assignment, star results, worldwide standings, leaderboards and quick-match pairing. Online results only score when both players' apps report the same outcome.
- Without server keys in `index.html` the game runs fully on the device, as before
- Progress, cosmetics and replays are saved on the device
- Installable as a home-screen app, and works offline for bot and pass & play games
