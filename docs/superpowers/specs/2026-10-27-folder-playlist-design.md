# Плейлист папки в HomeScreenKit: один порядок для сетки, просмотрщика и плеера — дизайн

Дата: 2026-10-27. Ветки `polish-2` от `origin/main` в HomeScreenKit, Loupe и FrameScrub. Ничего не отправляется на
GitHub до слова пользователя; после каждого этапа приложения собираются с китом из локального клона (`swift package
edit`) и ставятся в `~/Applications`.

## Цель

Листание в просмотрщике Loupe и в плеере FrameScrub идёт в том же порядке, что сетка Home, как бы файл ни был открыт.
Решения пользователя:

- Цель этой работы — **один порядок** (общее знание о битых файлах — следующая подзадача, на этой модели).
- Источник плейлиста определяет его порядок:

| Откуда открыт | Плейлист |
|---|---|
| Home (сетка папки) | файлы папки в `BrowserSort` папки — как их показала сетка |
| Файл напрямую (Finder, Open…, перетаскивание, Recent, командная строка) | **то же самое**: папка файла, её сохранённая сортировка |
| Плагин (FrameScrub `ListPlaylist`: сцены Stash, файлы, потоки) | список плагина как есть, без сортировки |

- Подход А: чистая модель в `HomeScreenModel`; листинг диска и хранение сортировки остаются за приложением.

## Как сейчас

- Кит: `BrowserSort.order(_:)` сортирует `[BrowserEntry]` (имена — Finder-порядок, ничья — путь; равные даты/размеры —
  по имени по возрастанию; без значения — в конце, по имени).
- Loupe: сортировка папки — `browser-sort` в настройках папки (наследуется), её читают и сетка, и просмотрщик. Но
  просмотрщик сортирует **своим** кодом (`Playlist.init` — `naturalLess`, `Playlist.sorted(_:)` по `stamps`), правила
  повторены руками. Имена страниц zip сетка берёт по внутреннему пути (`ArchivePath.split(url)?.entry`), просмотрщик —
  по `lastPathComponent`: порядок страниц в подпапках архива может разойтись.
- FrameScrub: сортировка Home — словарь в памяти (`FrameScrubHomeSource.sorts`), не переживает перезапуск. Плейлист
  из Home переводит её в `PlaylistSort` + `ascending` (`HomeFolders.playlistOrder`) только пока открыта папка из Home
  (`folderReturn`); иначе — свой `playlist-sort`. Своя сортировка (`Playlist.init`) расходится с китом: файл без даты —
  `distantPast`, без размера — 0 (в ките — в конце), ничья по имени без пути. Листинг плеера (`FolderListing.read`)
  — отдельный от листинга Home (`HomeFolders.entries`) код: ссылки, например, разбирает только Home.

## Модель: `FolderPlaylist` (HomeScreenModel)

```swift
/// The files of one folder in its BrowserSort order, as Home's grid shows them, and the position among them.
public struct FolderPlaylist: Equatable, Sendable {
    public let folder: URL
    public private(set) var sort: BrowserSort
    public private(set) var files: [BrowserEntry]
    public private(set) var index: Int
    public var current: BrowserEntry { files[index] }
    public var urls: [URL] { files.map(\.url) }

    public init(folder: URL, entries: [BrowserEntry], sort: BrowserSort, current: URL)
    public mutating func move(by step: Int) -> Bool
    public mutating func move(to url: URL) -> Bool
    public mutating func resort(_ sort: BrowserSort)
    public mutating func replace(entries: [BrowserEntry])
}
```

- **Состав** — записи с `isFile` (что сетка рисует файлами); папки, архивы, места, коллекции — нет. Какие расширения
  «свои», решает приложение, строя записи.
- **Порядок** — `sort.order(files)`: тот же вызов, что у сетки. Своего кода сравнения в приложениях не остаётся.
- **Текущий файл всегда в списке** при `init`: нет в записях — добавляется запись `kind: .file` с именем
  `lastPathComponent` и без даты/размера, место по сортировке. URL сравниваются стандартизованными.
- `move(by:)` — до концов, без заворота (как сейчас); `move(to:)` — false, если такого файла нет.
- `resort` — тот же файл остаётся текущим.
- `replace(entries:)` — новый листинг (имена → с атрибутами, изменение папки): текущий остаётся по URL; если его
  больше нет — текущим становится файл на прежнем индексе (зажатом в границы), как `Playlist.replacing` в Loupe.
  Пустой новый листинг оставляет один текущий файл.
- Нет в модели: чтения диска, хранения сортировки, пропуска битых, фильтра по имени.

Кит — минорный выпуск (0.8.0) с новым API; тег — только по слову пользователя.

## Loupe

- `Playlist` остаётся (на нём полоса, `CachePlan`, `FolderRequest`, бенчи), но порядок и позицию держит
  `FolderPlaylist`: `files` (`[URL]`, хранится, обновляется при смене порядка) и `index` берутся из модели,
  `stamps` — как сейчас. `init(files:current:stamps:keeping:sort:)` строит записи общей функцией
  `BrowserListingSource.fileEntry(_:stamp:)` — той же, которой их строит сетка (имя страницы zip — внутренний путь,
  дата и размер — из `FileStamp`).
