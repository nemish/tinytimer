import Notch from "./notch";

// The notarized build that `../build.sh release` uploads to R2.
const DOWNLOAD = "https://dl.yaraoncode.me/tinytimer/TinyTimer.zip";
const REPO = "https://github.com/nemish/tinytimer";

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
    </>
  );
}
