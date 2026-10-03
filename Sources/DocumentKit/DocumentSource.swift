/// A document that the app can show and read text from. Later milestones add Markdown and code sources.
public protocol DocumentSource {
    var kind: DocumentKind { get }
    var metadata: DocumentMetadata { get }
    var outline: [OutlineEntry] { get }
    func paragraphs(onPage pageIndex: Int) -> [Paragraph]
}