- `Playlist.sorted(_:)` → `FolderPlaylist.resort`; `naturalLess` и сравнение в `BrowserSortSetting.swift` удаляются.
- Сортировка — как сейчас: `browser-sort` папки (`BrowserSort.forFolder`), для сетки и для просмотрщика. Файл,
  открытый напрямую, уже получает её при перечитывании папки (`ViewerSession` строка ~621); быстрый проход только по
  именам (`quickList`) теперь тоже идёт в сортировке папки (по имени — то же, что сетка в фазе «только имена»).
- Листинг просмотрщика (`relist` / `quickList`) остаётся своим: у него своя семантика (`keeping` — скрытые и странные
  файлы, открытые напрямую, nil при отказе шары, проверка «текущий исчез»). Состав по правилам уже совпадает с сеткой
  (свои расширения, без имён с точкой, без флага hidden). Это отступление от обсуждённого «просмотрщик берёт листинг
  сетки»: на цель «один порядок» оно не влияет, потому что порядок теперь даёт одна функция по одинаковым записям;
  объединение листингов — отдельный шаг, если понадобится.

## FrameScrub

- `Playlist` строится на `FolderPlaylist`: `files`, `currentIndex`, `current`, `previous`, `next`,
  `neighbourAfterRemoval` — из модели; фильтр по имени и `totalCount` / `positionText` — слой поверх (как сейчас).
- `FolderListing` хранит записи `HomeFolders.entries` (только файлы): один код листинга для сетки и плеера.
- `Playlist.init(current:sort:filter:listing:)` принимает `BrowserSort`; `ascending` уходит.
- **Сортировка папки сохраняется**: `FolderSorts` — словарь «папка → `BrowserSort.text`» в
  `~/Library/Application Support/FrameScrub/folder-sorts.json` (без наследования). `FrameScrubHomeSource.sort(for:)` /
  `setSort` читают и пишут его для папок; Recent и другие источники — как сейчас, в памяти.
- `playlist-sort` (настройки, «Folder order») — сортировка по умолчанию для папок без своей: `name` → имя по
  возрастанию, `date` → дата по убыванию, `size` → размер по убыванию (как `BrowserSortChoice`).
- Меню сортировки в панели плейлиста и F9 (`cycle-playlist-sort`) меняют **сортировку папки** текущего файла (та же,
  что у сетки), а не `playlist-sort`. Ключ меню → `BrowserSort` по `BrowserSortChoice` (выбор активного ключа —
  разворот направления). Сетка видит изменение при следующем показе папки (`HomeBrowserView` читает
  `source.sort(for:)` при показе места).
- `folderReturn.order` и `HomeFolders.playlistOrder` уходят: порядок папки один, где бы она ни была открыта.
- `ListPlaylist` не меняется.

## Этапы

1. **Кит + Loupe.** HomeScreenKit `polish-2`: `FolderPlaylist` + тесты. Loupe `polish-2`: `Playlist` на модели,
   общая `fileEntry`, удалён свой код сортировки, тесты. Сборка Loupe с локальным китом, метка `P2-1`, установка.
2. **FrameScrub.** `Playlist` на модели, листинг из `HomeFolders`, `FolderSorts`, меню/F9 на сортировку папки,
   тесты. Сборка FrameScrub с локальным китом, установка.
3. (Следующая подзадача, отдельный дизайн.) Общее знание о битых файлах на `FolderPlaylist`.

## Тесты

- Кит (`FolderPlaylistTests`): для набора записей (img2/img10, одинаковые имена в разных путях, без даты/размера,
  только имена, папки и архивы вперемешку) и всех шести сортировок `urls == sort.order(entries).filter(\.isFile)
  .map(\.url)`; текущий вне записей добавлен на своё место; `resort` / `replace` держат текущий; `replace` без
  текущего — прежний индекс, зажатый; `move` — концы.
- Loupe: тесты `Playlist` (сортировки, `replacing`, `relist`, `quickList`), `FolderRequest`, архивы — зелёные; новый
  тест «сетка и просмотрщик из одних файлов дают один порядок» (записи `fileEntry` через `BrowserSort.order` против
  `Playlist(...sort:)`), включая страницы zip в подпапке.
- FrameScrub: тесты `Playlist` (сортировки на `BrowserSort`, фильтр, концы), `FolderSorts` (запись, чтение,
  перезапуск, битый файл), умолчание из `playlist-sort`.
- Руками на каждой сборке: сортировка папки в Home (дата ↓) → открыть файл → листать: порядок как в сетке; тот же файл
  из Finder — тот же порядок; FrameScrub: сменить порядок в панели плейлиста → Home — сетка в новом порядке, после
  перезапуска тоже; плейлист плагина — в своём порядке.
