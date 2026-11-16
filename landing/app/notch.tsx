"use client";

// A working copy of the app's notch panel (TimerModel + NotchView in ../../main.swift): same state,
// same rules, same sizes. Differences, all because this is a web page:
//  - it opens on hover instead of click/drag, and closes when the pointer leaves;
//  - it stays silent until something in it has been clicked, so nobody gets a surprise bell;
//  - "tink" and "glass" are macOS system sounds the site doesn't ship, so those two are silent;
//  - power "quits" for a moment, then the app comes back in its starting state.
import { type ReactNode, useEffect, useRef, useState } from "react";

const SOUNDS = ["bell", "chime", "bowl", "kalimba", "marimba", "wood", "drop", "tink"];
const RINGS = ["phone", "digital", "melody", "bells", "pulse", "harp"];
const UNSHIPPED = ["tink", "glass"];

type Session = { id: number; start: number; minutes: number[] };
let nextId = 1;
const newSession = (minutes: number[] = []): Session => ({ id: nextId++, start: Date.now(), minutes });

const initial = () => ({
  mode: "countdown" as "stopwatch" | "countdown",
  min: 25,
  elapsed: 23, // seconds; the page opens mid-countdown at 24:37
  running: true,
  pinned: true,
  chimeEvery: 60, // seconds, 0 = off
  chimeRepeat: true,
  sound: "bell",
  volume: 0.3,
  doneSound: "glass",
  doneVolume: 0.5,
  doneRepeat: false,
  sessions: [newSession([25, 25, 25])],
  view: "panel" as "panel" | "prefs" | "sessions",
  finishTab: false,
  off: false,
});
type State = ReturnType<typeof initial>;

const pad = (n: number) => String(n).padStart(2, "0");
function format(s: number) {
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h > 0 ? `${h}:${pad(m)}:${pad(s % 60)}` : `${pad(m)}:${pad(s % 60)}`;
}
/** True when the elapsed time crossed a multiple of `every` between two ticks; once only if !repeats. */
function chimeDue(prev: number, now: number, every: number, repeats: boolean) {
  return every > 0 && Math.floor(now / every) > Math.floor(prev / every) && (repeats || prev < every);
}
function when(start: number) {
  const d = new Date(start);
  const time = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  return d.toDateString() === new Date().toDateString()
    ? `Today ${time}`
    : `${d.getDate()} ${d.toLocaleString("en", { month: "short" })} ${time}`;
}

const ICONS: Record<string, ReactNode> = {
  reset: (
    <>
      <polyline points="1 4 1 10 7 10" />
      <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10" />
    </>
  ),
  play: <path className="solid" d="M7 4l13 8-13 8z" />,
  pause: (
    <>
      <rect className="solid" x="5" y="4" width="5" height="16" rx="1" />
      <rect className="solid" x="14" y="4" width="5" height="16" rx="1" />
    </>
  ),
  gear: (
    <>
      <circle cx="12" cy="12" r="3" />
      <circle cx="12" cy="12" r="7" />
      <circle cx="12" cy="12" r="9.5" strokeWidth="3" strokeDasharray="3.73 3.73" strokeLinecap="butt" />
    </>
  ),
  pinned: <path className="solid" d="M9 2h6v2l-1 1v5l3 3v2h-4v5l-1 2-1-2v-5H7v-2l3-3V5L9 4z" />,
  unpinned: <path strokeWidth="2" d="M9 2h6v2l-1 1v5l3 3v2h-4v5l-1 2-1-2v-5H7v-2l3-3V5L9 4z" />,
  power: (
    <>
      <path d="M18.36 6.64a9 9 0 1 1-12.73 0" />
      <line x1="12" y1="2" x2="12" y2="12" />
    </>
  ),
  back: <polyline points="15 4 7 12 15 20" />,
  x: <path d="M5 5l14 14M19 5L5 19" />,
};

