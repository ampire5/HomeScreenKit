# Лента в HomeScreenKit: перенос и режимы — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** механика ленты Loupe переезжает в HomeScreenKit (`FilmstripModel`, `Filmstrip`) без изменения поведения, затем у ленты появляются режимы «поверх / рядом / скрыта» с капсулой на самой ленте.

**Architecture:** модель (раскладка, движение) — чистый Swift без AppKit; вьюха с пулом слоёв, подписью, капсулой и шевроном возврата — AppKit-модуль кита, всё сообщает замыканиями. Loupe оставляет у себя контроллер, маршрут прокрутки, скраб фото и правила режимов (`StripPlacement`, чистая функция).

**Tech Stack:** Swift 6.2 (кит в `swiftLanguageModes: [.v5]`), AppKit, Core Animation, Swift Testing; Loupe собирается только своими скриптами.

**Spec:** `docs/superpowers/specs/2026-10-22-filmstrip-kit-design.md`

## Global Constraints

- Ничего не отправлять на GitHub (никаких `git push`, `gh pr`) — до слова пользователя.
- Кит: ветка `filmstrip-kit` в корне кита (от `origin/main`, уже содержит 2 коммита `home-polish`).
- Loupe: работа и тесты — в чекауте LTS (lts/macos26), ветка `filmstrip-lts` (киты подключены `swift package edit` к локальным чекаутам китов). `main` на этом Intel не собирается. Каждый коммит Loupe потом переносится cherry-pick'ом в чекаут main, ветка `strip-scroll-stack`.
- `Package.resolved` и `Packages/` не коммитить. Мешают `git switch` — `git stash push -- Package.resolved`, после — `git stash pop`.
- Тесты кита: `swift test [--filter X]`. Тесты Loupe: `scripts/test.sh [--filter X]` — успех: строка `✔ Loupe core: N tests, all passed`. Известные нестабильные под нагрузкой: `cubeBuildTime` (Loupe), отдельно проходят.
- `FilmstripModel` не импортирует AppKit.
- Константы раскладки переезжают без изменений: `narrowAspect 0.5625`, `gapRatio 0.028`, `radiusRatio 0.045`, `currentPaddingRatio 0.12`, `fadeRatio 0.85`, `unknownCurrentAspect 1.5`; движения: `lockDistance 4.0`, `restDelay 0.15`, `rubberBand 0.3`.
- Коммиты заканчиваются трейлерами:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` и `Claude-Session: https://claude.ai/code/session_01UHEgCsxN5juXdhYFYdkB1N`.
- Тексты (английские, как в Loupe): предупреждение `loupe.conf:N: 'strip-window=bar' is now 'strip-window=beside'`; тост `In full screen the strip is always over the photo`; подсказки `Keep the strip beside the photo (⇧T)`, `Let the strip float over the photo (⇧T)`, `Pin the strip (T)`, `Unpin the strip (T)`, `Hide the strip (T)`, `Show the strip (T)`.
- Размеры: капсула — 6 pt над верхним краем ленты у правого конца, ячейка кнопки 28 × 24, символ 16 pt; шеврон возврата — 18 × 9 pt по центру, 6 pt от нижнего края, зона показа — 24 pt от нижнего края окна.

## Review Focus

1. Старый конфиг с `strip-window=overlay`: должен стать `over`, а не сброситься к `beside` по умолчанию — тест в Task 5.
2. `⇧T`, пока лента закреплена или спрятана: «спрятана» (режим «рядом») и «закреплена» (режим «поверх») — разные флаги, переключение режима не должно переносить один в другой — тест в Task 6.
3. Вход в полный экран при видимой капсуле: кнопка «где лента» исчезает, шеврон возврата не показывается — тест в Task 6.
4. Колесо мыши (не трекпад) над лентой по-прежнему листает фото (маршрут `.owner`) — тест в Task 3 и `StripRouteTests` в Task 4.
5. Пустая папка и папка из одного файла после переноса: лента без ячеек, без падений — тест в Task 1.

