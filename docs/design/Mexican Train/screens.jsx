// Mexican Train screens — shared by direction A (Caboose) and B (Pacific)
// Each direction passes a `theme` prop with its color/font/border vocabulary.

const { useState, useEffect, useRef } = React;

// ─────────────────────────────────────────────────────────────
// Sample game state
// ─────────────────────────────────────────────────────────────
const PLAYERS_FULL = [
  { id: 'a', name: 'Aaron',   star: true,  you: false },
  { id: 'k', name: 'Kevin',   star: false, you: true  },
  { id: 'k2', name: 'Kev II', star: false, you: false },
  { id: 'c', name: 'Comp',    star: false, you: false },
  { id: 'd', name: 'Dale',    star: false, you: false },
  { id: 'e', name: 'Edie',    star: false, you: false },
  { id: 'f', name: 'Frankie', star: false, you: false },
  { id: 'g', name: 'Gus',     star: false, you: false },
];

// 13 stops (double-12 down to double-0). null = not yet played.
const SCORES_FULL = {
  a:  [38, 12, 22, 0,  null, null, null, null, null, null, null, null, null],
  k:  [14, 0,  18, 7,  null, null, null, null, null, null, null, null, null],
  k2: [22, 5,  9,  null,null, null, null, null, null, null, null, null, null],
  c:  [9,  18, 31, null,null, null, null, null, null, null, null, null, null],
  d:  [16, 4,  12, null,null, null, null, null, null, null, null, null, null],
  e:  [20, 9,  14, null,null, null, null, null, null, null, null, null, null],
  f:  [11, 22, 8,  null,null, null, null, null, null, null, null, null, null],
  g:  [5,  17, 20, null,null, null, null, null, null, null, null, null, null],
};

const sumPlayer = (arr) => arr.reduce((a, b) => a + (b || 0), 0);

