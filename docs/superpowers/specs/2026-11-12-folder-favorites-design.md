# Folder Favorites in Loupe and FrameScrub

Favorites gives users a quick way back to folders they use repeatedly. Each app keeps its own list on this Mac. The two apps use the same sidebar and commands.

## Sidebar and commands

- Show a collapsible **Favorites** section above **Places** when there is at least one favorite. The sidebar's **Places** section contains the usual system locations, such as the home folder and mounted volumes.
- A favorite opens its folder on click. Its disclosure control expands the existing folder tree below it. Clicking a folder in Favorites follows that branch when the same path also appears under Places. Removing a favorite leaves the browser at its current folder.
- A folder's context menu in the browser or sidebar offers **Add to Favorites** or **Remove from Favorites**, according to membership. Adding an existing path again has no effect. Only folders qualify.
- Add new favorites at the end. Drag a top-level favorite between other favorites to change its order. Offer **Move Up** and **Move Down** in the context menu for keyboard and assistive access. Reordering preserves the open folder, selection and expanded branches. The existing tree rules still determine the order of subfolders.
- Keep unavailable favorites in their saved positions. Dim their rows and keep removal and reordering available. Refresh availability when a volume returns or the sidebar reloads. Check availability asynchronously so a slow share cannot block interaction.

## Ownership and compatibility

HomeScreenKit supplies the shared Favorites section, context menu behavior and reordering interaction through its existing sidebar and browser. Hosts supply the saved folders, update their own stores, and notify their open Home windows when a list changes.

Loupe reads its existing ordered folder pins as Favorites on first use, preserving their paths and order. In Loupe, favorite folders also remain available in the Places browser page and its breadcrumb menu. FrameScrub starts with an empty list and persists its own order. When either app renames a folder, favorites at or below that folder follow the new path and keep their positions.

## Approaches considered

- Use folder context menus to add and remove favorites, and use dragging within Favorites to reorder. This fits the existing Loupe interaction and lets the empty section stay hidden. This is the chosen approach.
- Also accept folders dropped from Finder or the browser. This gives a second way to add folders and requires a drop target even when the list is empty.

## Acceptance

Open a Loupe state with saved pins and confirm all appear in their previous order. In both apps add a folder from each context menu, expand it, reorder it, relaunch, and confirm the saved order. Check that changes appear in another Home window in the same app and that the other app's list stays independent. With a favorite on a disconnected volume, verify its position, available commands and recovery after reconnecting. Rename a parent folder inside the app and confirm its favorite descendants follow it.
