// The desktop breakpoint as a media query, in one place for every hook that
// switches between the mobile map stage and the desktop layout (the players
// drawer, the map viewport, the keyboard inset). It is Tailwind's `lg`
// (64rem), the same width as the design system's `--size-collapse` token and
// the `lg:` classes the stage markup uses (docs/mobile-battle-mode.md §3).
// Colocated hooks import it as `@/js/breakpoints` (esbuild's `@` alias).
export const DESKTOP_QUERY = "(min-width: 64rem)"