// ─────────────────────────────────────────────────────────────
// Tiny domino glyph (used for engine indicator)
// ─────────────────────────────────────────────────────────────
function DominoGlyph({ a = 12, b = 12, w = 36, color = '#1c1917', orientation = 'horizontal' }) {
  const pip = (cx, cy) => <circle cx={cx} cy={cy} r="1.6" fill={color} />;
  const pips = (n, ox) => {
    const layouts = {
      0: [], 1: [[7,7]], 2: [[4,4],[10,10]],
      3: [[4,4],[7,7],[10,10]],
      4: [[4,4],[10,4],[4,10],[10,10]],
      5: [[4,4],[10,4],[7,7],[4,10],[10,10]],
      6: [[4,4],[10,4],[4,7],[10,7],[4,10],[10,10]],
      7: [[4,4],[10,4],[4,7],[10,7],[4,10],[10,10],[7,7]],
      8: [[3,3],[7,3],[11,3],[3,7],[11,7],[3,11],[7,11],[11,11]],
      9: [[3,3],[7,3],[11,3],[3,7],[7,7],[11,7],[3,11],[7,11],[11,11]],
      10: [[3,3],[7,3],[11,3],[3,6],[11,6],[3,9],[11,9],[3,11],[7,11],[11,11]],
      11: [[3,3],[7,3],[11,3],[3,6],[7,6],[11,6],[3,9],[11,9],[3,11],[7,11],[11,11]],
      12: [[3,3],[7,3],[11,3],[3,6],[7,6],[11,6],[3,9],[7,9],[11,9],[3,11],[7,11],[11,11]],
    };
    return (layouts[n] || []).map(([x,y], i) => <circle key={i} cx={x+ox} cy={y} r="1.3" fill={color} />);
  };
  if (orientation === 'vertical') {
    // Render rotated: swap width/height so the SVG box is tall.
    return (
      <svg width={w/2} height={w} viewBox="0 0 14 28" style={{ display: 'block' }}>
        <rect x="0.5" y="0.5" width="13" height="27" rx="1.5" fill="none" stroke={color} strokeWidth="0.8"/>
        <line x1="1" y1="14" x2="13" y2="14" stroke={color} strokeWidth="0.8"/>
        {/* top half = a (rotate the inner pip layout 90°: x,y → y, 14-x within 14×14) */}
        <g transform="translate(0,0)">
          {(()=>{ const ps={
            0: [], 1: [[7,7]], 2: [[4,4],[10,10]],
            3: [[4,4],[7,7],[10,10]],
            4: [[4,4],[10,4],[4,10],[10,10]],
            5: [[4,4],[10,4],[7,7],[4,10],[10,10]],
            6: [[4,4],[10,4],[4,7],[10,7],[4,10],[10,10]],
            7: [[4,4],[10,4],[4,7],[10,7],[4,10],[10,10],[7,7]],
            8: [[3,3],[7,3],[11,3],[3,7],[11,7],[3,11],[7,11],[11,11]],
            9: [[3,3],[7,3],[11,3],[3,7],[7,7],[11,7],[3,11],[7,11],[11,11]],
            10: [[3,3],[7,3],[11,3],[3,6],[11,6],[3,9],[11,9],[3,11],[7,11],[11,11]],
            11: [[3,3],[7,3],[11,3],[3,6],[7,6],[11,6],[3,9],[11,9],[3,11],[7,11],[11,11]],
            12: [[3,3],[7,3],[11,3],[3,6],[7,6],[11,6],[3,9],[7,9],[11,9],[3,11],[7,11],[11,11]],
          }; return (ps[a]||[]).map(([x,y],i)=><circle key={i} cx={x} cy={y} r="1.3" fill={color}/>); })()}
        </g>
        <g transform="translate(0,14)">
          {(()=>{ const ps={
            0: [], 1: [[7,7]], 2: [[4,4],[10,10]],
            3: [[4,4],[7,7],[10,10]],
            4: [[4,4],[10,4],[4,10],[10,10]],
            5: [[4,4],[10,4],[7,7],[4,10],[10,10]],
            6: [[4,4],[10,4],[4,7],[10,7],[4,10],[10,10]],
            7: [[4,4],[10,4],[4,7],[10,7],[4,10],[10,10],[7,7]],
            8: [[3,3],[7,3],[11,3],[3,7],[11,7],[3,11],[7,11],[11,11]],
            9: [[3,3],[7,3],[11,3],[3,7],[7,7],[11,7],[3,11],[7,11],[11,11]],
            10: [[3,3],[7,3],[11,3],[3,6],[11,6],[3,9],[11,9],[3,11],[7,11],[11,11]],
            11: [[3,3],[7,3],[11,3],[3,6],[7,6],[11,6],[3,9],[11,9],[3,11],[7,11],[11,11]],
            12: [[3,3],[7,3],[11,3],[3,6],[7,6],[11,6],[3,9],[7,9],[11,9],[3,11],[7,11],[11,11]],
          }; return (ps[b]||[]).map(([x,y],i)=><circle key={i} cx={x} cy={y} r="1.3" fill={color}/>); })()}
        </g>
      </svg>
    );
  }
  return (
    <svg width={w} height={w/2} viewBox="0 0 28 14" style={{ display: 'block' }}>
      <rect x="0.5" y="0.5" width="27" height="13" rx="1.5" fill="none" stroke={color} strokeWidth="0.8"/>
      <line x1="14" y1="1" x2="14" y2="13" stroke={color} strokeWidth="0.8"/>
      {pips(a, 0)}
      {pips(b, 14)}
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// REFERENCE PHOTO — a "captured" wood-table shot showing the dominoes laid out
// ─────────────────────────────────────────────────────────────
function ReferencePhoto({ theme }) {
  const tiles = [[5,3],[9,0],[6,4],[2,2],[11,8],[10,7],[12,5],[4,1]];
  return (
    <div style={{
      flex: 1, minHeight: 0,
      borderRadius: 12, overflow: 'hidden', position: 'relative',
      border: `2px solid ${theme.ink}`,
      background: 'linear-gradient(135deg, #8b6f47 0%, #6b4f2f 60%, #4a3522 100%)',
      boxShadow: 'inset 0 0 30px rgba(0,0,0,0.5), 0 2px 6px rgba(0,0,0,0.2)',
    }}>
      {/* wood grain */}
      <div style={{
        position: 'absolute', inset: 0,
        backgroundImage: 'repeating-linear-gradient(95deg, rgba(0,0,0,0.1) 0 2px, transparent 2px 7px), radial-gradient(ellipse at 30% 40%, rgba(255,200,140,0.12), transparent 60%)',
        pointerEvents: 'none',
      }}/>

      {/* dominoes scattered like a real photo */}
      <div style={{
        position: 'absolute', inset: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexWrap: 'wrap', gap: 6, padding: 14,
      }}>
        {tiles.map(([a, b], i) => (
          <div key={i} style={{
            transform: `rotate(${(i % 2 ? 1 : -1) * (3 + (i * 7) % 12)}deg)`,
            filter: 'drop-shadow(0 2px 3px rgba(0,0,0,0.6))',
            background: '#fefcf6', padding: '4px 5px', borderRadius: 3,
          }}>
            <DominoGlyph a={a} b={b} w={42} color="#1c1917"/>
          </div>
        ))}
      </div>

      {/* photo metadata strip */}
      <div style={{
        position: 'absolute', top: 6, left: 8, right: 8,
        display: 'flex', justifyContent: 'space-between',
        fontFamily: theme.mono, fontSize: 8, color: 'rgba(255,255,255,0.85)',
        letterSpacing: '0.12em', fontWeight: 700,
        textShadow: '0 1px 2px rgba(0,0,0,0.7)',
        pointerEvents: 'none',
      }}>
        <span>● REC · IMG_0428</span>
        <span>ƒ/2.4 · 1/60s</span>
      </div>

      {/* corner markers */}
      {[[6,6,'tl'],[6,6,'tr'],[6,6,'bl'],[6,6,'br']].map(([w,h,pos], i) => {
        const style = { position: 'absolute', width: 14, height: 14, border: '2px solid rgba(255,255,255,0.45)', pointerEvents: 'none' };
        if (pos === 'tl') Object.assign(style, { top: 4, left: 4, borderRight: 'none', borderBottom: 'none' });
        if (pos === 'tr') Object.assign(style, { top: 4, right: 4, borderLeft: 'none', borderBottom: 'none' });
        if (pos === 'bl') Object.assign(style, { bottom: 4, left: 4, borderRight: 'none', borderTop: 'none' });
        if (pos === 'br') Object.assign(style, { bottom: 4, right: 4, borderLeft: 'none', borderTop: 'none' });
        return <div key={i} style={style}/>;
      })}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SCOREBOARD — Golf card (rows = players, cols = stops)
// ─────────────────────────────────────────────────────────────
function Scoreboard({ theme, state, onAddScore, onAuditScore, density = 'cozy', showHistory = true, playerCount = 4, showGallery = true }) {
  const players = PLAYERS_FULL.slice(0, playerCount);
  const scores = Object.fromEntries(players.map(p => [p.id, SCORES_FULL[p.id]]));
  const stops = 13;
  const currentStop = state.currentStop; // 1-indexed

  // standings: lower total = better (Mexican Train scoring)
  const standings = players
    .map(p => ({ ...p, total: sumPlayer(scores[p.id]) }))
    .sort((a, b) => a.total - b.total);
  const leaderId = standings[0].id;
  const you = players.find(p => p.you);
  const yourTotal = you ? sumPlayer(scores[you.id]) : 0;
  const yourPlace = you ? standings.findIndex(s => s.id === you.id) + 1 : 0;
  const leaderTotal = standings[0].total;
  const behind = yourTotal - leaderTotal;
  const ordinal = (n) => n === 1 ? '1st' : n === 2 ? '2nd' : n === 3 ? '3rd' : `${n}th`;

  const cellH = density === 'compact' ? 22 : 28;
  const fontSm = density === 'compact' ? 10 : 11;

  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      background: theme.bg, color: theme.ink,
      overflow: 'hidden',
    }}>
      {/* Header strip — title + stop indicator + menu */}
      <div style={{
        padding: '8px 14px 6px', display: 'flex', alignItems: 'center',
        justifyContent: 'space-between', gap: 8,
        borderBottom: `1px solid ${theme.border}`,
        background: theme.headerBg, flexShrink: 0,
      }}>
        <div style={{
          fontFamily: theme.display, fontSize: 15, letterSpacing: '0.10em',
          color: theme.brand, fontWeight: 700, whiteSpace: 'nowrap',
          lineHeight: 1, flexShrink: 0,
        }}>MEX·TRAIN</div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 5, flexShrink: 0, lineHeight: 1 }}>
          <span style={{
            fontFamily: theme.mono, fontSize: 9, color: theme.muted,
            letterSpacing: '0.14em',
          }}>STOP</span>
          <span style={{
            fontFamily: theme.display, fontSize: 17, color: theme.ink,
            fontWeight: 700, lineHeight: 1, whiteSpace: 'nowrap',
          }}>{currentStop}<span style={{ color: theme.muted, fontSize: 11 }}>/{stops}</span></span>
          <button style={{
            border: 'none', background: 'transparent', color: theme.muted,
            padding: 0, marginLeft: 4, cursor: 'pointer', display: 'flex', alignSelf: 'center',
          }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="19" r="1"/>
            </svg>
          </button>
        </div>
      </div>

      {/* Engine sub-strip */}
      <div style={{
        padding: '5px 14px', display: 'flex', alignItems: 'center', gap: 8,
        background: theme.subBg, borderBottom: `1px solid ${theme.border}`,
        fontFamily: theme.mono, fontSize: 10, color: theme.muted,
        letterSpacing: '0.1em', textTransform: 'uppercase',
        whiteSpace: 'nowrap', flexShrink: 0, lineHeight: 1,
      }}>
        <span style={{ flexShrink: 0 }}>Engine</span>
        <DominoGlyph a={13 - currentStop} b={13 - currentStop} w={28} color={theme.ink} />
        <span style={{ marginLeft: 'auto', color: theme.accent, fontSize: 9, flexShrink: 0 }}>
          ●&nbsp;{playerCount}&nbsp;aboard
        </span>
      </div>

      {/* YOUR-STATS strip — place + behind leader */}
      {you && (
        <div style={{
          padding: '10px 14px', display: 'flex', alignItems: 'stretch',
          gap: 10, background: theme.youBg,
          borderBottom: `1px solid ${theme.border}`, flexShrink: 0,
        }}>
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{
              fontFamily: theme.display, fontSize: 30, fontWeight: 800,
              color: yourPlace === 1 ? theme.brand : theme.ink,
              lineHeight: 1, letterSpacing: '-0.02em',
            }}>{ordinal(yourPlace)}</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <div style={{
                fontFamily: theme.mono, fontSize: 9, letterSpacing: '0.14em',
                color: theme.muted, textTransform: 'uppercase',
              }}>You · {you.name}</div>
              <div style={{
                fontFamily: theme.mono, fontSize: 10, color: theme.ink,
                letterSpacing: '0.04em', fontWeight: 600,
              }}>
                {behind === 0
                  ? <span style={{ color: theme.brand }}>LEADING THE TRAIN ♔</span>
                  : <>{behind} pts behind <span style={{ color: theme.muted }}>{standings[0].name}</span></>}
              </div>
            </div>
          </div>
          <div style={{
            display: 'flex', flexDirection: 'column', alignItems: 'flex-end',
            justifyContent: 'center', borderLeft: `1px dashed ${theme.border}`,
            paddingLeft: 10,
          }}>
            <div style={{
              fontFamily: theme.mono, fontSize: 9, letterSpacing: '0.14em',
              color: theme.muted, textTransform: 'uppercase',
            }}>Your total</div>
            <div style={{
              fontFamily: theme.display, fontSize: 22, fontWeight: 800,
              color: theme.ink, lineHeight: 1,
            }}>{yourTotal}</div>
          </div>
        </div>
      )}

      {/* GOLF CARD TABLE */}
      {/* GOLF CARD TABLE */}
      <div style={{ flex: 1, overflow: 'hidden', padding: '8px 8px 0', display: 'flex', flexDirection: 'column', minHeight: 0 }}>
        <div style={{
          flex: 'none', overflow: 'auto', borderRadius: 8,
          border: `1px solid ${theme.border}`, background: theme.cardBg,
        }}>
          {/* Stop headers row */}
          <div style={{
            display: 'grid',
            gridTemplateColumns: `64px repeat(${stops}, 1fr) 38px`,
            background: theme.headerBg,
            borderBottom: `1px solid ${theme.border}`,
            position: 'sticky', top: 0, zIndex: 2,
          }}>
            <div style={{
              padding: '6px 6px', fontFamily: theme.mono, fontSize: fontSm,
              color: theme.muted, letterSpacing: '0.08em',
            }}>PLAYER</div>
            {Array.from({ length: stops }).map((_, i) => {
              const stopNum = i + 1;
              const isCurrent = stopNum === currentStop;
              const isPast = stopNum < currentStop;
              return (
                <div key={i} style={{
                  padding: '6px 0', fontFamily: theme.mono, fontSize: fontSm,
                  color: isCurrent ? theme.bg : (isPast ? theme.ink : theme.muted),
                  background: isCurrent ? theme.accent : 'transparent',
                  textAlign: 'center', fontWeight: isCurrent ? 700 : 500,
                  borderLeft: `1px solid ${theme.border}`,
                }}>{stopNum}</div>
              );
            })}
            <div style={{
              padding: '6px 0', fontFamily: theme.mono, fontSize: fontSm,
              color: theme.muted, letterSpacing: '0.1em', textAlign: 'center',
              borderLeft: `2px solid ${theme.border}`, background: theme.subBg,
            }}>TOT</div>
          </div>

          {/* Player rows */}
          {players.map((p, ri) => {
            const total = sumPlayer(scores[p.id]);
            const youRow = p.you;
            const leader = p.id === leaderId;
            return (
              <div key={p.id} style={{
                display: 'grid',
                gridTemplateColumns: `64px repeat(${stops}, 1fr) 38px`,
                background: youRow ? theme.youBg : 'transparent',
                borderBottom: ri < players.length - 1 ? `1px solid ${theme.borderLight}` : 'none',
                position: 'relative',
              }}>
                {/* Name cell */}
                <div style={{
                  padding: '0 6px', display: 'flex', alignItems: 'center', gap: 3,
                  fontFamily: theme.mono, fontSize: 11, fontWeight: youRow ? 700 : 500,
                  color: theme.ink, height: cellH, lineHeight: 1,
                  borderRight: `1px solid ${theme.border}`, letterSpacing: '0.02em',
                }}>
                  {youRow && <span style={{ color: theme.accent, fontSize: 10, flexShrink: 0 }}>▸</span>}
                  <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', minWidth: 0 }}>{p.name}</span>
                  {leader && <span style={{ color: theme.brand, fontSize: 10, flexShrink: 0 }}>♔</span>}
                </div>
                {/* score cells */}
                {scores[p.id].map((s, ci) => {
                  const stopNum = ci + 1;
                  const isCurrent = stopNum === currentStop;
                  const isPlayed = s !== null;
                  return (
                    <button key={ci}
                      onClick={() => isPlayed && onAuditScore && onAuditScore(p, ci)}
                      disabled={!isPlayed}
                      style={{
                        height: cellH,
                        border: 'none', background: isCurrent ? theme.currentCol : 'transparent',
                        borderLeft: `1px solid ${theme.borderLight}`,
                        fontFamily: showHistory ? theme.mono : theme.display,
                        fontSize: showHistory ? 11 : 10,
                        fontWeight: 600,
                        color: isPlayed ? theme.ink : theme.muted,
                        cursor: isPlayed ? 'pointer' : 'default',
                        padding: 0,
                      }}>
                      {showHistory ? (isPlayed ? s : '·') : (isPlayed ? '✓' : '·')}
                    </button>
                  );
                })}
                {/* total */}
                <div style={{
                  height: cellH, display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontFamily: theme.mono, fontSize: 13, fontWeight: 800,
                  color: leader ? theme.brand : theme.ink,
                  borderLeft: `2px solid ${theme.border}`, background: theme.subBg,
                }}>{total}</div>
              </div>
            );
          })}
        </div>

        {/* legend */}
        <div style={{
          padding: '6px 4px', fontFamily: theme.mono, fontSize: 9,
          color: theme.muted, display: 'flex', justifyContent: 'space-between',
          letterSpacing: '0.08em', flexShrink: 0,
        }}>
          <span>♔ LEADER  ▸ YOU</span>
          <span>TAP ANY SCORE TO AUDIT</span>
        </div>

        {/* PHOTO GALLERY — stop {currentStop - 1} captures */}
        {showGallery && currentStop > 1 ? (
          <PhotoGallery theme={theme} stop={currentStop - 1} players={players} scores={scores}/>
        ) : (
          <div style={{ flex: 1 }}/>
        )}
      </div>

      {/* PRIMARY CTA — Add Score */}
      <div style={{
        padding: '8px 14px 14px', flexShrink: 0,
        background: theme.subBg, borderTop: `1px solid ${theme.border}`,
      }}>
        <button onClick={onAddScore} style={{
          width: '100%', height: 56, borderRadius: theme.btnRadius ?? 12, border: 'none',
          background: theme.cta, color: theme.ctaText,
          fontFamily: theme.display, fontSize: 14, fontWeight: 800,
          letterSpacing: '0.14em', cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
          whiteSpace: 'nowrap', lineHeight: 1,
          boxShadow: theme.ctaShadow,
        }}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{ flexShrink: 0 }}>
            <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/>
            <circle cx="12" cy="13" r="4"/>
          </svg>
          <span>ADD SCORE</span>
          <span style={{
            fontFamily: theme.mono, fontSize: 11, opacity: 0.7,
            padding: '3px 8px', borderRadius: 999,
            background: 'rgba(255,255,255,0.12)', letterSpacing: '0.08em',
          }}>STOP&nbsp;{currentStop}</span>
        </button>
        <div style={{
          textAlign: 'center', marginTop: 6, fontFamily: theme.mono,
          fontSize: 9, color: theme.muted, letterSpacing: '0.12em',
        }}>
          YOUR TURN · ENGINE {13 - currentStop}-{13 - currentStop}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// PHOTO GALLERY — recent stop captures (camera roll strip)
