# Favorites and File View Tabs Implementation Plan

> Implement using targeted failing regression checks, then verify the kit and both apps together.

**Goal:** Add folder Favorites to Loupe and FrameScrub and persistent File View tabs to FrameScrub's existing player window.

**Architecture:** HomeScreenKit owns common sidebar commands, reorder UI and opt-in tab navigation. Each app owns its saved folders. FrameScrub owns the Last Session lifecycle and the association between a media open and its originating browser tab.

**Tech stack:** Swift, AppKit, SwiftPM, existing app persistence.

## Work

1. HomeScreenKit Favorites. Add a dedicated Favorites section with stable branch identity, reusable menu commands and move callbacks. Exercise overlap with Places and ordering without altering child order. Reorder top-level Favorites by dragging or the menu.
2. Loupe Favorites. Adapt existing BrowserPlaces pins, retaining their order and current Places page and breadcrumb access. Store manual reorder transactionally, refresh the sidebar and preserve existing rename handling. Verify old DB rows and persistence across reopen.
3. FrameScrub Favorites. Persist ordered folder URLs, update matching descendants on rename and check availability off the main thread with bounded waits. Refresh on mount changes and user mutations. Verify offline retention and ordering.
4. HomeScreenKit tabs. Add opt-in controls with one browser and per-tab navigation, selection and scroll state. Activate even on identical locations. Expose selected tab identity and a versioned snapshot. Keep tab strip visible in Home sources and restore the previous folder state on selection. Verify independent back/forward and scroll.
5. FrameScrub tabs and Last Session. Enable tabs, bind return to the originating tab, and use one player. Store a meaningful File View snapshot independently of the launch mode. Use Home or Last Session on empty launch and let explicit file opens take priority. Offer manual Last Session replacing the active set, and load inactive folders only when selected.
6. Build and test all three from the same kit source. Check folder context menus, drag and keyboard reorder, switch between overlapping/same-folder tabs, player return, and empty/direct-file launch paths. Update architecture maps with ownership and data flow.
