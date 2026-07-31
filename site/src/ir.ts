import type { CrepusIr } from "@tschk/crepus-moonshine";

const monoFont = '"Geist Mono", ui-monospace, monospace';

const linkStyle = {
  color: "#fafafa",
  textDecoration: "underline",
  textUnderlineOffset: "3px",
} as const;

const sepStyle = {
  color: "#52525b",
  userSelect: "none",
} as const;

export const pageIr: CrepusIr = {
  version: 1,
  root: [
    {
      kind: "stack",
      axis: "horizontal",
      style: {
        position: "fixed",
        top: "clamp(14px, 2.4vw, 30px)",
        right: "clamp(14px, 2.4vw, 30px)",
        zIndex: "11",
        display: "flex",
        flexWrap: "wrap",
        alignItems: "center",
        justifyContent: "flex-end",
        gap: "0.35rem 0.5rem",
        fontFamily: monoFont,
        fontSize: "clamp(0.75rem, 1.6vw, 0.9rem)",
        color: "#a1a1aa",
        pointerEvents: "auto",
      },
      children: [
        {
          kind: "link",
          href: "https://github.com/tschk/alpenglow/releases/latest",
          target: "_blank",
          rel: "noopener noreferrer",
          content: "latest release",
          style: linkStyle,
        },
        { kind: "text", content: "·", style: sepStyle },
        {
          kind: "link",
          href: "https://github.com/tschk/alpenglow",
          target: "_blank",
          rel: "noopener noreferrer",
          content: "GitHub",
          style: linkStyle,
        },
        { kind: "text", content: "·", style: sepStyle },
        {
          kind: "link",
          href: "https://tsc.hk",
          target: "_blank",
          rel: "noopener noreferrer",
          content: "tsc.hk",
          style: linkStyle,
        },
      ],
    },
    {
      kind: "stack",
      axis: "vertical",
      style: {
        margin: "0",
        height: "100vh",
        overflow: "hidden",
        background: "#000",
        color: "#fff",
        fontFamily: monoFont,
        WebkitFontSmoothing: "antialiased",
      },
      children: [
        {
          kind: "text",
          content: "Alpenglow is an immutable RAM-root Linux distribution with persistent bcachefs-backed state.",
          style: {
            padding: "clamp(28px, 5vw, 64px)",
            color: "#e4e4e7",
            fontSize: "clamp(0.875rem, 2vw, 1.125rem)",
          },
        },
      ],
    },
    {
      kind: "stack",
      axis: "vertical",
      gap: "0.625rem",
      style: {
        position: "fixed",
        bottom: "clamp(14px, 2.4vw, 30px)",
        left: "clamp(14px, 2.4vw, 30px)",
        right: "clamp(14px, 2.4vw, 30px)",
        zIndex: "10",
        display: "grid",
        maxWidth: "130",
        fontFamily: monoFont,
        pointerEvents: "none",
      },
      children: [
        {
          kind: "text",
          content: "loading alpenglow shell",
          style: { margin: "0", color: "#fff" },
        },
        {
          kind: "meter",
          value: 0,
          min: 0,
          max: 100,
          style: { height: "0.75rem", width: "100%", accentColor: "#fff" },
        },
      ],
    },
  ],
};