---

## Этап 1 — перенос

### Task 1: `FilmstripModel`: раскладка и мелкие типы

**Files:**
- Modify: `Package.swift` — продукт и таргет `FilmstripModel`, тест-таргет `FilmstripModelTests`.
- Create: `Sources/FilmstripModel/FilmstripLayout.swift` (из `Sources/LoupeCore/StripScrollLayout.swift`), `FilmstripItems.swift` (из `StripPlaylist`), `FilmstripHitZone.swift`, `FilmstripResizeDrag.swift`, `ScrollPhase.swift` (из `LoupeCore/ScrollGestureGuard.swift:1-12`), `FilmstripScrollDirection.swift` (из `Config.swift:13-15`).
- Test: `Tests/FilmstripModelTests/FilmstripLayoutTests.swift`, `FilmstripHitZoneTests.swift`, `FilmstripResizeDragTests.swift` (из соответствующих `Tests/LoupeCoreTests/Strip*Tests.swift`).

**Interfaces:**
- Produces:
  - `public enum FilmstripAxis: Sendable { case horizontal }`
  - `public struct FilmstripCell: Equatable, Sendable { range: Range<Int>; item: Int; start: Double; length: Double }`
  - `public struct FilmstripLayout: Equatable, Sendable` — `init(axis: FilmstripAxis = .horizontal, itemCount: Int, length: Double, thickness: Double, maxAspect: Double, aspects: [Double?])`; свойства `axis`, `itemCount`, `length` (было `width`), `thickness` (было `cellHeight`), `cellLength` (было `cellWidth`), `gap`; методы `narrowLength(of:)`, `centre(of:)`, `item(atBase:) -> Int?`, `offsetRange`, `fadeLength`, `fades(cells:current:) -> (start: Double, end: Double)`, `cells(offset:current:expansion:) -> [FilmstripCell]`; те же статические константы.
  - `public enum FilmstripItems { static func indexMap(from: [URL], to: [URL]) -> [Int: Int] }`
  - `public struct FilmstripHitZone` — `init(length:thickness:padding:)`, `inResizeBand(along:across:)`, `inHoverZone(along:across:)`.
  - `public struct FilmstripResizeDrag` — `init(startThickness:)`, `thickness(forDrag:)`.
  - `public struct ScrollPhase: OptionSet, Sendable` (те же значения), `public enum FilmstripScrollDirection: String, Sendable { case natural, reversed }`.

- [ ] **Step 1: Перенести тесты.** Скопировать 21 тест (`StripScrollLayoutTests` 17, `StripHitZoneTests` 3, `StripResizeDragTests` 1) в `FilmstripModelTests`, заменить имена по таблице Interfaces (`fileCount:`→`itemCount:`, `width:`→`length:`, `cellHeight:`→`thickness:`, `.x`→`.start`, `.width`→`.length`, `file`→`item`, `left/right`→`start/end`, `x:y:`→`along:across:`), импорт `@testable import FilmstripModel`. Значения в проверках не менять. Добавить:

```swift
@Test func emptyAndSingleItem() {
    let empty = FilmstripLayout(itemCount: 0, length: 800, thickness: 68, maxAspect: 1.5, aspects: [])
    #expect(empty.cells(offset: 0, current: 0, expansion: 1).isEmpty && empty.item(atBase: 0) == nil)
    let one = FilmstripLayout(itemCount: 1, length: 800, thickness: 68, maxAspect: 1.5, aspects: [1.5])
    #expect(one.cells(offset: one.centre(of: 0), current: 0, expansion: 1).map(\.item) == [0])
    #expect(one.fades(cells: one.cells(offset: one.centre(of: 0), current: 0, expansion: 1), current: 0) == (0, 0))
}
@Test func axisDefaultsToHorizontal() {
    #expect(FilmstripLayout(itemCount: 3, length: 800, thickness: 68, maxAspect: 1.5, aspects: []).axis == .horizontal)
}
```

