import Notch from "./notch";

// The notarized build that `../build.sh release` uploads to R2.
const DOWNLOAD = "https://dl.yaraoncode.me/tinytimer/TinyTimer.zip";
const REPO = "https://github.com/nemish/tinytimer";

// Newest first. Add a line here with each `../build.sh release`.
const CHANGELOG = [
  ["0.4", "Nov 17, 2026", "Optional focus aid: hide the macOS menu bar clock while the timer runs. Turn it on in Preferences."],
  ["0.3", "Nov 16, 2026", "Pin button on the compact timer, so you can keep it visible without opening the panel."],
  ["0.2", "Nov 14, 2026", "Updates itself: an “Update” button appears when a newer version is out. One click installs it."],
  ["0.1", "Nov 13, 2026", "First release: stopwatch and countdown in the notch, interval chimes, 13 sounds, and Pomodoro-style sessions."],
];

export default function Page() {
  return (
    <>
      <Notch />
      <main>
        <svg className="icon" viewBox="0 0 96 96" aria-hidden="true">
          <rect x="0.5" y="0.5" width="95" height="95" rx="21" />
          <circle cx="48" cy="49" r="32" />
          <polyline points="50,33 50,52 37,45" />
          <circle className="dot" cx="48" cy="17" r="4" />
        </svg>
        <h1>You could vibe-code this in 30&nbsp;minutes.</h1>
        <p>Or just download it. TinyTimer is a stopwatch and countdown that lives in your Mac menu bar.</p>
        <a className="button" href={DOWNLOAD} data-event="download_clicked">
          Download for macOS
        </a>
        <p className="small">
          Have an idea? <a href={`${REPO}/issues`}>Drop an issue on GitHub</a>.
        </p>
      </main>
      <section className="changelog" id="changelog">
        <h2>Changelog</h2>
        <ul>
          {CHANGELOG.map(([version, date, text]) => (
            <li key={version}>
              <b>{version}</b> <time>{date}</time>
              <span>{text}</span>
            </li>
          ))}
        </ul>
      </section>
    </>
  );
}
