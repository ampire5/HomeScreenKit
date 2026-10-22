/// Which way a two-finger swipe over the filmstrip moves the selection. `natural`: fingers left go to the next
/// items, as a three-finger swipe does (the strip is content that follows the fingers under the selection, so the
/// selection's border moves against them); `reversed`: the selection moves with the fingers.
public enum FilmstripScrollDirection: String, Sendable {
    case natural, reversed
}