function Chip(p: { on?: boolean; disabled?: boolean; onClick: () => void; children: ReactNode; label?: string }) {
  return (
    <button type="button" className={p.on ? "chip on" : "chip"} disabled={p.disabled} onClick={p.onClick}
      aria-pressed={p.on} aria-label={p.label}>
      {p.children}
    </button>
  );
}
function IconButton(p: { icon: string; label: string; big?: boolean; tiny?: boolean; onClick: () => void }) {
  return (
    <button type="button" className={`ib${p.big ? " big" : ""}${p.tiny ? " tiny" : ""}`} aria-label={p.label}
      onClick={p.onClick}>
      <svg viewBox="0 0 24 24">{ICONS[p.icon]}</svg>
    </button>
  );
}
/** One dot per finished countdown. */
function Dots({ n, cap }: { n: number; cap: number }) {
  return (
    <span className="dots">
      {Array.from({ length: Math.min(n, cap) }, (_, i) => <i key={i} />)}
      {n > cap && <b>+{n - cap}</b>}
    </span>
  );
}

export default function Notch() {
  const [s, setS] = useState(initial);
  const set = (patch: Partial<State>) => setS((old) => ({ ...old, ...patch }));
  const cur = useRef(s);
  cur.current = s;

  // Sound. `clicked` flips on the first click inside the panel; until then nothing plays.
  const clicked = useRef(false);
  const playing = useRef<HTMLAudioElement | null>(null);
  function play(name: string, volume: number, loop = false) {
    playing.current?.pause();
    if (!clicked.current || UNSHIPPED.includes(name)) return;
    const a = new Audio(`/sounds/${name}.mp3`);
    a.volume = volume;
    a.loop = loop;
    a.play().catch(() => {}); // the browser may still refuse; a silent demo is fine
    playing.current = a;
  }
  const playChime = (o: Partial<State> = {}) => play(o.sound ?? cur.current.sound, o.volume ?? cur.current.volume);
  const playDone = (o: Partial<State> = {}) =>
    play(o.doneSound ?? cur.current.doneSound, o.doneVolume ?? cur.current.doneVolume);
  const stopRinging = () => {
    if (playing.current?.loop) playing.current.pause();
  };

  // ponytail: whole-second ticks from setInterval, so a background tab drifts and pausing drops the
  // fraction; switch to the app's start-date arithmetic if the demo ever needs to keep real time.
  useEffect(() => {
    const id = setInterval(() => {
      const c = cur.current;
      if (!c.running) return;
      const now = c.elapsed + 1;
      if (c.mode === "countdown" && now >= c.min * 60) {
        // Finished: back to the full duration, one more dot, and the finish sound.
        const sessions = c.sessions.slice(-200);
        const last = sessions[sessions.length - 1];
        sessions[sessions.length - 1] = {
          ...last,
          start: last.minutes.length ? last.start : Date.now(),
          minutes: [...last.minutes, c.min],
        };
        set({ running: false, elapsed: 0, sessions });
        play(c.doneSound, c.doneVolume, c.doneRepeat);
        if (c.doneRepeat) setTimeout(stopRinging, 60_000); // rings for a minute at most
        return;
      }
      set({ elapsed: now });
      if (chimeDue(c.elapsed, now, c.chimeEvery, c.chimeRepeat)) playChime();
    }, 1000);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const duration = s.min * 60;
  const display = format(s.mode === "stopwatch" ? s.elapsed : Math.max(0, duration - s.elapsed));
  const completed = s.sessions[s.sessions.length - 1].minutes.length;
  const done = s.sessions.filter((x) => x.minutes.length).reverse();

  function toggle() {
    stopRinging();
    set(s.running ? { running: false } : { running: true, elapsed: s.mode === "countdown" && s.elapsed >= duration ? 0 : s.elapsed });
  }
  function reset(patch: Partial<State> = {}) {
    stopRinging();
    set({ running: false, elapsed: 0, ...patch });
  }
  function deleteSession(id: number) {
    const rest = s.sessions.filter((x) => x.id !== id);
    set({ sessions: rest.length && !rest[rest.length - 1].minutes.length ? rest : [...rest, newSession()] });
  }
  function quit() {
    playing.current?.pause();
    set({ off: true });
    setTimeout(() => setS(initial()), 1500);
  }

  const every = s.chimeEvery < 60 ? `${s.chimeEvery}s` : `${s.chimeEvery / 60}m`;
  const chimeSummary = s.chimeEvery === 0 ? "off" : s.chimeRepeat ? `every ${every}` : `once at ${every}`;
  const height = s.view !== "panel" ? 264 : s.mode === "countdown" ? 170 : 136;

  const soundGrid = (title: string, names: string[]) => (
    <div className="row top-aligned">
      <span className="label">{title}</span>
      <div className="grid">
        {[0, 4].map((start) => (
          <div className="row" key={start}>
            {names.slice(start, start + 4).map((name) => (
              <Chip key={name} on={(s.finishTab ? s.doneSound : s.sound) === name}
                onClick={() => {
                  if (s.finishTab) { set({ doneSound: name }); playDone({ doneSound: name }); }
                  else { set({ sound: name }); playChime({ sound: name }); }
                }}>
                {name}
              </Chip>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
  const slider = (key: "volume" | "doneVolume", preview: () => void) => (
    <div className="row">
      <span className="label">Volume</span>
      <input type="range" aria-label="Volume" min="0.05" max="1" step="0.05" value={s[key]}
        onChange={(e) => set({ [key]: Number(e.target.value) })}
        onPointerUp={(e) => { preview(); e.currentTarget.blur(); }} onKeyUp={preview} />
    </div>
  );

  return (
    <div className="top">
      <div className={`notch${s.pinned ? "" : " unpinned"}${s.off ? " off" : ""}`} style={{ "--h": `${height}px` } as React.CSSProperties}
        onClickCapture={() => { clicked.current = true; }} onMouseEnter={stopRinging}
        onMouseLeave={() => set({ view: "panel" })}>
        <div className="compact" aria-hidden="true">
          <i className={s.running ? "run on" : "run"} />
          <span className="time">{display}</span>
          {s.mode === "countdown" && completed > 0 && <Dots n={completed} cap={5} />}
          {s.mode === "countdown" && (
            <span className="ib tiny">
              <svg viewBox="0 0 24 24">{ICONS[s.running ? "reset" : "play"]}</svg>
            </span>
          )}
          <span className="ib tiny pin">
            <svg viewBox="0 0 24 24">{ICONS.pinned}</svg>
          </span>
        </div>

        {s.view === "panel" && (
          <div className="panel">
            <div className="row">
              <i className={s.running ? "run on" : "run"} />
              <span className="time">{display}</span>
              <span className="row push">
                <IconButton icon="reset" label="Reset" onClick={() => reset()} />
                <IconButton icon={s.running ? "pause" : "play"} label={s.running ? "Pause" : "Start"} big onClick={toggle} />
              </span>
            </div>
            <div className="row">
              <Chip on={s.mode === "stopwatch"} onClick={() => reset({ mode: "stopwatch" })}>Stopwatch</Chip>
              <Chip on={s.mode === "countdown"} onClick={() => reset({ mode: "countdown" })}>Countdown</Chip>
              {s.mode === "countdown" && (
                <span className="row push">
                  <Dots n={completed} cap={10} />
                  <Chip onClick={() => set({ view: "sessions" })}>Sessions</Chip>
                </span>
              )}
            </div>
            {s.mode === "countdown" && (
              <div className="row">
                <Chip label="One minute less" onClick={() => set({ min: Math.max(1, s.min - 1) })}>−</Chip>
                <span className="min">{s.min} min</span>
                <Chip label="One minute more" onClick={() => set({ min: Math.min(600, s.min + 1) })}>+</Chip>
                <span className="row push">
                  {[5, 15, 25, 45].map((n) => (
                    <Chip key={n} on={s.min === n} label={`${n} minutes`} onClick={() => set({ min: n })}>{n}</Chip>
                  ))}
                </span>
              </div>
            )}
            <div className="row">
              <Chip onClick={() => set({ view: "prefs" })}>♪ {s.sound} · {chimeSummary}</Chip>
              <span className="row push">
                <IconButton icon="gear" label="Preferences" onClick={() => set({ view: "prefs" })} />
                <IconButton icon={s.pinned ? "pinned" : "unpinned"} label={s.pinned ? "Unpin" : "Pin"} onClick={() => set({ pinned: !s.pinned })} />
                <IconButton icon="power" label="Quit" onClick={quit} />
              </span>
            </div>
          </div>
        )}

        {s.view === "sessions" && (
          <div className="panel">
            <div className="row">
              <IconButton icon="back" label="Back" onClick={() => set({ view: "panel" })} />
              <span className="title">Sessions</span>
              <span className="row push">
                <Chip disabled={completed === 0} onClick={() => set({ sessions: [...s.sessions, newSession()] })}>New session</Chip>
                <Chip disabled={done.length === 0} onClick={() => set({ sessions: [newSession()] })}>Clear all</Chip>
              </span>
            </div>
            {done.length === 0 ? (
              <span className="note">No finished countdowns yet. Each countdown that reaches zero adds a dot.</span>
            ) : (
              <div className="list">
                {done.map((x) => (
                  <div className="row" key={x.id}>
                    <span className={x.id === s.sessions[s.sessions.length - 1].id ? "when current" : "when"}>{when(x.start)}</span>
                    <Dots n={x.minutes.length} cap={16} />
                    <span className="row push">
                      <span className="when">{x.minutes.reduce((a, b) => a + b, 0)} min</span>
                      <IconButton icon="x" label="Delete session" tiny onClick={() => deleteSession(x.id)} />
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {s.view === "prefs" && (
          <div className="panel">
            <div className="row">
              <IconButton icon="back" label="Back" onClick={() => set({ view: "panel" })} />
              <span className="title">Preferences</span>
              <span className="row push">
                <Chip on={!s.finishTab} onClick={() => set({ finishTab: false })}>Chime</Chip>
                <Chip on={s.finishTab} onClick={() => set({ finishTab: true })}>Countdown end</Chip>
              </span>
            </div>
            {soundGrid("Sound", s.finishTab ? SOUNDS.map((n) => (n === "tink" ? "glass" : n)) : SOUNDS)}
            {soundGrid("Ring", RINGS)}
            {s.finishTab ? (
              <>
                {slider("doneVolume", () => playDone())}
                <div className="row">
                  <span className="label">Repeat</span>
                  <Chip on={!s.doneRepeat} onClick={() => set({ doneRepeat: false })}>Once</Chip>
                  <Chip on={s.doneRepeat} onClick={() => set({ doneRepeat: true })}>Repeating</Chip>
                </div>
                <span className="note">
                  {s.doneRepeat ? "Rings until you click the timer (1 min at most)." : "Plays once when a countdown reaches zero."}
                </span>
              </>
            ) : (
              <>
                <div className="row">
                  <span className="label">Chime</span>
                  {([[0, "Off"], [30, "30s"], [60, "1m"], [300, "5m"]] as const).map(([secs, text]) => (
                    <Chip key={secs} on={s.chimeEvery === secs} onClick={() => set({ chimeEvery: secs })}>{text}</Chip>
                  ))}
                </div>
                <div className="row">
                  <span className="label">Repeat</span>
                  <Chip on={s.chimeRepeat} disabled={s.chimeEvery === 0} onClick={() => set({ chimeRepeat: true })}>Repeating</Chip>
                  <Chip on={!s.chimeRepeat} disabled={s.chimeEvery === 0} onClick={() => set({ chimeRepeat: false })}>Once</Chip>
                </div>
                {slider("volume", () => playChime())}
              </>
            )}
          </div>
        )}
      </div>
      <div className="hint" aria-hidden="true">
        <svg viewBox="0 0 40 30">
          <path d="M37 27C32 12 20 6 5 5" />
          <path d="M12 1 5 5l6 6" />
        </svg>
        hover me
      </div>
    </div>
  );
}
