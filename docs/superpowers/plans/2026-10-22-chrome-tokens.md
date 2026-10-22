# Токены HomeChrome и светлая тема — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** хром Loupe и кита берёт радиусы, шрифты, отступы, стекло, цвета и затухания из `HomeChrome.Chrome`; окна и Home получают светлую тему по ключу `appearance`, хром поверх фото остаётся тёмным.

**Architecture:** токены и две палитры — значения в `HomeChrome` (без вьюх); `ChromeGlass` и `ChromeToastView` — общие вьюхи там же; кит и Loupe переводят свой хром на них; тема — `NSApp.appearance` из конфига Loupe плюс семантические цвета Home.

**Tech Stack:** Swift 6.2 (кит в `swiftLanguageModes: [.v5]`), AppKit, Swift Testing; Loupe собирается только своими скриптами.

**Spec:** `docs/superpowers/specs/2026-10-22-chrome-tokens-design.md`

## Global Constraints

- Ничего не отправлять на GitHub (никаких `git push`, `gh pr`).
- Кит: корень кита, ветка `chrome-tokens` (от `main`, спецификация уже там). Тесты: `swift test [--filter X]`.
- Loupe: работа и тесты в чекаут LTS (lts/macos26), ветка `chrome-tokens-lts` (создать от `filmstrip-lts`, Task 4), киты в `swift package edit`. Тесты только `scripts/test.sh [--filter X]` (успех: `✔ Loupe core: N tests, all passed`; `cubeBuildTime` может падать под нагрузкой — перезапустить отдельно); сборка `scripts/make-app.sh`. Каждый коммит Loupe потом cherry-pick'ом в чекаут main, ветка `chrome-tokens` (от `main`).
- Не коммитить `Package.resolved`, `Packages/`, `release.yaml`; мешают `git switch` — `git stash push -- Package.resolved`.
- Коммиты: `git -c user.name="Vladimir Selin" -c user.email=418805+ampire5@users.noreply.github.com commit`, трейлеры `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` и `Claude-Session: https://claude.ai/code/session_01UHEgCsxN5juXdhYFYdkB1N`.
- Проекты публичные: никаких личных путей, имён папок и файлов пользователя в коде, тестах, коммитах.
- Главный поток не блокируется; пересчёт цветов — только в `viewDidChangeEffectiveAppearance` / `updateLayer`.
- Значения токенов — ровно из спецификации (разделы 1–2): радиусы `cell 3`, `control 6`, `card 10`, `panel 14`, `capsule(h) = h/2`; кольцо `width 2.5`, `gap 2`; отступы `2 4 6 8 12 16 20`; `Motion.show 0.15`, `hide 0.25`, `select 0.2`; `overMedia`: тинт srgb(22,24,29) α 0.62 / 0.55, ободок белый 0.14, разделитель 0.18, текст 0.92 / 0.7 / 0.5, нажатие 0.2, наведение 0.1, затемнение чёрный 0.45, тень чёрный 0.55.
- Ключи конфига `strip-fade-*`, `toast-duration`, `pan-indicators-fade` и их значения по умолчанию не меняются.

## Review Focus

1. Светлое оформление системы, Loupe в полном экране: лента, язычок, подпись, тосты просмотрщика остаются тёмными — тест `overMediaStaysDarkInLightWindow` (Task 2).
2. `appearance=system`, оформление системы меняется при запущенном приложении: слои Home (`CGColor`) перекрашиваются без перезапуска — тест `cardPlaceholderFollowsAppearance` (Task 6).
3. «Уменьшить движение»: показ и скрытие хрома мгновенные — тест `motionIsInstantWithReduceMotion` (Task 1).
4. `appearance=dark` на светлом Mac: окно Settings тоже тёмное — тест `appearanceKeySetsTheApp` (Task 5).
5. Шпаргалка над ярким фото остаётся читаемой (затемнение под стеклом) — ручная проверка L5, пункт в Task 4.

---

### Task 1: `Chrome` — токены и палитры

**Files:**
- Create: `Sources/HomeChrome/Chrome.swift` (Radius, Ring, Space, Text, Motion), `Sources/HomeChrome/ChromePalette.swift` (Palette.overMedia, Palette.window, resolve).
- Test: `Tests/HomeChromeTests/ChromeTokensTests.swift`.

