// Navigation manifest for the Proximi.io Flutter map documentation site.
//
// Single source of truth for sidebar order, page titles in breadcrumbs and pagers, and which
// fragments the build expects under `content/`. A nav entry with slug "a/b" is fed by
// `content/a/b.html`; the empty slug "" is fed by `content/index.html`.
//
// The section set mirrors the Android map site (`proximiio-android-sdk-v6/docs/map-site/nav.mjs`)
// and the iOS map docs: same order, same slugs where the page exists. Flutter-only pages (the
// platform view) are additions inside the existing sections. Compose/View API pages have one
// Flutter counterpart, the widget page.

export const SITE = {
  /** Product name shown in the header lockup. */
  name: "Proximi.io Flutter map",
  /** Eyebrow under the product name. */
  version: "v6",
  /** Suffix appended to every <title>. */
  titleSuffix: "Proximi.io Flutter map v6",
  /** Repository link in the header. */
  repoUrl: "https://github.com/proximiio/flutter-proximiio-map",
};

/**
 * @typedef {{ slug: string, label: string }} NavItem
 * @typedef {{ label: string, collapsed?: boolean, items: NavItem[] }} NavSection
 * @type {NavSection[]}
 */
export const NAV = [
  {
    label: "Getting started",
    items: [
      { slug: "", label: "What the Flutter map is" },
      { slug: "getting-started/installation", label: "Installation" },
      { slug: "getting-started/first-map", label: "Your first map" },
    ],
  },
  {
    label: "Core concepts",
    items: [
      { slug: "concepts/platform-view", label: "The platform view" },
      { slug: "concepts/style", label: "The organization style" },
      { slug: "concepts/levels", label: "Floors" },
    ],
  },
  {
    label: "Guides",
    items: [
      { slug: "guides/position", label: "The blue dot" },
      { slug: "guides/route", label: "Routes" },
      { slug: "guides/guidance", label: "Turn-by-turn guidance" },
      { slug: "guides/journeys", label: "Multi-stop journeys" },
      { slug: "guides/camera", label: "Camera and insets" },
      { slug: "guides/features", label: "Venue features and taps" },
      { slug: "guides/languages", label: "Languages" },
      { slug: "guides/geofences", label: "Geofence display" },
      { slug: "guides/offline", label: "Offline" },
      { slug: "guides/attribution", label: "Attribution and licences" },
    ],
  },
  {
    label: "API",
    items: [
      { slug: "api/widget", label: "ProximiioMap" },
      { slug: "api/controller", label: "ProximiioMapController" },
      { slug: "api/options", label: "MapOptions" },
      { slug: "api/guidance", label: "Route guidance types" },
      { slug: "api/journeys", label: "Journey types" },
    ],
  },
  {
    label: "Reference",
    items: [
      { slug: "reference/platform-differences", label: "Platform differences" },
      { slug: "reference/troubleshooting", label: "Troubleshooting" },
      { slug: "reference/versioning", label: "Versioning and releases" },
      { slug: "reference/migration", label: "Migrating from 1.x" },
    ],
  },
];
