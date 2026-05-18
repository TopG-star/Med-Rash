---
name: Neo-Medical Academy
colors:
  surface: '#f9f9f9'
  surface-dim: '#dadada'
  surface-bright: '#f9f9f9'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f3f3'
  surface-container: '#eeeeee'
  surface-container-high: '#e8e8e8'
  surface-container-highest: '#e2e2e2'
  on-surface: '#1b1b1b'
  on-surface-variant: '#4c4735'
  inverse-surface: '#303030'
  inverse-on-surface: '#f1f1f1'
  outline: '#7e7763'
  outline-variant: '#cfc6af'
  surface-tint: '#705d00'
  primary: '#705d00'
  on-primary: '#ffffff'
  primary-container: '#ffde59'
  on-primary-container: '#756100'
  inverse-primary: '#e4c542'
  secondary: '#00696c'
  on-secondary: '#ffffff'
  secondary-container: '#73f6fb'
  on-secondary-container: '#007073'
  tertiary: '#ad1d7f'
  on-tertiary: '#ffffff'
  tertiary-container: '#ffd4e7'
  on-tertiary-container: '#b22383'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#ffe16e'
  primary-fixed-dim: '#e4c542'
  on-primary-fixed: '#221b00'
  on-primary-fixed-variant: '#544600'
  secondary-fixed: '#73f6fb'
  secondary-fixed-dim: '#52d9de'
  on-secondary-fixed: '#002021'
  on-secondary-fixed-variant: '#004f52'
  tertiary-fixed: '#ffd8e9'
  tertiary-fixed-dim: '#ffaed8'
  on-tertiary-fixed: '#3c0029'
  on-tertiary-fixed-variant: '#890063'
  background: '#f9f9f9'
  on-background: '#1b1b1b'
  surface-variant: '#e2e2e2'
typography:
  headline-lg:
    fontFamily: anybody
    fontSize: 32px
    fontWeight: '800'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  headline-md:
    fontFamily: anybody
    fontSize: 24px
    fontWeight: '800'
    lineHeight: '1.2'
  headline-sm:
    fontFamily: anybody
    fontSize: 20px
    fontWeight: '700'
    lineHeight: '1.2'
  headline-lg-mobile:
    fontFamily: anybody
    fontSize: 28px
    fontWeight: '800'
    lineHeight: '1.1'
  body-lg:
    fontFamily: hankenGrotesk
    fontSize: 18px
    fontWeight: '600'
    lineHeight: '1.5'
  body-md:
    fontFamily: hankenGrotesk
    fontSize: 16px
    fontWeight: '500'
    lineHeight: '1.5'
  label-caps:
    fontFamily: hankenGrotesk
    fontSize: 12px
    fontWeight: '800'
    lineHeight: '1'
    letterSpacing: 0.05em
  data-point:
    fontFamily: anybody
    fontSize: 16px
    fontWeight: '700'
    lineHeight: '1'
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  container-margin: 20px
  gutter: 16px
  stack-sm: 8px
  stack-md: 16px
  stack-lg: 24px
  border-width: 3px
  shadow-offset: 4px
---

## Brand & Style

The design system is built on a **Neo-Brutalist** foundation, specifically tailored for the high-energy environment of gamified medical education. The brand personality is authoritative yet vibrant, stripping away corporate sterility in favor of raw, impactful communication that resonates with Healthcare Professionals (HCPs) in Ghana.

The aesthetic prioritizes clarity and "tap-ability" for quick mobile interactions. It utilizes high-contrast outlines, "hard" drop shadows, and a saturated color palette to create a sense of urgency and accomplishment. The visual language balances professional medical rigor with a playful, competitive edge, ensuring that learning feels less like a chore and more like a high-stakes challenge.

## Colors

The color palette is designed to facilitate instant visual hierarchy through "color-coding" rank and category.

