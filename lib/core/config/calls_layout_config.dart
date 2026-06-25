/// Feature flag for the row-based Calls Screen layout (templates A/B/G/D).
/// Default `true` after migration (phase 8).
const bool useNewCallsScreenLayout = true;

/// Viewport width below which columns stack vertically inside a template row.
const double callsLayoutNarrowViewportBreakpoint = 980;

/// Ελάχιστο πλάτος ανά στήλη σε οριζόντιο πλέγμα πριν η διάταξη γίνει στοίβα (stack).
const double callsLayoutMinColumnWidth = 380;