**Interfaces:**
- Produces:
  - `public enum Chrome` с `enum Radius { static let cell: CGFloat = 3, control = 6, card = 10, panel = 14; static func capsule(_ height: CGFloat) -> CGFloat }`, `enum Ring { static let width: CGFloat = 2.5, gap: CGFloat = 2 }`, `enum Space { static let xxs: CGFloat = 2, xs = 4, s = 6, m = 8, l = 12, xl = 16, xxl = 20 }`.
  - `enum Text { static func font(_ style: Style, weight: NSFont.Weight? = nil) -> NSFont; static func digits(_ style: Style, weight: NSFont.Weight? = nil) -> NSFont }`, `enum Style { case badge, small, label, body, title, heading, hero }` → `NSFont.TextStyle` `.caption1` (semibold), `.subheadline`, `.callout`, `.body`, `.title3` (semibold), `.title2` (semibold), `.title1` (semibold).
  - `enum Motion { static let show: TimeInterval = 0.15, hide = 0.25, select = 0.2; @MainActor static func duration(_ d: TimeInterval, reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) -> TimeInterval }` (0 при reduceMotion).
  - `enum Palette { enum overMedia { static let glassTint: NSColor (srgb 22/255, 24/255, 29/255, α 0.62); glassTintLight (α 0.55); rim (white 0.14); separator (0.18); text (0.92); secondaryText (0.7); tertiaryText (0.5); pressed (0.2); hover (0.1); scrim (black 0.45); mediaShadow (black 0.55); @MainActor static func apply(to view: NSView) } enum window { static let label = NSColor.labelColor, secondaryLabel, tertiaryLabel, separator = .separatorColor, fill = .quaternarySystemFill, background = .windowBackgroundColor, accent = .controlAccentColor } }`.
  - `@MainActor static func Chrome.resolve(_ color: NSColor, in view: NSView) -> CGColor` (цвет в `view.effectiveAppearance`).

- [ ] **Step 1: Тесты** `radiiAndSpaces` (все числа выше, `capsule(28) == 14`), `textStylesMapToSystem` (`font(.body).pointSize == NSFont.preferredFont(forTextStyle: .body).pointSize`, `font(.title)` жирность semibold, `digits(.label)` — моноширинные цифры: `fontDescriptor.featureSettings` не пусто), `overMediaValues` (компоненты srgb и альфы ровно как в Global Constraints), `motionIsInstantWithReduceMotion` (`duration(Chrome.Motion.hide, reduceMotion: true) == 0`, `reduceMotion: false` → 0.25), `resolveFollowsAppearance` (`resolve(.labelColor)` во вьюхе с `aqua` ≠ с `darkAqua`), `overMediaApplyForcesDark` (`apply(to:)` → `effectiveAppearance` darkAqua в окне с `aqua`).
- [ ] **Step 2:** `swift test --filter ChromeTokensTests` — Expected: не собирается (`Chrome` нет).
- [ ] **Step 3:** реализовать по Interfaces; `BrowserLoading.reducesMotion` и частные проверки в Filmstrip пока не трогать (Task 3).
- [ ] **Step 4:** `swift test` — весь кит зелёный.
- [ ] **Step 5:** commit `HomeChrome: tokens for radii, spacing, text styles and motion; the over-media and window palettes`.

### Task 2: `ChromeGlass` и `ChromeToastView`

**Files:**
- Create: `Sources/HomeChrome/ChromeGlass.swift`, `Sources/HomeChrome/ChromeToastView.swift`.
- Test: `Tests/HomeChromeTests/ChromeGlassTests.swift`.

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `@MainActor public final class ChromeGlass: NSView` — `public enum Style: Equatable { case overMedia(Weight), window; public enum Weight { case regular, light } }`, `init(style: Style, cornerRadius: CGFloat)`, `var cornerRadius: CGFloat`, `let contentView: NSView`. `overMedia`: `NSGlassEffectView` с `tintColor = glassTint` / `glassTintLight`, ободок `rim` 1 pt (слой поверх, радиус тот же), `Palette.overMedia.apply(to: self)`. `window`: `NSGlassEffectView` без тинта, ободок `Palette.window.separator`, оформление окна.
  - `@MainActor public final class ChromeToastView: NSView` — `init(style: ChromeGlass.Style)`, `func show(_ text: String, for seconds: TimeInterval)`, `func hide()`, `var isShowing: Bool`; стекло радиуса `Radius.card`, текст `Text.digits(.label)`, отступы `Space.s` / `Space.l`, показ `Motion.show`, скрытие `Motion.hide` (через `Motion.duration`). Цвет текста: `overMedia.text` / `window.label`.