- [ ] **Step 2:** `swift test --filter FilmstripModelTests` — Expected: ошибка сборки «no such module 'FilmstripModel'».
- [ ] **Step 3: Перенести код** из LoupeCore с переименованиями; комментарии — в терминах «элемент», «вдоль», «поперёк». В Package.swift: `.library(name: "FilmstripModel", targets: ["FilmstripModel"])`, `.target(name: "FilmstripModel")`, `.testTarget(name: "FilmstripModelTests", dependencies: ["FilmstripModel"])`.
- [ ] **Step 4:** `swift test --filter FilmstripModelTests` — Expected: 23 теста прошли. Затем `swift test` — весь кит зелёный.
- [ ] **Step 5:** commit `FilmstripModel: the strip's layout, hit zone and resize drag move into the kit`.

### Task 2: `FilmstripModel`: движение

**Files:**
- Create: `Sources/FilmstripModel/FilmstripScroll.swift` (из `Sources/LoupeCore/StripScroll.swift` без `Route` и `route(...)`).
- Test: `Tests/FilmstripModelTests/FilmstripScrollTests.swift` (из `StripScrollTests.swift` без `scrollRoutes`, 19 тестов).

**Interfaces:**
- Consumes: `FilmstripLayout`, `ScrollPhase`, `FilmstripScrollDirection` (Task 1).
- Produces: `public struct FilmstripScroll: Sendable` с тем же API, что у `StripScroll`, кроме маршрута: `Outcome(item: Int?, commit: Bool)`, `direction`, `isScrubbing`, `restDeadline`, `offset`, `isMoving`, `event(fingerDelta: Double, crossDelta: Double, phase:momentum:layout:current:now:) -> Outcome`, `drag(by:layout:current:)`, `settled(layout:) -> (item: Int, offset: Double)?`, `settle()`, `layoutChanged(keeping:layout:)`, `rested(now:)`, `takeOver()`, `end()`; константы `lockDistance`, `restDelay`, `rubberBand`.

- [ ] **Step 1:** перенести 19 тестов с переименованиями (`fingerDX:`→`fingerDelta:`, `dy:`→`crossDelta:`, `.file`→`.item`).
- [ ] **Step 2:** `swift test --filter FilmstripScrollTests` — Expected: не собирается, `FilmstripScroll` нет.
- [ ] **Step 3:** перенести код; внутренний `enum Axis` переименовать в `GestureAxis`, чтобы не путать с `FilmstripAxis`.
- [ ] **Step 4:** `swift test --filter FilmstripModelTests` — Expected: 42 теста прошли.
- [ ] **Step 5:** commit `FilmstripModel: the strip's motion (drag, momentum, rubber band, settle)`.

### Task 3: `Filmstrip`: вьюха, подпись, демо

**Files:**
- Modify: `Package.swift` — продукт и таргет `Filmstrip` (зависит от `FilmstripModel`, `HomeChrome`), тест-таргет `FilmstripTests`; `homescreen-demo` зависит ещё от `Filmstrip`.
- Create: `Sources/Filmstrip/FilmstripView.swift` (из `Sources/Loupe/StripView.swift`), `Sources/Filmstrip/FilmstripLabelView.swift` (из `StripLabelView` там же), `Sources/homescreen-demo/FilmstripDemo.swift`; Modify: `Sources/homescreen-demo/main.swift` (пункт меню «Filmstrip Demo»).
- Test: `Tests/FilmstripTests/FilmstripViewTests.swift`.

