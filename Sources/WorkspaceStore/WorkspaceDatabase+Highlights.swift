import GRDB

extension WorkspaceDatabase {
    public func addHighlight(_ highlight: HighlightRecord, anchor: AnchorRecord) throws {
        try queue.write { db in
            try anchor.insert(db)
            try highlight.insert(db)
        }
    }

    public func highlights(documentID: String) throws -> [StoredHighlight] {
        try queue.read { db in
            let anchors = try AnchorRecord
                .filter(Column("document_id") == documentID)
                .order(Column("first_page"), Column("created_at"))
                .fetchAll(db)
            let highlights = try HighlightRecord.filter(anchors.map(\.id).contains(Column("anchor_id"))).fetchAll(db)
            let byAnchor = Dictionary(grouping: highlights, by: \.anchorID)
            return anchors.flatMap { anchor in
                (byAnchor[anchor.id] ?? []).map { StoredHighlight(highlight: $0, anchor: anchor) }
            }
        }
    }

    /// Removes the highlight, and its anchor when no other highlight uses the anchor.
    public func removeHighlight(id: String) throws {
        try queue.write { db in
            guard let highlight = try HighlightRecord.fetchOne(db, key: id) else { return }
            try highlight.delete(db)
            let anchorInUse = try HighlightRecord.filter(Column("anchor_id") == highlight.anchorID).fetchCount(db) > 0
            if !anchorInUse {
                try AnchorRecord.deleteOne(db, key: highlight.anchorID)
            }
        }
    }
}
