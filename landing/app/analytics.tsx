"use client";

import { useEffect } from "react";

/**
 * PostHog, set up as on the Lexy landing page: no cookie (so no consent
 * banner), no autocapture, and exactly two events — `$pageview` and
 * `download_clicked` (any click on an element with `data-event`).
 * Imported dynamically, so without NEXT_PUBLIC_POSTHOG_KEY nothing loads.
 */
export default function Analytics() {
  useEffect(() => {
    const key = process.env.NEXT_PUBLIC_POSTHOG_KEY;
    if (!key) return;
    let onClick: ((e: MouseEvent) => void) | undefined;
    let cancelled = false;

    void import("posthog-js").then(({ default: posthog }) => {
      if (cancelled) return;
      posthog.init(key, {
        api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST ?? "https://eu.i.posthog.com",
        persistence: "localStorage",
        autocapture: false,
        capture_pageview: false,
        capture_pageleave: false,
        capture_exceptions: false,
        disable_session_recording: true,
        disable_surveys: true,
        advanced_disable_flags: true,
      });
      posthog.capture("$pageview");

      onClick = (e) => {
        const event = (e.target as Element).closest<HTMLElement>("[data-event]")?.dataset.event;
        if (event) posthog.capture(event);
      };
      document.addEventListener("click", onClick);
    });

    return () => {
      cancelled = true;
      if (onClick) document.removeEventListener("click", onClick);
    };
  }, []);
  return null;
}