**Interfaces:**
- Consumes: Task 1, Task 2.
- Produces:
  - `public enum FilmstripScrollRoute: Sendable { case strip, owner, ignore }`
  - `@MainActor public final class FilmstripView: NSView` — тот же набор, что у `StripView`, с переименованиями `file → item`: `static let padding: CGFloat = 6`, `layout: FilmstripLayout`, `setLayout(_:animated:)`, `cornerRadius`, `isOverlay`, `show(offset:current:expansion:animated:)`, `setImage(_:forItem:)`, `setUnavailable`, `forget(_:)`, `remap(_:)`, `forgetAll()`, `showLabel(item:text:)`, `endHover()`, `visibleItems`, `cancelPress()`, `isPressed`, `acceptsMouse`; замыкания `onHover`, `onPress`, `onDrag`, `onDragEnd`, `onVisibleChange`, `onBackingChange`, `onResizeDrag`, `onResizeEnd`, `onResize`, `onScroll` (прокрутка владельца), `onStripScroll` (было `onTrackpadScroll`), новые `routeScroll: ((NSEvent) -> FilmstripScrollRoute)?` (nil — всё `.strip`), `onOtherMouse: ((NSEvent, _ down: Bool) -> Bool)?`, `onOtherMouseDragged: ((NSEvent) -> Void)?`.
  - `@MainActor public final class FilmstripLabelView: NSView` — `text: String`.

- [ ] **Step 1: Тесты маршрута и кнопок.** Помощники в файле теста: `scrollEvent()` — `NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: -10, wheel3: 0)!)!`; `otherMouseEvent(_ type: NSEvent.EventType)` — `NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!`.

```swift
@MainActor @Test func scrollGoesWhereTheOwnerSays() {
    let view = FilmstripView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
    var strip = 0, owner = 0
    view.onStripScroll = { _ in strip += 1 }
    view.onScroll = { _ in owner += 1 }
    view.scrollWheel(with: scrollEvent())                       // no router: the strip's
    view.routeScroll = { _ in .owner }; view.scrollWheel(with: scrollEvent())
    view.routeScroll = { _ in .ignore }; view.scrollWheel(with: scrollEvent())
    #expect(strip == 1 && owner == 1)
}
@MainActor @Test func otherButtonsGoToTheOwner() {
    let view = FilmstripView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
    var downs: [Bool] = []
    view.onOtherMouse = { _, down in downs.append(down); return true }
    view.otherMouseDown(with: otherMouseEvent(.otherMouseDown)); view.otherMouseUp(with: otherMouseEvent(.otherMouseUp))
    #expect(downs == [true, false])
}
@MainActor @Test func showsOnlyVisibleCells() {
    let view = FilmstripView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
    view.setLayout(FilmstripLayout(itemCount: 10_000, length: 400, thickness: 68, maxAspect: 1.5, aspects: []), animated: false)
    view.show(offset: view.layout.centre(of: 5_000), current: 5_000, expansion: 1, animated: false)
    #expect(!view.visibleItems.isEmpty && view.visibleItems.count <= 49 && view.visibleItems.contains(5_000))
}
```

- [ ] **Step 2:** `swift test --filter FilmstripViewTests` — Expected: не собирается, модуля `Filmstrip` нет.
- [ ] **Step 3:** перенести вьюху и подпись; в `scrollWheel` — `switch routeScroll?(event) ?? .strip`; `otherMouseDown/Up` — `onOtherMouse?(event, true/false) == true` иначе `super`; `otherMouseDragged` — `onOtherMouseDragged?(event)`. Никаких `import LoupeCore`, `Settings`, `MouseButtons`. Демо: окно 900 × 140, `FilmstripView` на 10 000 элементов, аспекты по кругу `[1.5, 0.67, 1.33, 0.75, 1, 1.78]`, картинки — `CGImage` сплошного цвета `hue = item * 0.618 mod 1`; движение трекпадом через `FilmstripScroll`, клик — `show(... animated: true)`, подпись `"\(item + 1) / 10000"`.
- [ ] **Step 4:** `swift test` — весь кит зелёный; `swift build --product homescreen-demo` — без ошибок.
- [ ] **Step 5:** commit `Filmstrip: the strip's view and glass label in the kit; buttons and scroll routing go to the owner; a demo`.