- [ ] **Step 1: Тесты** `overMediaStaysDarkInLightWindow` (окно с `aqua`, `ChromeGlass(.overMedia(.regular))` внутри → `effectiveAppearance.bestMatch([.aqua, .darkAqua]) == .darkAqua`), `windowGlassFollowsWindow` (то же для `.window` → `.aqua`), `glassKeepsRadius` (`cornerRadius = 10` → у стекла и ободка 10), `toastShowsAndHides` (`show("x", for: 0.05)` → `isShowing`, после ожидания ≤ 1 с — нет; `hide()` сразу — нет).
- [ ] **Step 2:** `swift test --filter ChromeGlassTests` — FAIL (нет типов).
- [ ] **Step 3:** реализовать.
- [ ] **Step 4:** `swift test` — зелёный.
- [ ] **Step 5:** commit `HomeChrome: one glass (over media or window) and one toast`.

### Task 3: кит на токенах

**Files:**
- Modify: `Sources/Filmstrip/FilmstripToolsView.swift`, `FilmstripRevealView.swift` (стекло → `ChromeGlass(.overMedia(.regular / .light))`, цвета, `Motion`), `FilmstripLabelView.swift` (`overMedia.apply`, `Text.font(.label)`), `FilmstripView.swift` (радиус ячейки по умолчанию `Radius.cell`); `Sources/HomeChrome/GlassCapsule.swift`, `GlassGroup.swift`, `GlassPill.swift` (шрифты `Text`, `Motion.select`, радиусы `capsule`); `Sources/HomeScreenKit/HomeCard.swift`, `CollectionCard.swift` (радиус `card`, кольцо `Ring`, шрифты), `PhotoCard.swift` (бейджи и тени — `overMedia`, шрифты), `BrowserLoading.swift` (плашка `panel`, `reducesMotion` → `Motion.duration`), `HomeMessageView.swift`, `GridHeader.swift`, `GridFooter.swift`, `HomeScreenView.swift` (шрифты по таблице спецификации); `Sources/homescreen-demo/` — окно «Chrome Demo»: `ChromeGlass` обоих стилей, тост, капсула и язычок ленты, переключатель Light / Dark (`NSApp.appearance`).
- Test: обновить `Tests/FilmstripTests/FilmstripToolsTests.swift` (те же проверки поверх `ChromeGlass`), `Tests/HomeScreenKitTests` — если проверяют радиусы или шрифты.

**Interfaces:**
- Consumes: Tasks 1–2. Цвета Home-карточек (`white 0.14`, `.white` заголовки) здесь **не** меняются — это Task 6 (тема); меняются только радиусы, шрифты, кольцо, движение и всё «поверх фото».

- [ ] **Step 1:** тест `filmstripChromeUsesOneGlass` в `FilmstripToolsTests`: у `FilmstripToolsView` и `FilmstripRevealView` подложка — `ChromeGlass` (поиск по `subviews`), стиль `.overMedia`.
- [ ] **Step 2:** `swift test --filter FilmstripToolsTests` — FAIL.
- [ ] **Step 3:** перевести файлы; литералы радиусов, кеглей и длительностей хрома из списка Files — на токены (фото в `PhotoCard` 1 / 4 — оставить); удалить дублированный код стекла Filmstrip.
- [ ] **Step 4:** `swift test` — зелёный; `swift build --product homescreen-demo` — без ошибок; `grep -rn "NSAppearance(named: .darkAqua)" Sources | grep -v ChromePalette` — только `HomeView`, `HomeScreenView`, `HomeBrowserView` (их снимает Task 6).
- [ ] **Step 5:** commit `Kit chrome on the tokens: the strip's glass is ChromeGlass, cards and capsules take Chrome radii, text styles and motion; a Chrome demo`.

