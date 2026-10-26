# Битые файлы: одно знание для сетки, полосы, просмотрщика и плеера — дизайн

Дата: 2026-10-27. Ветки `polish-2` (HomeScreenKit, Loupe, FrameScrub), локально, без push. Продолжение
`2026-10-27-folder-playlist-design.md` (этап 3).

## Решения пользователя

- При листании битый файл **молча пропускается** в обоих приложениях; файл, открытый по имени, показывает ошибку.
  FrameScrub при листании вместо экрана «Cannot open» — короткое «‹имя›: skipped».
- **Битый** — файл, который не читает декодер. Ошибка чтения (шара ушла, нет доступа, память) битым не делает.
- Знание живёт **до конца работы приложения**, привязано к дате и размеру файла: изменившийся файл снова неизвестен.
- Подход А: хранилище в ките; сетка читает его сама.

## Кит (HomeScreenModel / HomeScreenKit)

`UnreadableFiles` — `@MainActor final class`, одна на приложение:

- `mark(_ url: URL, date: Date?, size: Int64?)`, `clear(_ url: URL)`;
- `contains(_ url: URL, date: Date?, size: Int64?) -> Bool`, `contains(_ entry: BrowserEntry) -> Bool`: URL
  стандартизуются; дата и размер сравниваются, только когда известны с обеих сторон;
- `observe(_ change: @escaping (Set<URL>) -> Void) -> UnreadableFiles.Observation` — наблюдатель живёт, пока жив
  токен; вызывается синхронно с изменившимися URL; повторная отметка без изменений никого не будит.

`FolderPlaylist.index(from: Int, step: Int, skipping: (BrowserEntry) -> Bool) -> Int?` — `from` или первый за ним
в направлении шага, кому `skipping` не true; nil за краем.

`HomeBrowserView.unreadable: UnreadableFiles?` — карточки файлов, которые в нём, бледные; стрелки их пропускают
(вместе с `setUnavailable`); при изменении перерисовываются только живые карточки изменившихся URL.
`setUnavailable(_:for:)` остаётся публичным API.

## Loupe

- Одно `UnreadableFiles` (AppDelegate) → сетка каждого окна (`HomeBrowserView.unreadable`), `StripController`,
  `ViewerSession`.
- Превью: генератор различает исход — ошибка декодера (`DecodeError.unreadable`) → `unavailable` (как сейчас:
  `status == .unavailable`); ошибка чтения → новый набор `readFailed`, только чтобы очередь не повторяла файл
  бесконечно (сбрасывается там же, где `unavailable`); `status` для него — `.pending`. `FolderBrowserSource` и
  `StripController` при `.unavailable` отмечают файл в хранилище (дата/размер — из `FileStamp` листинга, если есть);
  ручной `setUnavailable` в `FolderBrowserSource` уходит.
- Полоса: `StripController` наблюдает хранилище и ставит `setUnavailable(forItem:)` своим ячейкам.
- Просмотрщик: `brokenFiles` и его сброс при смене папки уходят; шаг пропускает отмеченные через
  `Playlist`→`FolderPlaylist.index(from:step:skipping:)`; ошибка декодера отмечает файл всегда, а при шаге (не по
  имени, не из полосы, не в режиме двух страниц) — идёт дальше, как `skipBroken` сейчас; удачное открытие снимает
  отметку.

## FrameScrub

- Одно `UnreadableFiles` (AppDelegate) → `FrameScrubHomeSource` (`view.unreadable`) и `PlayerWindowController`.
- Ошибка открытия с `OpenFailure.Kind` `.damaged` / `.noVideo` → отметка (дата/размер — из записи листинга папки).
  Если файл открыт шагом по папке (‹ ›, ⏮ ⏭, автопереход) — переход к следующему в том же направлении мимо
  отмеченных и сообщение «‹имя›: skipped»; открыт по имени — экран «Cannot open», как сейчас. Удачное открытие
  снимает отметку.
- Шаг по плейлисту папки пропускает отмеченные. Неудача постера в хранилище не пишется (причина неизвестна).
- `ListPlaylist` (плагин) — без изменений.

## Этапы

- 4а: кит + Loupe → сборка Loupe `P2-4` (предупредить другую сессию перед установкой).
- 4б: FrameScrub → сборка FrameScrub.

## Тесты

- Кит: `UnreadableFilesTests` (отметка/снятие, другая дата или размер — неизвестен, без даты — по URL,
  стандартизация, наблюдатель: только изменившиеся, токен снят — тишина); `FolderPlaylistTests` для
  `index(from:step:skipping:)` (оба направления, всё впереди битое — nil, `from` сам годен).
- Loupe: генератор — ошибка декодера даёт `.unavailable`, ошибка чтения — нет (`ThumbnailStoreTests`); тесты
  `Playlist`/просмотрщика без AppKit, где они есть.
- FrameScrub: какой `OpenFailure.Kind` считается битым (`OpenFailure.marksUnreadable`); пропуск при шаге — через
  `FolderPlaylist`.
- Руками: папка с битым JPEG / видео: в сетке карточка бледная после первой встречи (Loupe — сразу по превью),
  листание его пропускает в обе стороны, открытие по имени показывает ошибку; файл заменён целым — снова
  открывается.