### Task 4: Loupe на ките

**Files (чекаута LTS, lts/macos26):**
- Modify: `Package.swift` — `LoupeCore` и `LoupeCoreTests` зависят ещё от `.product(name: "FilmstripModel", package: "HomeScreenKit")`, `Loupe` — от `Filmstrip`, `LoupeBench` — от `FilmstripModel`.
- Delete: `Sources/LoupeCore/StripScrollLayout.swift`, `StripScroll.swift`, `StripHitZone.swift`, `StripResizeDrag.swift`; `Sources/Loupe/StripView.swift`; тесты `StripScrollLayoutTests`, `StripScrollTests`, `StripHitZoneTests`, `StripResizeDragTests`.
- Create: `Sources/LoupeCore/StripRoute.swift`, `Tests/LoupeCoreTests/StripRouteTests.swift` (тест `scrollRoutes` из `StripScrollTests`).
- Modify: `Sources/LoupeCore/ScrollGestureGuard.swift` (определение `ScrollPhase` заменяется на `public typealias ScrollPhase = FilmstripModel.ScrollPhase`), `Config.swift` (`public typealias StripScrollDirection = FilmstripScrollDirection`), `Sources/Loupe/StripController.swift`, `ViewerSession.swift`, `ViewerWindowController.swift`, `Sources/LoupeBench/StripBench.swift` — переход на имена кита.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `MouseButtons.otherMouse(_ event: NSEvent, down: Bool) -> Bool` (в `Sources/Loupe`, обёртка над нынешними `otherMouseDown` / `otherMouseUp`); `public enum StripRoute { static func route(precise: Bool, held: MouseButtons, folderGesture: Bool, pressed: Bool, spent: @autoclosure () -> Bool) -> FilmstripScrollRoute }` (`.viewer` прежнего кода → `.owner`).

- [ ] **Step 1:** перенести `scrollRoutes` в `StripRouteTests` с `StripRoute.route` и `.owner`; `scripts/test.sh --filter StripRouteTests` — Expected: не собирается, `StripRoute` нет.
- [ ] **Step 2:** создать `StripRoute`; удалить переехавшие файлы; typealias'ы; в `StripController` — `FilmstripView`, `FilmstripLayout(itemCount:length:thickness:...)`, `view.routeScroll = { StripRoute.route(precise: $0.hasPreciseScrollingDeltas, held: MouseButtons(rawValue: NSEvent.pressedMouseButtons), folderGesture: Settings.shared.config.folderScrollGesture, pressed: view.isPressed, spent: view.isScrollSpent($0)) }`, `view.onOtherMouse = { MouseButtons.shared.otherMouse($0, down: $1) }` (обёртка над нынешними `otherMouseDown/Up`), `view.onOtherMouseDragged = { MouseButtons.shared.moved($0) }`. Переименование `file → item` в вызовах вьюхи — отдельным коммитом от правок логики не требуется: здесь только вызовы.
- [ ] **Step 3:** `scripts/test.sh` — Expected: `✔ Loupe core: N tests, all passed` (N = 1639 − 41 переехавший = 1598, ± вновь добавленные).
- [ ] **Step 4:** бенч `bash -c '. scripts/libjxl-env.sh && swift run -c release --triple "$LTS_TRIPLE" LoupeBench strip'` — Expected: p99 на событие ≤ 3 мкс, раскладка 1 млн ≤ 7 мс, ячеек ≤ 49 (нынешние 2,5 мкс / 5 мс / 49 с запасом на шум Intel).
- [ ] **Step 5:** `scripts/make-app.sh` — Expected: `Built build/Loupe.app`. Это сборка **L2**; список проверок для пользователя: всё как в прошлой сборке (движение, инерция, пружина, клик, колесо листает фото, подпись, ресайз, растущая папка, полный экран).
- [ ] **Step 6:** commit `Strip: the layout, motion and view come from HomeScreenKit (FilmstripModel, Filmstrip); the scroll route stays here`; cherry-pick в чекаут main `strip-scroll-stack`.