// ─────────────────────────────────────────────────────────────
function PhotoGallery({ theme, stop, players, scores }) {
  // Build a thumbnail per player for the given stop
  const items = players.map(p => {
    const pts = scores[p.id]?.[stop - 1];
    return { player: p, points: pts == null ? '—' : pts };
  });

  // Tile mini — pip count visualised as 1 or 2 mini dominoes
  const renderTilePips = (n, seed) => {
    const tiles = [];
    let remain = n;
    while (remain > 0 && tiles.length < 2) {
      const a = Math.min(12, Math.max(0, Math.round(remain / 2)));
      const b = remain - a;
      tiles.push([a, Math.min(12, b)]);
      remain -= (a + Math.min(12, b));
    }
    if (tiles.length === 0) tiles.push([0, 0]);
    return tiles;
  };

  // Choose column count that gives a balanced grid for the player count
  const n = items.length;
  let cols = 4;
  if (n <= 3) cols = n;
  else if (n === 4) cols = 2;
  else if (n <= 6) cols = 3;
  else cols = 4;

  return (
    <div style={{
      flex: 1, minHeight: 0,
      display: 'flex', flexDirection: 'column',
      padding: '6px 6px 6px',
      borderTop: `1px dashed ${theme.border}`,
      background: theme.subBg,
      borderRadius: 10,
      overflow: 'hidden',
    }}>
      <div style={{
        display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
        padding: '0 4px 4px', fontFamily: theme.mono, fontSize: 9,
        color: theme.muted, letterSpacing: '0.1em',
        flexShrink: 0,
      }}>
        <span>📷 STOP {stop} · CAMERA ROLL</span>
        <span style={{ color: theme.accent, fontWeight: 700 }}>VIEW ALL ›</span>
      </div>
      <div style={{
        flex: 1, minHeight: 0,
        display: 'grid',
        gridTemplateColumns: `repeat(${cols}, 1fr)`,
        gridAutoRows: '1fr',
        gap: 5,
      }}>
        {items.map((it, i) => (
          <PhotoTile key={it.player.id} theme={theme} item={it} idx={i} />
        ))}
      </div>
    </div>
  );
}

