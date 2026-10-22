# Chess Battle

Chess with a gold economy. Each side starts with a king, 3 pawns and a knight, placed randomly and mirrored. Capture pieces to earn gold, spend it to drop reinforcements, and checkmate your opponent.

Play: https://forestmack.github.io/chess-battle/

## Rules

- **Your turn:** move one piece, or buy as many pieces as you can afford, then end your turn.
- **Gold:** you start with 3 and it carries over between turns. Captures pay: pawn 1, knight or bishop 3, rook 5, queen 9.
- **Shop:** pawn 1, knight 4, bishop 4, rook 6, queen 12. Pawns drop on your pawn row and everything else on your back row. You can't buy the same piece twice in a row, and you can have at most 8 pawns.
- **Suicide:** if your king is still in check when your turn ends, you lose on the spot.
- **Win:** by checkmate, suicide, resignation or time.
- **Draw:** no safe move and nothing to buy, 30 turns each with no capture, buy or pawn move, or bare kings.

## Modes

- Bots: Easy, Medium and Hard
- Daily challenge: the same board for everyone each day
- Daily puzzle: mate in one
- Pass & play on one phone
- Online head to head via an invite link

## Nations and Legacy

- **Chess Nations:** new players spin to join one of four nations: Ember Dominion, Tide Republic, Grove Order or Dusk Throne. Online wins earn your nation 5 stars, losses cost 3, and a draw gives both nations 1. Your nation's home board shows whenever you play White online, and both armies wear their nation's colors.
- **Legacy:** stars also build your personal legacy, which unlocks five earn-only piece sets: Marble, Neon, Forged, Prism and Celestial. Online games pay the same stars to your legacy. Bot and daily games award legacy too (win +2, draw +1, loss −1, up to 10 a day), but only online games count for your nation.

## Under the hood

- Single-file app (`index.html`), with no build step and no backend
- Online play is peer-to-peer through PeerJS, so there are no accounts or game server
- Progress, cosmetics and replays are saved on the device
- Installable as a home-screen app, and works offline for bot and pass & play games
