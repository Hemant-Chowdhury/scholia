/// Finds the chapter and section titles that contain a page, for example ["Chapter 4", "4.2 Tool use"].
public enum StructuralPath {
    public static func path(forPage page: Int, in outline: [OutlineEntry]) -> [String] {
        var stack: [OutlineEntry] = []
        for entry in outline where entry.pageIndex <= page {
            while let last = stack.last, last.level >= entry.level { stack.removeLast() }
            stack.append(entry)
        }
        return stack.map(\.title)
    }
}