function PhotoTile({ theme, item, idx }) {
  const { player, points } = item;
  // Wood-grain backdrop tone, slightly different per tile for variety
  const woodTones = [
    'linear-gradient(135deg, #8b6f47 0%, #6b4f2f 100%)',
    'linear-gradient(135deg, #7a5f3f 0%, #5a4527 100%)',
    'linear-gradient(135deg, #94724c 0%, #75552f 100%)',
    'linear-gradient(135deg, #6f5638 0%, #4f3b22 100%)',
  ];
  const wood = woodTones[idx % woodTones.length];

  // Pick 1-2 small dominoes to show on the "photo"
  const n = typeof points === 'number' ? points : 0;
  const tiles = [];
  let remain = n;
  while (remain > 0 && tiles.length < 2) {
    const a = Math.min(12, Math.max(0, Math.floor(remain / 2)));
    const b = Math.min(12, remain - a);
    tiles.push([a, b]);
    remain = 0;
  }
  if (tiles.length === 0) tiles.push([0, 0]);

  const pip = (cx, cy) => <circle cx={cx} cy={cy} r="0.9" fill="#fafaf7" />;
  const pipPositions = (n) => {
    const pos = {
      0: [], 1: [[3, 3]],
      2: [[1.5, 1.5], [4.5, 4.5]],
      3: [[1.5, 1.5], [3, 3], [4.5, 4.5]],
      4: [[1.5, 1.5], [4.5, 1.5], [1.5, 4.5], [4.5, 4.5]],
      5: [[1.5, 1.5], [4.5, 1.5], [3, 3], [1.5, 4.5], [4.5, 4.5]],
      6: [[1.5, 1.2], [4.5, 1.2], [1.5, 3], [4.5, 3], [1.5, 4.8], [4.5, 4.8]],
      7: [[1.5, 1.2], [4.5, 1.2], [1.5, 3], [3, 3], [4.5, 3], [1.5, 4.8], [4.5, 4.8]],
      8: [[1.5, 1.2], [4.5, 1.2], [1.5, 2.6], [4.5, 2.6], [1.5, 3.8], [4.5, 3.8], [1.5, 4.8], [4.5, 4.8]],
      9: [[1.2, 1.2], [3, 1.2], [4.8, 1.2], [1.2, 3], [3, 3], [4.8, 3], [1.2, 4.8], [3, 4.8], [4.8, 4.8]],
      10: [[1.2, 1.2], [3, 1.2], [4.8, 1.2], [1.2, 2.6], [4.8, 2.6], [1.2, 3.8], [4.8, 3.8], [1.2, 4.8], [3, 4.8], [4.8, 4.8]],
      11: [[1.2, 1.2], [3, 1.2], [4.8, 1.2], [1.2, 2.6], [3, 2.6], [4.8, 2.6], [1.2, 3.8], [4.8, 3.8], [1.2, 4.8], [3, 4.8], [4.8, 4.8]],
      12: [[1.2, 1.2], [3, 1.2], [4.8, 1.2], [1.2, 2.6], [3, 2.6], [4.8, 2.6], [1.2, 3.8], [3, 3.8], [4.8, 3.8], [1.2, 4.8], [3, 4.8], [4.8, 4.8]],
    };
    return pos[n] || [];
  };

  return (
    <div style={{
      width: '100%', height: '100%',
      borderRadius: 8,
      background: wood,
      position: 'relative',
      overflow: 'hidden',
      border: `1px solid rgba(0,0,0,0.4)`,
      boxShadow: 'inset 0 0 12px rgba(0,0,0,0.35), 0 1px 2px rgba(0,0,0,0.2)',
    }}>
      {/* faux wood grain stripes */}
      <div style={{
        position: 'absolute', inset: 0,
        backgroundImage: 'repeating-linear-gradient(95deg, rgba(0,0,0,0.08) 0 1px, transparent 1px 4px)',
        pointerEvents: 'none',
      }}/>

      {/* dominoes laid on table */}
      <div style={{
        position: 'absolute', inset: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        gap: 3,
      }}>
        {tiles.map(([a, b], i) => (
          <svg key={i} viewBox="0 0 6 12" width="14" height="28" style={{
            transform: `rotate(${(i - 0.5) * 8}deg)`,
            filter: 'drop-shadow(0 1px 1px rgba(0,0,0,0.5))',
          }}>
            <rect x="0" y="0" width="6" height="12" rx="0.6" fill="#fefcf6"/>
            <line x1="0" y1="6" x2="6" y2="6" stroke="#8a7a5c" strokeWidth="0.15"/>
            {pipPositions(a).map(([x, y], j) => <circle key={'a'+j} cx={x} cy={y} r="0.45" fill="#1c1917"/>)}
            {pipPositions(b).map(([x, y], j) => <circle key={'b'+j} cx={x} cy={y + 6} r="0.45" fill="#1c1917"/>)}
          </svg>
        ))}
      </div>

      {/* player initial badge */}
      <div style={{
        position: 'absolute', top: 3, left: 4,
        fontFamily: theme.mono, fontSize: 8, fontWeight: 800,
        color: '#fafaf7', letterSpacing: '0.05em',
        textShadow: '0 1px 2px rgba(0,0,0,0.6)',
      }}>{player.name.slice(0, 4).toUpperCase()}</div>

      {/* points pill */}
      <div style={{
        position: 'absolute', bottom: 3, right: 4,
        background: 'rgba(0,0,0,0.65)',
        color: theme.accent,
        fontFamily: theme.mono, fontSize: 9, fontWeight: 800,
        padding: '1px 5px', borderRadius: 4,
        letterSpacing: '0.05em',
      }}>{points}</div>

      {/* shutter glint */}
      <div style={{
        position: 'absolute', top: 0, right: 0,
        width: 14, height: 14,
        background: 'radial-gradient(circle at top right, rgba(255,255,255,0.18), transparent 70%)',
        pointerEvents: 'none',
      }}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// CAMERA SCREEN — viewfinder + scan + confirm + submit
// ─────────────────────────────────────────────────────────────
function CameraScreen({ theme, state, onCancel, onSubmit, onSwitchManual, allowManual }) {
  const [phase, setPhase] = useState('aim');     // aim | scanning | confirm
  const [detected, setDetected] = useState(null); // pip count
  const [tiles, setTiles] = useState([]);
  const [manual, setManual] = useState(false);
  const [manualVal, setManualVal] = useState('');

  // Simulated scan
  const scan = () => {
    setPhase('scanning');
    setTimeout(() => {
      const fake = [
        { a: 5, b: 3 }, { a: 9, b: 0 }, { a: 6, b: 4 }, { a: 2, b: 2 }, { a: 11, b: 8 },
      ];
      const total = fake.reduce((s, t) => s + t.a + t.b, 0);
      setTiles(fake);
      setDetected(total);
      setPhase('confirm');
    }, 1100);
  };

  if (manual) {
    return (
      <ManualEntry theme={theme} state={state} value={manualVal} setValue={setManualVal}
        onCancel={onCancel} onSwitchCamera={() => setManual(false)} onSubmit={onSubmit} />
    );
  }

  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      background: '#000', color: '#fff', overflow: 'hidden', position: 'relative',
    }}>
      {/* TOP bar */}
      <div style={{
        padding: '8px 12px', display: 'flex', alignItems: 'center',
        justifyContent: 'space-between', zIndex: 5, background: 'rgba(0,0,0,0.5)',
        backdropFilter: 'blur(8px)', borderBottom: '1px solid rgba(255,255,255,0.08)',
      }}>
        <button onClick={onCancel} style={{
          border: 'none', background: 'rgba(255,255,255,0.1)',
          color: '#fff', fontFamily: theme.mono, fontSize: 10,
          padding: '6px 10px', borderRadius: Math.min(theme.btnRadius ?? 6, 14), letterSpacing: '0.1em',
          cursor: 'pointer',
        }}>← CANCEL</button>
        <div style={{
          fontFamily: theme.mono, fontSize: 10, color: 'rgba(255,255,255,0.7)',
          letterSpacing: '0.14em',
        }}>STOP {state.currentStop}/13 · YOUR HAND</div>
        <button onClick={() => setManual(true)} style={{
          border: '1px solid rgba(255,255,255,0.2)', background: 'transparent',
          color: 'rgba(255,255,255,0.85)', fontFamily: theme.mono, fontSize: 10,
          padding: '6px 10px', borderRadius: Math.min(theme.btnRadius ?? 6, 14), letterSpacing: '0.1em',
          cursor: 'pointer',
        }}>123</button>
      </div>

      {/* VIEWFINDER */}
      <div style={{
        flex: 1, position: 'relative', overflow: 'hidden',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        {/* Fake camera background — wood table feel */}
        <div style={{
          position: 'absolute', inset: 0,
          background: `
            radial-gradient(ellipse at 30% 40%, rgba(140,90,50,0.35), transparent 70%),
            radial-gradient(ellipse at 70% 70%, rgba(60,40,20,0.6), transparent 60%),
            linear-gradient(135deg, #2a1810 0%, #1a0f08 100%)
          `,
        }} />
        {/* Wood grain stripes */}
        <svg style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', opacity: 0.15 }}>
          {Array.from({ length: 30 }).map((_, i) => (
            <line key={i} x1="0" y1={i * 18} x2="100%" y2={i * 18 + 4}
              stroke="#8b5e34" strokeWidth="0.5" />
          ))}
        </svg>

        {/* Detected dominoes */}
        {(phase === 'scanning' || phase === 'confirm') && (
          <div style={{
            position: 'relative', display: 'grid', gridTemplateColumns: 'repeat(3, auto)',
            gap: 14, transform: 'rotate(-4deg)',
          }}>
            {tiles.length === 0
              ? Array.from({ length: 5 }).map((_, i) => <DetectedTile key={i} a={null} b={null} highlight={false} />)
              : tiles.map((t, i) => (
                  <DetectedTile key={i} a={t.a} b={t.b} highlight={phase === 'confirm'} delay={i * 80} theme={theme} />
                ))}
          </div>
        )}

        {/* Aim brackets */}
        {phase === 'aim' && (
          <>
            <AimBrackets accent={theme.accent} />
            <div style={{
              position: 'absolute', top: '50%', left: 0, right: 0,
              transform: 'translateY(-50%)', textAlign: 'center', pointerEvents: 'none',
              fontFamily: theme.mono, fontSize: 11, letterSpacing: '0.18em',
              color: 'rgba(255,255,255,0.85)',
            }}>POINT AT YOUR HAND</div>
          </>
        )}

        {/* Scan reticle line */}
        {phase === 'scanning' && (
          <ScanLine accent={theme.accent} />
        )}

        {/* CONFIRM — large pip count overlay on bottom of image */}
        {phase === 'confirm' && (
          <div style={{
            position: 'absolute', left: 0, right: 0, bottom: 0,
            padding: '40px 16px 16px',
            background: 'linear-gradient(to top, rgba(0,0,0,0.9) 30%, rgba(0,0,0,0.6) 70%, transparent)',
            display: 'flex', alignItems: 'flex-end', justifyContent: 'flex-start', gap: 14,
          }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <div style={{
                fontFamily: theme.mono, fontSize: 10, letterSpacing: '0.20em',
                color: theme.accent, fontWeight: 700, textTransform: 'uppercase',
              }}>✓ {tiles.length} tiles · your pip count</div>
              <div style={{
                fontFamily: theme.display, fontSize: 96, fontWeight: 800,
                color: '#fff', lineHeight: 0.9, letterSpacing: '-0.04em',
                textShadow: '0 4px 24px rgba(0,0,0,0.6)',
              }}>{detected}</div>
              <div style={{
                fontFamily: theme.mono, fontSize: 9, letterSpacing: '0.14em',
                color: 'rgba(255,255,255,0.55)', marginTop: 4,
              }}>EDIT IN AUDIT AFTER SUBMIT</div>
            </div>
          </div>
        )}

        {/* aim status pill */}
        {phase === 'aim' && (
          <div style={{
            position: 'absolute', top: 16, left: '50%', transform: 'translateX(-50%)',
            background: 'rgba(0,0,0,0.6)', color: 'rgba(255,255,255,0.8)',
            padding: '6px 12px', borderRadius: 999, backdropFilter: 'blur(8px)',
            fontFamily: theme.mono, fontSize: 9, letterSpacing: '0.12em',
            display: 'flex', alignItems: 'center', gap: 6, whiteSpace: 'nowrap',
            lineHeight: 1,
          }}>
            <span style={{ width: 6, height: 6, borderRadius: 3, background: '#4ade80', display: 'inline-block', flexShrink: 0 }}/>
            HOLD STILL · GOOD LIGHT
          </div>
        )}
      </div>

      {/* BOTTOM */}
      <div style={{
        background: 'rgba(0,0,0,0.85)', backdropFilter: 'blur(12px)',
        borderTop: '1px solid rgba(255,255,255,0.1)', padding: '14px 16px 22px',
      }}>
        {phase === 'aim' && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div style={{ width: 56 }}/>
            <button onClick={scan} aria-label="Scan" style={{
              width: 72, height: 72, borderRadius: '50%', border: 'none',
              background: '#fff', cursor: 'pointer',
              boxShadow: '0 0 0 4px #000, 0 0 0 6px rgba(255,255,255,0.4)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <div style={{ width: 56, height: 56, borderRadius: '50%', background: theme.accent }}/>
            </button>
            {allowManual ? (
              <button onClick={() => setManual(true)} aria-label="Manual entry" style={{
                width: 56, height: 56, borderRadius: theme.btnRadius ?? 14, border: '1px solid rgba(255,255,255,0.2)',
                background: 'rgba(255,255,255,0.06)', cursor: 'pointer',
                display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
                color: '#fff', fontFamily: theme.mono, fontSize: 9, gap: 2,
                letterSpacing: '0.08em',
              }}>
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <rect x="3" y="4" width="18" height="16" rx="2"/>
                  <path d="M7 9h2M11 9h2M15 9h2M7 13h2M11 13h2M15 13h2M7 17h10"/>
                </svg>
                <span>123</span>
              </button>
            ) : <div style={{ width: 56 }}/>}
          </div>
        )}

        {phase === 'scanning' && (
          <div style={{ textAlign: 'center', padding: '12px 0' }}>
            <div style={{
              fontFamily: theme.mono, fontSize: 11, letterSpacing: '0.16em',
              color: theme.accent, marginBottom: 8,
            }}>SCANNING…</div>
            <div style={{
              height: 4, background: 'rgba(255,255,255,0.1)', borderRadius: 2, overflow: 'hidden',
            }}>
              <div className="cam-progress" style={{
                height: '100%', width: '40%', background: theme.accent,
              }}/>
            </div>
          </div>
        )}

        {phase === 'confirm' && (
          <div style={{ display: 'flex', gap: 8 }}>
            <button onClick={() => { setPhase('aim'); setTiles([]); setDetected(null); }}
              style={secondaryBtn(theme)}>↻ RETAKE</button>
            <button onClick={() => onSubmit(detected)} style={{
              ...primaryBtn(theme), flex: 2,
            }}>ALL ABOARD ✓</button>
          </div>
        )}
      </div>

      <style>{`
        @keyframes camProgress { 0% { transform: translateX(-100%);} 100% { transform: translateX(250%);} }
        .cam-progress { animation: camProgress 1.1s linear infinite; }
        @keyframes tilePop { 0%{transform:scale(0.6);opacity:0;} 100%{transform:scale(1);opacity:1;} }
        .tile-pop { animation: tilePop 0.4s cubic-bezier(0.34,1.56,0.64,1) backwards; }
        @keyframes scanSweep { 0% { top: 18%; } 50% { top: 78%; } 100% { top: 18%; } }
        .scan-line { animation: scanSweep 1.6s ease-in-out infinite; }
      `}</style>
    </div>
  );
}

function stepBtn(theme) {
  return {
    width: 44, height: 44, borderRadius: theme.btnRadius ?? 10, border: '1px solid rgba(255,255,255,0.2)',
    background: 'rgba(255,255,255,0.08)', color: '#fff',
    fontFamily: theme.display, fontSize: 22, fontWeight: 700, cursor: 'pointer',
  };
}
function primaryBtn(theme) {
  return {
    flex: 1, height: 52, borderRadius: theme.btnRadius ?? 12, border: 'none',
    background: theme.cta, color: theme.ctaText,
    fontFamily: theme.display, fontSize: 14, fontWeight: 800,
    letterSpacing: '0.16em', cursor: 'pointer',
  };
}
function secondaryBtn(theme) {
  return {
    flex: 1, height: 52, borderRadius: theme.btnRadius ?? 12,
    border: '1px solid rgba(255,255,255,0.25)',
    background: 'rgba(255,255,255,0.06)', color: '#fff',
    fontFamily: theme.display, fontSize: 14, fontWeight: 700,
    letterSpacing: '0.16em', cursor: 'pointer',
  };
}

function DetectedTile({ a, b, highlight, delay = 0, theme }) {
  const pip = (n, ox, color = '#1c1917') => {
    const layouts = {
      0: [], 1: [[7,7]], 2: [[4,4],[10,10]],
      3: [[4,4],[7,7],[10,10]],
      4: [[4,4],[10,4],[4,10],[10,10]],
      5: [[4,4],[10,4],[7,7],[4,10],[10,10]],
      6: [[4,4],[10,4],[4,7],[10,7],[4,10],[10,10]],
      7: [[4,4],[10,4],[4,7],[10,7],[4,10],[10,10],[7,7]],
      8: [[3,3],[7,3],[11,3],[3,7],[11,7],[3,11],[7,11],[11,11]],
      9: [[3,3],[7,3],[11,3],[3,7],[7,7],[11,7],[3,11],[7,11],[11,11]],
      10: [[3,3],[7,3],[11,3],[3,6],[11,6],[3,9],[11,9],[3,11],[7,11],[11,11]],
      11: [[3,3],[7,3],[11,3],[3,6],[7,6],[11,6],[3,9],[11,9],[3,11],[7,11],[11,11]],
      12: [[3,3],[7,3],[11,3],[3,6],[7,6],[11,6],[3,9],[7,9],[11,9],[3,11],[7,11],[11,11]],
    };
    return (layouts[n] || []).map(([x,y], i) => <circle key={i} cx={x+ox} cy={y} r="1.4" fill={color} />);
  };
  return (
    <div className="tile-pop" style={{
      animationDelay: `${delay}ms`, position: 'relative',
      filter: highlight ? `drop-shadow(0 0 8px ${theme?.accent || '#fff'}88)` : 'none',
    }}>
      <svg width="64" height="32" viewBox="0 0 28 14">
        <rect x="0.5" y="0.5" width="27" height="13" rx="1.5" fill="#fafaf6" stroke="#1c1917" strokeWidth="0.8"/>
        <line x1="14" y1="1" x2="14" y2="13" stroke="#1c1917" strokeWidth="0.6"/>
        {a !== null && pip(a, 0)}
        {b !== null && pip(b, 14)}
      </svg>
      {highlight && a !== null && (
        <div style={{
          position: 'absolute', top: -6, right: -6,
          background: theme?.accent || '#fff', color: '#000',
          fontFamily: theme?.mono || 'monospace', fontSize: 9, fontWeight: 700,
          padding: '2px 5px', borderRadius: 4,
        }}>{a + b}</div>
      )}
    </div>
  );
}

function AimBrackets({ accent }) {
  const sz = 220, t = 3, len = 32;
  const corner = (style) => (
    <div style={{
      position: 'absolute', width: len, height: len, ...style,
    }}/>
  );
  const c = accent;
  return (
    <div style={{ position: 'absolute', width: sz, height: sz * 0.62, top: '50%', left: '50%',
      transform: 'translate(-50%, -50%)' }}>
      {/* corners */}
      <div style={{ position: 'absolute', top: 0, left: 0, width: len, height: t, background: c }}/>
      <div style={{ position: 'absolute', top: 0, left: 0, width: t, height: len, background: c }}/>
      <div style={{ position: 'absolute', top: 0, right: 0, width: len, height: t, background: c }}/>
      <div style={{ position: 'absolute', top: 0, right: 0, width: t, height: len, background: c }}/>
      <div style={{ position: 'absolute', bottom: 0, left: 0, width: len, height: t, background: c }}/>
      <div style={{ position: 'absolute', bottom: 0, left: 0, width: t, height: len, background: c }}/>
      <div style={{ position: 'absolute', bottom: 0, right: 0, width: len, height: t, background: c }}/>
      <div style={{ position: 'absolute', bottom: 0, right: 0, width: t, height: len, background: c }}/>
    </div>
  );
}

function ScanLine({ accent }) {
  return (
    <div style={{
      position: 'absolute', left: '15%', right: '15%', height: 2,
      background: accent, boxShadow: `0 0 16px ${accent}, 0 0 4px ${accent}`,
    }} className="scan-line"/>
  );
}

// ─────────────────────────────────────────────────────────────
// MANUAL ENTRY (camera fallback)
// ─────────────────────────────────────────────────────────────
function ManualEntry({ theme, state, value, setValue, onCancel, onSwitchCamera, onSubmit }) {
  const tap = (k) => {
    if (k === '⌫') setValue(v => v.slice(0, -1));
    else if (value.length < 3) setValue(v => v + k);
  };
  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      background: theme.bg, color: theme.ink, overflow: 'hidden',
    }}>
      {/* header */}
      <div style={{
        padding: '8px 12px', display: 'flex', alignItems: 'center',
        justifyContent: 'space-between', background: theme.headerBg,
        borderBottom: `1px solid ${theme.border}`,
      }}>
        <button onClick={onCancel} style={{
          border: 'none', background: theme.subBg, color: theme.ink,
          fontFamily: theme.mono, fontSize: 10, padding: '6px 10px',
          borderRadius: Math.min(theme.btnRadius ?? 6, 14), letterSpacing: '0.1em', cursor: 'pointer',
        }}>← CANCEL</button>
        <div style={{
          fontFamily: theme.mono, fontSize: 10, color: theme.muted,
          letterSpacing: '0.14em',
        }}>MANUAL · STOP {state.currentStop}/13</div>
        <button onClick={onSwitchCamera} style={{
          border: `1px solid ${theme.border}`, background: 'transparent',
          color: theme.ink, fontFamily: theme.mono, fontSize: 10,
          padding: '6px 10px', borderRadius: Math.min(theme.btnRadius ?? 6, 14), letterSpacing: '0.1em',
          cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4,
        }}>📷</button>
      </div>

      {/* readout */}
      <div style={{
        padding: '20px 16px 10px', textAlign: 'center', flex: '0 0 auto',
      }}>
        <div style={{
          fontFamily: theme.mono, fontSize: 10, color: theme.muted,
          letterSpacing: '0.18em', marginBottom: 6,
        }}>YOUR PIP COUNT</div>
        <div style={{
          fontFamily: theme.display, fontSize: 80, fontWeight: 800,
          color: theme.ink, lineHeight: 1,
        }}>{value || '0'}</div>
        <div style={{
          fontFamily: theme.mono, fontSize: 9, color: theme.muted,
          letterSpacing: '0.14em', marginTop: 8,
        }}>SUM OF PIPS LEFT IN HAND</div>
      </div>

      {/* keypad */}
      <div style={{
        flex: 1, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)',
        gap: 8, padding: '8px 16px',
      }}>
        {['1','2','3','4','5','6','7','8','9','0','⌫'].map((k, i) => {
          if (i === 9) return [
            <div key="empty" style={{ visibility: 'hidden' }}/>,
            <button key="0" onClick={() => tap('0')} style={keyBtn(theme)}>0</button>,
            <button key="del" onClick={() => tap('⌫')} style={{ ...keyBtn(theme), fontSize: 18 }}>⌫</button>,
          ];
          if (i === 10) return null;
          return <button key={k} onClick={() => tap(k)} style={keyBtn(theme)}>{k}</button>;
        }).flat().filter(Boolean)}
      </div>

      {/* submit */}
      <div style={{ padding: '6px 16px 16px', background: theme.subBg, borderTop: `1px solid ${theme.border}` }}>
        <button onClick={() => onSubmit(parseInt(value || '0', 10))} disabled={!value}
          style={{
            width: '100%', height: 52, borderRadius: theme.btnRadius ?? 12, border: 'none',
            background: value ? theme.cta : theme.muted, color: theme.ctaText,
            fontFamily: theme.display, fontSize: 14, fontWeight: 800,
            letterSpacing: '0.16em', cursor: value ? 'pointer' : 'default',
            opacity: value ? 1 : 0.5,
          }}>ALL ABOARD ✓</button>
      </div>
    </div>
  );
}
function keyBtn(theme) {
  return {
    border: `1px solid ${theme.border}`, borderRadius: theme.btnRadius ?? 10,
    background: theme.cardBg, color: theme.ink,
    fontFamily: theme.display, fontSize: 24, fontWeight: 600,
    cursor: 'pointer',
  };
}

