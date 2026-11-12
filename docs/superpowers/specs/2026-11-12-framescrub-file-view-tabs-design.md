# File View tabs in FrameScrub

Keep several working folders open in FrameScrub's main window. All tabs use the window's existing player. Folder Favorites in FrameScrub and Loupe are covered by the [Favorites design](2026-11-12-folder-favorites-design.md).

## Navigation

- Put the tab strip in File View above the browser. Each tab is named for its current folder. Show the full path on hover so folders with the same name can be distinguished. Provide a visible **+** and controls for switching, closing and reordering tabs.
- **+** opens the current folder in a new tab with its own history. When there is no current folder, use the last browsed folder or Places. **Open in New Tab** opens the chosen folder and selects the new tab. Offer it on folder cards and folder rows, including Favorites. The last remaining tab stays open when its close action is invoked.
- Each tab remembers its current location, back and forward history, selected card, and scroll anchor while FrameScrub is running. A tab at the browser's top level is titled **Places**. The shared sidebar, toolbar and inspector follow the selected tab. Opening an app source such as Recent or Stash parks the folder tabs and keeps their strip visible. Clicking any folder tab resumes it. Closing a parked tab leaves the app source visible.
- Opening a video uses the existing player and records the tab it came from. Returning to File View selects that tab and the last opened video when it is still present. Media opened directly from Finder follows the existing return behavior.

## Last Session

Use Loupe's **At launch** design. **Home** is the default. **Last Session** restores the saved File View tabs on a launch without a file. A file opened directly takes priority. Opening **Last Session** manually from Home replaces the current File View tabs with the saved set.

Save a versioned snapshot of tab locations (folder or Places), order and the selected tab, plus each tab's selection and scroll anchor. Keep the last meaningful snapshot separate from current activity so that opening to blank Home or opening a video directly leaves Last Session available. If the user browses folders and then closes back to a single Places tab, save that state as well. Ignore snapshots the app cannot decode. Restore the active tab first and defer folder listing for the others until selected. Restored tabs start with fresh back and forward histories. An unavailable folder keeps its tab so it can be retried after reconnecting. Session restoration covers File View and uses the existing playback resume behavior.

## Implementation approach

Use one HomeView and one browser per window. HomeScreenKit keeps each tab's navigation state and displays the strip when the host enables tabs. On a switch, capture the outgoing state, activate the incoming state and use the browser's cancellation and cached listing paths. Only the visible tab subscribes to listings, watches a folder and asks for thumbnails. Late results from a previous tab must not replace the visible listing, including when two tabs point to the same path. FrameScrub owns persistence and binds its existing player return route to the originating tab ID.

A separate browser per tab would retain each view directly, but would require isolating the current single-browser source callbacks and carefully parking every hidden view. Using the existing HomeView with separate navigation state fits the shared source and player.

## Acceptance

Open two folders using the context menu and **+**, navigate in each, then switch between them and verify history, selection and scroll are independent. Reorder and close tabs. Open a video from the second tab and return to it through the same player. Switch quickly between folders, including an unavailable share, and verify results only update the selected tab. Verify the **Home** and **Last Session** launch choices, manual restore, saved order and active tab, and opening directly into a video from Finder. Check tab switching and folder listing work against the existing responsiveness requirements.