### Task 4: хром просмотрщика Loupe на токенах (сборка L5)

**Files (чекаута LTS, lts/macos26):**
- Создать ветку: `git switch -c chrome-tokens-lts filmstrip-lts` (с `stash` для `Package.resolved`).
- Modify: `Sources/Loupe/ToastView.swift` (обёртка над `ChromeToastView(.overMedia(.regular))`, тот же `show(_:)` для вызывающих), `ConfigWarningsOverlay.swift` (`ChromeGlass` `card`, моноширинный текст остаётся, `Motion`), `StatsBar.swift` (`overMedia` цвета, `Text.digits`), `LoadingIndicator.swift` (цвет дуги `overMedia.text`), `BackButton.swift` (`ChromeGlass(.overMedia(.regular), cornerRadius: Radius.capsule(40))` вместо `GlassBackdrop`; символ — `Text`), `ViewerWindowController.swift` (фейд кнопки «назад» — `Motion.show` / `Motion.hide`), `CheatSheetView.swift` (`ChromeGlass` `panel` + `scrim` вместо `.hudWindow` и чёрной заливки), `StashLibrary.swift` (`ChromeGlass(.window, cornerRadius: Radius.card)` вместо `.hudWindow`).
- Test: существующие тесты Loupe; новых модульных нет (вьюхи приложения) — проверка сборкой и вручную.

**Interfaces:**
- Consumes: Tasks 1–2 (`Chrome`, `ChromeGlass`, `ChromeToastView`).

- [ ] **Step 1:** перевести файлы; `import HomeChrome` там, где нужно (`Loupe` уже зависит от `HomeChrome`; если нет — добавить продукт в `Package.swift` таргета `Loupe`).
- [ ] **Step 2:** `scripts/test.sh` — Expected: `✔ Loupe core: N tests, all passed`.
- [ ] **Step 3:** `grep -rn "hudWindow\|GlassBackdrop\|white: 0.1, alpha: 0.85" Sources/Loupe` — пусто.
- [ ] **Step 4:** `scripts/make-app.sh` — `Built build/Loupe.app` (**L5**). Ручные проверки: тосты, предупреждения конфига, кнопка «назад», индикатор загрузки, статус-бар, шпаргалка над ярким и тёмным фото (читаемость), панель Stash, капсула и язычок ленты — одно стекло, одинаковые радиусы и затухания.
- [ ] **Step 5:** commit `Viewer chrome on HomeChrome: one glass and one toast; cheat sheet and Stash bar leave hudWindow`; cherry-pick в чекаут main `chrome-tokens` (создать от `main`).

### Task 5: ключ `appearance`

**Files:**
- Modify: `Sources/LoupeCore/Config.swift` (`public enum AppAppearance: String, Sendable { case system, light, dark }`, `appearance` по умолчанию `.system`, `set` / `parse` / `text(forKey:)`, ключ в нужных списках), `Sources/LoupeSettings/Pages/PageGeneral.swift` (выбор `System` / `Light` / `Dark`, описание `"Light or dark windows and Home. The photo and everything over it stay dark."`), `Sources/Loupe/AppDelegate.swift` (применение при запуске и при перечитывании настроек), `Sources/LoupeCore/` — чистая функция `AppAppearance.appearanceName -> NSAppearance.Name?` (`.system` → nil, `.light` → `.aqua`, `.dark` → `.darkAqua`).
- Test: `Tests/LoupeCoreTests/ConfigTests.swift`, `Tests/LoupeCoreTests/AppearanceTests.swift`.

**Interfaces:**
- Produces: `Config.appearance: AppAppearance`; `AppAppearance.appearanceName: NSAppearance.Name?`.