// ─────────────────────────────────────────────────────────────
// AUDIT — full screen
// ─────────────────────────────────────────────────────────────
function AuditScreen({ theme, state, audit, onCancel, onSave }) {
  const player = PLAYERS_FULL.find(p => p.id === audit.playerId) || PLAYERS_FULL[0];
  const score = SCORES_FULL[audit.playerId][audit.stopIdx];
  const [val, setVal] = useState(String(score));
  const [audited, setAudited] = useState(true);
  const numVal = parseInt(val || '0', 10);
  const delta = numVal - score;
  const playerTotal = sumPlayer(SCORES_FULL[audit.playerId]) - score + numVal;

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: theme.bg, color: theme.ink, overflow: 'hidden' }}>
      {/* Header */}
      <div style={{
        padding: '8px 14px', display: 'flex', alignItems: 'center',
        justifyContent: 'space-between', background: theme.headerBg,
        borderBottom: `1px solid ${theme.border}`, flexShrink: 0,
      }}>
        <button onClick={onCancel} style={{
          border: 'none', background: theme.subBg, color: theme.ink,
          fontFamily: theme.mono, fontSize: 10, padding: '6px 10px',
          borderRadius: Math.min(theme.btnRadius ?? 6, 14), letterSpacing: '0.1em', cursor: 'pointer',
        }}>← BACK</button>
        <div style={{
          fontFamily: theme.mono, fontSize: 10, color: theme.muted,
          letterSpacing: '0.18em', fontWeight: 700,
        }}>AUDIT · STOP {audit.stopIdx + 1}</div>
        <div style={{ width: 56 }}/>
      </div>

      {/* HERO — who/what + new total */}
      <div style={{
        padding: '14px 14px 12px', flexShrink: 0,
        background: theme.subBg, borderBottom: `1px solid ${theme.border}`,
      }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 10 }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <div style={{ fontFamily: theme.mono, fontSize: 9, letterSpacing: '0.18em', color: theme.muted, fontWeight: 700 }}>PLAYER</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
              <span style={{ fontFamily: theme.display, fontSize: 26, fontWeight: 800, lineHeight: 1, letterSpacing: '-0.01em' }}>{player.name}</span>
              {player.you && <span style={{ fontFamily: theme.mono, fontSize: 9, color: theme.accent, letterSpacing: '0.14em', fontWeight: 700 }}>YOU</span>}
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 2 }}>
              <span style={{ fontFamily: theme.mono, fontSize: 9, letterSpacing: '0.14em', color: theme.muted }}>ENGINE</span>
              <DominoGlyph a={13 - audit.stopIdx - 1} b={13 - audit.stopIdx - 1} w={26} color={theme.ink}/>
            </div>
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontFamily: theme.mono, fontSize: 9, letterSpacing: '0.14em', color: theme.muted, fontWeight: 700 }}>NEW TOTAL</div>
            <div style={{ fontFamily: theme.display, fontSize: 30, fontWeight: 800, lineHeight: 1, color: theme.brand, marginTop: 2 }}>{playerTotal}</div>
            {delta !== 0 && (
              <div style={{ fontFamily: theme.mono, fontSize: 10, color: delta > 0 ? '#b54b2c' : '#3a7a3a', marginTop: 3, fontWeight: 700 }}>
                {delta > 0 ? '+' : ''}{delta} vs recorded
              </div>
            )}
          </div>
        </div>
      </div>

      {/* PIP COUNT EDITOR — big readout + ± + quick chips */}
      <div style={{ padding: '12px 14px 8px', flexShrink: 0 }}>
        <div style={{ fontFamily: theme.mono, fontSize: 9, letterSpacing: '0.18em', color: theme.muted, fontWeight: 700, marginBottom: 4 }}>PIP COUNT</div>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          padding: '4px 10px', borderRadius: 12,
          background: theme.cardBg, border: `1px solid ${theme.border}`,
        }}>
          <button onClick={() => setVal(v => String(Math.max(0, parseInt(v||'0',10) - 1)))} style={stepLight(theme)}>−</button>
          <input value={val} onChange={e => setVal(e.target.value.replace(/\D/g,'').slice(0,3))}
            style={{
              flex: 1, textAlign: 'center', fontFamily: theme.display,
              fontSize: 72, fontWeight: 800, color: theme.ink, background: 'transparent',
              border: 'none', outline: 'none', padding: 0, lineHeight: 1, letterSpacing: '-0.04em',
              minWidth: 0,
            }}/>
          <button onClick={() => setVal(v => String(parseInt(v||'0',10) + 1))} style={stepLight(theme)}>+</button>
        </div>
        <div style={{ display: 'flex', gap: 6, marginTop: 8 }}>
          {[-10, -5, +5, +10].map(d => (
            <button key={d} onClick={() => setVal(v => String(Math.max(0, parseInt(v||'0',10) + d)))}
              style={{
                flex: 1, height: 34, borderRadius: theme.btnRadius ?? 8,
                border: `1px solid ${theme.border}`, background: theme.cardBg,
                color: theme.ink, fontFamily: theme.mono, fontSize: 12, fontWeight: 700,
                letterSpacing: '0.04em', cursor: 'pointer',
              }}>{d > 0 ? `+${d}` : d}</button>
          ))}
        </div>
      </div>

      {/* SCANNED TILES + RE-SCAN */}
      <div style={{ padding: '4px 14px 10px', flexShrink: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
          <div style={{ fontFamily: theme.mono, fontSize: 9, letterSpacing: '0.18em', color: theme.muted, fontWeight: 700 }}>SCANNED TILES · 8</div>
          <button style={{
            border: `1px solid ${theme.border}`, background: theme.cardBg, color: theme.ink,
            fontFamily: theme.mono, fontSize: 9, letterSpacing: '0.12em', fontWeight: 700,
            padding: '4px 10px', borderRadius: Math.min(theme.btnRadius ?? 6, 14), cursor: 'pointer',
          }}>📷 RE-SCAN</button>
        </div>
        <div style={{
          padding: '12px', borderRadius: 10, background: theme.subBg,
          border: `1px dashed ${theme.border}`, display: 'flex', flexWrap: 'wrap', gap: 10,
          alignItems: 'center', justifyContent: 'center',
        }}>
          {[[5,3],[9,0],[6,4],[2,2],[11,8],[10,7],[12,5],[4,1]].map(([a,b], i) => (
            <DominoGlyph key={i} a={a} b={b} w={(theme.tilesOrientation === 'vertical') ? 32 : 56}
              color={theme.ink} orientation={theme.tilesOrientation || 'horizontal'}/>
          ))}
        </div>
      </div>

      {/* REFERENCE PHOTO — captured shot */}
      <div style={{ flex: 1, minHeight: 0, padding: '4px 14px 8px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ fontFamily: theme.mono, fontSize: 9, letterSpacing: '0.18em', color: theme.muted, fontWeight: 700, marginBottom: 4, flexShrink: 0 }}>
          REFERENCE PHOTO · captured {new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
        </div>
        <ReferencePhoto theme={theme}/>
      </div>

      {/* footer actions */}
      <div style={{
        padding: '8px 14px 14px', background: theme.subBg,
        borderTop: `1px solid ${theme.border}`, display: 'flex', gap: 8, flexShrink: 0,
      }}>
        <button onClick={onCancel} style={{
          flex: 1, height: 52, borderRadius: theme.btnRadius ?? 12, border: `1px solid ${theme.border}`,
          background: theme.cardBg, color: theme.ink,
          fontFamily: theme.display, fontSize: 13, fontWeight: 700,
          letterSpacing: '0.12em', cursor: 'pointer',
        }}>DISCARD</button>
        <button onClick={() => onSave(numVal)} style={{
          flex: 2, height: 52, borderRadius: theme.btnRadius ?? 12, border: 'none',
          background: theme.cta, color: theme.ctaText,
          fontFamily: theme.display, fontSize: 13, fontWeight: 800,
          letterSpacing: '0.14em', cursor: 'pointer',
          boxShadow: theme.ctaShadow,
        }}>SAVE CORRECTION</button>
      </div>
    </div>
  );
}

function stepLight(theme) {
  return {
    width: 48, height: 48, borderRadius: theme.btnRadius ?? 10, border: `1px solid ${theme.border}`,
    background: theme.subBg, color: theme.ink,
    fontFamily: theme.display, fontSize: 24, fontWeight: 700, cursor: 'pointer',
    flexShrink: 0,
  };
}

Object.assign(window, {
  Scoreboard, CameraScreen, AuditScreen, ManualEntry,
  PLAYERS_FULL, SCORES_FULL, sumPlayer, DominoGlyph, ReferencePhoto, PhotoGallery, PhotoTile,
});