## Этап 2 — режимы и капсула

### Task 5: `strip-window = over | beside | hidden`

**Files:**
- Modify: `Sources/LoupeCore/Config.swift` (`StripWindowMode`, `stripWindow`, `set`, `parse`), `Sources/LoupeSettings/Pages/PageStrip.swift` (слова и описание), все `.overlay/.bar/.off` в `Sources/Loupe/StripController.swift`.
- Test: `Tests/LoupeCoreTests/ConfigTests.swift`.

**Interfaces:**
- Produces: `public enum StripWindowMode: String, Sendable { case over, beside, hidden }`; `Config().stripWindow == .beside`; `Config.renamedValues: [String: [String: String]]` = `["strip-window": ["overlay": "over", "bar": "beside", "off": "hidden"]]`.

- [ ] **Step 1: тесты**

```swift
@Test func stripWindowWords() {
    #expect(Config().stripWindow == .beside && Config().text(forKey: "strip-window") == "beside")
    for (word, mode) in [("over", StripWindowMode.over), ("beside", .beside), ("hidden", .hidden)] {
        let (c, w) = Config.parse("strip-window=\(word)")
        #expect(c.stripWindow == mode && w.isEmpty)
    }
}
@Test func stripWindowOldWordsStillWork() {
    for (old, new, mode) in [("overlay", "over", StripWindowMode.over), ("bar", "beside", .beside), ("off", "hidden", .hidden)] {
        let (c, w) = Config.parse("strip-window=\(old)")
        #expect(c.stripWindow == mode)
        #expect(w == ["loupe.conf:1: 'strip-window=\(old)' is now 'strip-window=\(new)'"])
    }
    var c = Config(); #expect(c.set("strip-window", "overlay") == .ok && c.stripWindow == .over)
}
```
Обновить старые проверки `.overlay/.bar/.off` в `ConfigTests` (строки с `stripWindow`).
- [ ] **Step 2:** `scripts/test.sh --filter ConfigTests` — Expected: FAIL (`over` не разбирается).
- [ ] **Step 3:** значения; `set` принимает старые слова через `renamedValues`; `parse` после `.ok` добавляет предупреждение, если слово было старым. `PageStrip`: `(word: "beside", title: "Beside")`, `("over", "Over")`, `("hidden", "Hidden")`, описание: `"Beside: a band under the photo; Over: appears with the mouse at the bottom edge and hides itself; Hidden: no strip. ⇧T switches Beside and Over, T hides or pins. Full screen always has it over. Default Beside."`.
- [ ] **Step 4:** `scripts/test.sh` — все прошли.
- [ ] **Step 5:** commit `strip-window: over | beside | hidden (overlay | bar | off still read, with a warning)`.

### Task 6: `StripPlacement` — правила режимов

**Files:**
- Create: `Sources/LoupeCore/StripPlacement.swift`.
- Test: `Tests/LoupeCoreTests/StripPlacementTests.swift`.

**Interfaces:**
- Produces:

```swift
public struct StripPlacement: Equatable, Sendable {
    public struct Input: Equatable, Sendable {
        public var mode: StripWindowMode; public var fullScreen: Bool
        public var hidden: Bool   // T in beside (persisted `stripBarHidden`)
        public var pinned: Bool   // T in over (persisted `stripPinned`)
        public var pointerOverStrip: Bool; public var pointerNearBottom: Bool  // within 24 pt of the window's bottom
        public var revealedByEdge: Bool  // over: the strip is out because the pointer reached its edge, hovers or moves
    }
    public enum Pin: Equatable, Sendable { case pin(on: Bool), hide }   // the capsule's T button
    public let visible: Bool, reservesSpace: Bool
    public let placeButton: Bool      // ⇧T button in the capsule
    public let pin: Pin?              // T button in the capsule (nil: no capsule)
    public let showsCapsule: Bool, showsReveal: Bool
    public init(_ input: Input)
    /// ⇧T: the mode to write, nil when nothing changes (full screen).
    public static func toggledMode(_ mode: StripWindowMode, fullScreen: Bool) -> StripWindowMode?
}
```