- [ ] **Step 1: Тесты** `appearanceWords` (по умолчанию `.system`, `text(forKey: "appearance") == "system"`; `light`, `dark` разбираются без предупреждений; `appearance=sepia` → предупреждение и `.system`), `appearanceKeySetsTheApp` (`AppAppearance.dark.appearanceName == .darkAqua`, `.light` → `.aqua`, `.system` → nil).
- [ ] **Step 2:** `scripts/test.sh --filter "ConfigTests|AppearanceTests"` — FAIL.
- [ ] **Step 3:** реализовать; в `AppDelegate` — `NSApp.appearance = name.flatMap(NSAppearance.init(named:))`.
- [ ] **Step 4:** `scripts/test.sh` — все прошли.
- [ ] **Step 5:** commit `appearance = system | light | dark: windows and Home follow it, the photo stays dark`; cherry-pick в чекаут main.

### Task 6: Home в теме

**Files (кит):**
- Modify: `Sources/HomeScreenKit/HomeView.swift` (снять `darkAqua`; `background` по умолчанию — `Palette.window.background`, пересчёт в `viewDidChangeEffectiveAppearance`), `HomeScreenView.swift`, `HomeBrowserView.swift` (снять `darkAqua`; тост браузера → `ChromeToastView(.window)`; `toolbar.background`), `HomeCard.swift`, `CollectionCard.swift`, `PhotoCard.swift` (подложка `window.fill`, волосок `window.separator`, заголовки `window.label` / `secondaryLabel`; бейджи на фото остаются `overMedia`), `BrowserLoading.swift` (шиммер, текст, плашка — `window`), `HomeMessageView.swift` (`window.label`), `HomeToolbar.swift` (подложка из `window.background`, пересчёт при смене оформления), `HomeSidebar.swift` (акцент и разделитель — пересчёт в `viewDidChangeEffectiveAppearance`). Список мест — приложение A заметки по дизайну.
- Test: `Tests/HomeScreenKitTests/HomeThemeTests.swift`.

**Interfaces:**
- Consumes: Tasks 1–2. `HomeView.background: CGColor` остаётся публичным свойством (Loupe перестаёт его задавать в Task 7).

- [ ] **Step 1: Тесты** `homeIsNotForcedDark` (у `HomeView`, `HomeScreenView`, `HomeBrowserView` `appearance == nil`), `cardPlaceholderFollowsAppearance` (у `HomeCard` в окне `aqua` и `darkAqua` цвет подложки-слоя разный; после смены `window.appearance` и `layoutSubtreeIfNeeded` — меняется), `photoBadgesStayDark` (бейдж `PhotoCard` — `darkAqua`).
- [ ] **Step 2:** `swift test --filter HomeThemeTests` — FAIL.
- [ ] **Step 3:** реализовать.
- [ ] **Step 4:** `swift test` — зелёный; `grep -rn "NSAppearance(named: .darkAqua)" Sources | grep -v ChromePalette` — пусто; `grep -rn "white: 0.14\|gray: 0.14" Sources/HomeScreenKit` — пусто.
- [ ] **Step 5:** commit `Home follows the app's appearance: semantic colours for cards, loading, messages, toolbar and sidebar; over-photo badges stay dark`.

### Task 7: Loupe в теме (сборка L6)

**Files:**
- Modify: `Sources/Loupe/ViewerWindowController.swift` (~L916 `homeView.background = config.background.cgColor` — убрать: фон Home теперь от темы; фон окна просмотра — по-прежнему `background`), всё, что в Loupe рисует Home-подобные поверхности вне просмотра (найти `grep -rn "\.white\b\|white: 0" Sources/Loupe` и разобрать: поверх фото — `overMedia`, окна — `window`).
- Test: существующие; новый `Tests/LoupeCoreTests/` — не нужен, если правка только в приложении.

- [ ] **Step 1:** правки.
- [ ] **Step 2:** `scripts/test.sh` — все прошли.
- [ ] **Step 3:** `scripts/make-app.sh` — **L6**. Ручные проверки: `appearance=system` при светлой и тёмной системе; смена оформления системы на лету; `light` / `dark` на противоположной системе (Home, Settings, листы); полный экран в светлой теме — лента, язычок, тосты тёмные; карточки, тулбар, сайдбар, шиммер загрузки, тост браузера читаются в обеих темах.
- [ ] **Step 4:** commit `Home's background follows the theme, not the viewer's background colour`; cherry-pick в чекаут main.
