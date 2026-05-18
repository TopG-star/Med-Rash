---
name: Cyber-Clinical Brutalism
colors:
  surface: '#131313'
  surface-dim: '#131313'
  surface-bright: '#3a3939'
  surface-container-lowest: '#0e0e0e'
  surface-container-low: '#1c1b1b'
  surface-container: '#201f1f'
  surface-container-high: '#2a2a2a'
  surface-container-highest: '#353534'
  on-surface: '#e5e2e1'
  on-surface-variant: '#cfc2d6'
  inverse-surface: '#e5e2e1'
  inverse-on-surface: '#313030'
  outline: '#988d9f'
  outline-variant: '#4d4354'
  surface-tint: '#ddb7ff'
  primary: '#ddb7ff'
  on-primary: '#490080'
  primary-container: '#b76dff'
  on-primary-container: '#400071'
  inverse-primary: '#842bd2'
  secondary: '#4ae176'
  on-secondary: '#003915'
  secondary-container: '#00b954'
  on-secondary-container: '#004119'
  tertiary: '#4cd7f6'
  on-tertiary: '#003640'
  tertiary-container: '#009eb9'
  on-tertiary-container: '#002f38'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#f0dbff'
  primary-fixed-dim: '#ddb7ff'
  on-primary-fixed: '#2c0051'
  on-primary-fixed-variant: '#6900b3'
  secondary-fixed: '#6bff8f'
  secondary-fixed-dim: '#4ae176'
  on-secondary-fixed: '#002109'
  on-secondary-fixed-variant: '#005321'
  tertiary-fixed: '#acedff'
  tertiary-fixed-dim: '#4cd7f6'
  on-tertiary-fixed: '#001f26'
  on-tertiary-fixed-variant: '#004e5c'
  background: '#131313'
  on-background: '#e5e2e1'
  surface-variant: '#353534'
typography:
  headline-xl:
    fontFamily: Space Grotesk
    fontSize: 64px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Space Grotesk
    fontSize: 40px
    fontWeight: '700'
    lineHeight: '1.2'
  headline-lg-mobile:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.2'
  headline-md:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.3'
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.6'
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.5'
  label-md:
    fontFamily: Space Mono
    fontSize: 14px
    fontWeight: '500'
    lineHeight: '1.0'
    letterSpacing: 0.05em
  label-sm:
    fontFamily: Space Mono
    fontSize: 12px
    fontWeight: '500'
    lineHeight: '1.0'
spacing:
  base: 8px
  gutter: 24px
  margin-mobile: 16px
  margin-desktop: 48px
  border-width: 3px
  shadow-offset: 6px
---

## Brand & Style
The design system establishes a high-impact, neo-brutalist aesthetic tailored for a high-tech medical education environment. It targets healthcare professionals who require immediate information hierarchy presented through a lens of cutting-edge innovation. 

The style is defined by "Cyber-Clinical" principles: raw, unapologetic structures paired with vibrant, electrified accents. It utilizes heavy black borders (`3px` to `4px`), sharp offsets, and a deep charcoal foundation to create a UI that feels both authoritative and experimental. The emotional response is one of precision, urgency, and digital mastery, moving away from traditional sterile medical interfaces toward a high-performance "command center" feel.

## Colors
The palette is rooted in a deep, near-black charcoal (`#0A0A0A`) to ensure maximum contrast for the neo-brutalist elements. 

- **Primary (Electric Violet):** Used for main actions, active states, and brand-defining strokes. It provides a futuristic, high-energy focal point.
- **Secondary (Cyber Green):** Reserved for success states, "Go" actions, and progress indicators, ensuring high visibility against the dark background.
- **Tertiary (Neon Cyan):** Used for supplemental information, info-badges, and technical callouts.
- **Surface:** A slightly lighter charcoal (`#1A1A1A`) is used for card backgrounds to maintain depth while keeping borders prominent.
- **Borders:** Pure black (`#000000`) is used for all structural outlines to maintain the neo-brutalist weight.

## Typography
Typography reflects a fusion of technical precision and bold editorial layout. 

- **Headlines:** Space Grotesk provides a geometric, slightly quirky feel that complements the brutalist borders. It should be used at large scales with tight tracking.
- **Body:** Inter ensures maximum readability for complex medical data and course content. It remains neutral to let the headlines and accents lead the visual narrative.
- **Data/Labels:** Space Mono is used for "meta" information, such as timestamps, durations, and technical specs, reinforcing the "academy of the future" theme.

## Layout & Spacing
This design system utilizes a rigid 12-column grid for desktop and a single-column stack for mobile. Layouts are defined by high-contrast containment. 

Spacing is intentional and generous to prevent the heavy borders from feeling cluttered. We use an 8px base unit. Elements should often "pop" out of their containers using hard-shadow offsets. Components do not use soft margins; they rely on clear, thick-bordered gutters (`24px`) to separate content blocks. 

On mobile, margins compress to `16px` and border widths should reduce to `2px` to preserve screen real estate while maintaining the signature style.

## Elevation & Depth
In neo-brutalism, depth is not achieved through light and shadow (skeuomorphism) but through **hard-edge offsets**.

- **Level 0:** The main background (`#0A0A0A`).
- **Level 1:** Cards and containers with a `3px` black border. 
- **Level 2 (Interactive):** When a user interacts with a card or button, it utilizes a "Hard Shadow"—a solid block of color (Primary or Secondary) offset by `6px` to the bottom-right, creating a faux-3D effect.
- **Level 3 (Active):** Elements shift `-2px` on both axes upon click/tap to simulate a physical "press" into the shadow.

No blurs or gradients are used for elevation. All transitions should be immediate or use a snappy `150ms` linear easing.

## Shapes
The shape language is strictly **Sharp (0)**. To maintain the aggressive, technical aesthetic of neo-brutalism, no rounding is applied to buttons, cards, or input fields. 

The only exception to this rule is for specialized medical icons or progress rings which require circular forms for functional clarity. All structural UI components must maintain 90-degree angles to reinforce the architectural, raw nature of the design.

## Components

- **Buttons:** High-contrast blocks. The primary button is Electric Violet with a black border and a black hard-shadow. Text is centered and uppercase.
- **Cards:** Surface color (`#1A1A1A`) with a `3px` black border. Headers within cards should be separated by a horizontal `3px` black line.
- **Input Fields:** Black background with a white or Electric Violet border. Placeholder text uses the `label-md` mono font for a "terminal" look.
- **Chips/Badges:** Small, rectangular boxes with `1px` borders. Use Cyber Green for status "Live" and Electric Violet for "Pro".
- **Checkboxes/Radios:** Square-only. Checked states fill the entire box with the Primary color and an 'X' or 'Inner Square' rather than a checkmark.
- **Lists:** Items are separated by thick `2px` black lines. Hover states trigger a full-row background color change to a dark tint of the Primary color.
- **Progress Bars:** Flat, non-rounded containers. The progress fill should be a solid Cyber Green with no gradients.