- [ ] **Step 1: тесты** (имена и проверки):
  - `besideShownReservesSpace`: beside, не hidden → visible, reservesSpace, капсула только при `pointerOverStrip`, `pin == .hide`, `placeButton`.
  - `besideHiddenShowsRevealNearBottom`: beside+hidden → не visible, не reservesSpace, `showsReveal == pointerNearBottom`, капсулы нет.
  - `overFollowsTheEdgeOrPin`: over → visible = `pinned || revealedByEdge`, reservesSpace false, `pin == .pin(on: pinned)`, нет reveal.
  - `hiddenModeShowsNothing`: hidden → ничего не видно, ни капсулы, ни reveal.
  - `fullScreenIsAlwaysOver`: для любого mode при fullScreen → поведение over; `placeButton == false`; `showsReveal == false`.
  - `hiddenAndPinnedStayApart`: beside+hidden+pinned=false → после смены mode на over с теми же флагами visible зависит только от `pinned`/edge (флаг hidden не прячет over).
  - `toggledModes`: `toggledMode(.beside, false) == .over`, `(.over, false) == .beside`, `(.hidden, false) == .beside`, `(.beside, true) == nil`.
- [ ] **Step 2:** `scripts/test.sh --filter StripPlacementTests` — Expected: не собирается.
- [ ] **Step 3:** реализовать по таблице состояний спецификации (раздел 2).
- [ ] **Step 4:** все тесты прошли.
- [ ] **Step 5:** commit `StripPlacement: what the strip shows in each mode, pinned or hidden, in a window and full screen`.

### Task 7: клавиша `⇧T`

**Files:**
- Modify: `Sources/LoupeCore/KeyMap.swift` (действие, привязка до `t`, шпаргалка), `Sources/Loupe/ViewerView.swift:1492` (диспетчер действий: `onToggleStripPlacement`).
- Test: `Tests/LoupeCoreTests/KeyMapTests.swift`.

**Interfaces:**
- Produces: `KeyAction.toggleStripPlacement`, заголовок `"Strip beside or over the photo"` в группе `.view`; `ViewerView.onToggleStripPlacement: (() -> Void)?`.

- [ ] **Step 1: тест** `shiftTPlacesTheStrip`: `lookup` для `t` без модификаторов → `.toggleStrip`, с `.shift` → `.toggleStripPlacement`; `label(.toggleStripPlacement).keys == "⇧T"`.
- [ ] **Step 2:** запустить — FAIL.
- [ ] **Step 3:** `KeyBinding(character: "t", modifiers: .shift, allowsRepeat: false, action: .toggleStripPlacement)` перед привязкой `t`; действие в списках, где стоит `.toggleStrip` (`KeyMap.swift:165`).
- [ ] **Step 4:** все тесты прошли.
- [ ] **Step 5:** commit `⇧T switches the strip between beside and over the photo`.

### Task 8: капсула и шеврон возврата в ките

**Files (кит):**
- Create: `Sources/Filmstrip/FilmstripToolsView.swift`, `Sources/Filmstrip/FilmstripRevealView.swift`.
- Test: `Tests/FilmstripTests/FilmstripToolsTests.swift`.

**Interfaces:**
- Produces:
  - `public struct FilmstripTool { public var symbol: String; public var help: String; public var isOn: Bool; public var action: @MainActor () -> Void }`
  - `@MainActor public final class FilmstripToolsView: NSView` — `tools: [FilmstripTool]` (пересобирает кнопки: `NSButton`, без рамки, символ 16 pt, ячейка 28 × 24, `toolTip = help`, `isOn` → `.on`), `setShown(_ shown: Bool, animated: Bool)` (альфа 0/1 за 0,15 с; скрытая не принимает клики). Фон — `GlassCapsule` из `HomeChrome`.
  - `@MainActor public final class FilmstripRevealView: NSView` — шеврон `chevron.up` 18 × 9, `onReveal: (() -> Void)?`, `setShown(_:animated:)`.