- **Primary (Yellow):** Reserved for top-tier achievements, active user highlights, and primary "Call to Action" buttons.
- **Secondary (Cyan):** Used for secondary rankings, progress indicators, and medical category tagging.
- **Tertiary (Pink):** Dedicated to tertiary rankings, alerts, or specific gamification nodes (e.g., "Special Quizzes").
- **Neutral (Black/White):** Black (#000000) is used exclusively for thick structural borders, hard shadows, and high-impact text. The background is a clean off-white (#FAFAFA) to reduce eye strain while maintaining a high-contrast environment.

A subtle dot-grid pattern using `#E0E0E0` should be applied to the main background to reinforce the "blueprint" or "worksheet" feel of the learning platform.

## Typography

Typography in this design system acts as a structural element. 

- **Headlines:** Using **Anybody** in extra-bold weights creates a loud, confident voice. Headlines should frequently use `uppercase` transformations to mimic the impactful nature of sports and gaming leaderboards.
- **Body & Labels:** **Hanken Grotesk** provides a clean, modern contrast. It ensures that complex medical terminology and long-form learning content remain highly legible on mobile screens.
- **Letter Spacing:** Headlines should feature tight letter spacing for a compact, aggressive look, while labels use wider tracking for clarity at small sizes.

## Layout & Spacing

The design system employs a **Fluid-Fixed hybrid grid**. While the layout fills the mobile viewport width, individual components adhere to a rigid 8px spacing system to maintain a disciplined, "constructed" appearance.

- **Margins:** A standard 20px horizontal margin ensures content does not touch the edge of the glass on mobile devices.
- **Vertical Rhythm:** Elements are stacked using 16px or 24px gaps to allow the heavy borders and shadows "room to breathe."
- **Grid:** Use a 12-column grid for desktop, but prioritize a single-column stack for mobile interactions. The dot-grid background should align with the 8px base unit.

## Elevation & Depth

This design system rejects soft ambient shadows and blurred depth. Hierarchy is established through **Hard Shadows** and **Thick Outlines**.

- **Hard Shadows:** All interactive or elevated cards must use a solid black shadow with a 4px offset (bottom-right: 4px 4px 0px 0px). The shadow has 100% opacity.
- **Active States:** When a user presses a button or card, the shadow offset should reduce to 0px, and the element should translate 4px down and right to simulate a physical "click" or "press."
- **Layering:** Use 3px black borders to separate all interactive surfaces from the background. Surfaces do not use color-based elevation; they stay flat white unless they are a "High Rank" card.

## Shapes

The shape language combines the aggressive nature of Neo-Brutalism with the approachability of modern mobile apps.

- **Core Radius:** Use a consistent **16px (1rem)** radius for all main containers, cards, and input fields.
- **Small Elements:** Buttons and tags should use a **12px (0.75rem)** radius.
- **Avatar Containers:** Avatars should be strictly circular with a 2px black border to contrast against the rectangular geometry of the cards.

## Components

### Buttons
Primary buttons use the Primary Yellow background with a 3px black border and a 4px hard shadow. Text must be `headline-sm` and centered. Secondary buttons use White or Cyan backgrounds with the same border/shadow treatment.

### Leaderboard Cards
Rank cards for #1, #2, and #3 utilize the full brand colors (Yellow, Cyan, Pink respectively). Standard rank cards (#4+) use a White background with a 3px border. All cards feature the 4px hard shadow.

### Input Fields
Inputs are white boxes with 3px black borders and 16px rounded corners. Placeholder text should be in `body-md` using a muted grey, which turns to black when the user starts typing.

### Chips & Tags
Used for medical categories (e.g., "Cardiology", "Emergency"). These are small, 12px rounded capsules with a 2px black border and no shadow, using the Secondary (Cyan) color for high visibility.

### Progress Bars
Thick black stroke (2px) container with a "flat" fill in Primary Yellow. No gradients or glows; the progress should look like a solid block of color moving through a channel.