- [ ] **Step 1: тесты** `toolsBuildButtons` (2 инструмента → 2 кнопки, подсказки и `state` совпадают), `toolActionRuns` (`performClick` на второй → action вызван один раз), `hiddenToolsTakeNoClicks` (`setShown(false, animated: false)` → `hitTest` возвращает nil), `revealCallsBack`.
- [ ] **Step 2:** `swift test --filter FilmstripToolsTests` — FAIL.
- [ ] **Step 3:** реализовать.
- [ ] **Step 4:** `swift test` — кит зелёный.
- [ ] **Step 5:** commit `Filmstrip: the strip's tool capsule and the chevron that brings a hidden strip back`.

### Task 9: режимы в Loupe

**Files (Loupe):**
- Modify: `Sources/Loupe/StripController.swift` (вместо нынешних `mode/pinned/barHidden/placement/update` — `StripPlacement`; капсула и шеврон; удалить `chevron`, `chevronAboveStrip`, `chevronAtBottom`, зону нижней трети), `Sources/Loupe/Settings.swift` (`func setStripWindow(_ mode: StripWindowMode)` через `change(["strip-window"])`), `Sources/Loupe/ViewerWindowController.swift` (`viewerView.onToggleStripPlacement`), `Sources/Loupe/AppDelegate.swift` (пункт меню View «Strip Beside the Photo» ⇧T, галочка = `beside`), `Sources/LoupeCore/KeyMap.swift` шпаргалка — строки мыши про шеврон.

**Interfaces:**
- Consumes: `StripPlacement` (Task 6), `KeyAction.toggleStripPlacement` (Task 7), `FilmstripToolsView`, `FilmstripRevealView`, `FilmstripTool` (Task 8), `StripWindowMode` (Task 5).
- Produces: `StripController.togglePlacement()` (`⇧T`): в полном экране — тост из Global Constraints, иначе `Settings.shared.setStripWindow(StripPlacement.toggledMode(...)!)`.

- [ ] **Step 1:** капсула: инструменты по `StripPlacement.placeButton` и `.pin` — «где лента» (`rectangle.bottomthird.inset.filled`, `isOn` в beside; подсказка `Let the strip float over the photo (⇧T)` в beside, `Keep the strip beside the photo (⇧T)` в over), `T`-кнопка (`pin`/`pin.fill` с `Pin`/`Unpin the strip (T)`; `chevron.down` с `Hide the strip (T)`). Положение — правый конец ленты, 6 pt над ней. Шеврон возврата — `Show the strip (T)`, 6 pt от нижнего края, зона 24 pt.
- [ ] **Step 2:** `scripts/test.sh` — Expected: всё прошло (логика режимов покрыта Task 6).
- [ ] **Step 3:** `scripts/make-app.sh` — сборка **L3**. Список ручных проверок: (1) рядом: капсула только над лентой, две кнопки, `T`/шеврон прячут, шеврон у края возвращает; (2) `⇧T` и кнопка «где лента» — поверх ↔ рядом, `loupe.conf` получает новое слово; (3) поверх: булавка и `T` закрепляют, без булавки лента уходит через 200 мс; (4) полный экран: кнопки «где лента» нет, шеврона у края нет, `⇧T` — тост; (5) старый `strip-window=bar` в конфиге — предупреждение и режим «рядом»; (6) `hidden` — ленты нет, `⇧T` → рядом.
- [ ] **Step 4:** commit `Strip modes over / beside / hidden with a capsule on the strip and a chevron at the edge; the bottom-third chevron goes`; cherry-pick Tasks 5–9 в чекаут main `strip-scroll-stack`.
