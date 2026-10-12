import SwiftUI
import UniformTypeIdentifiers

/// 匯出用的單一檔案；帳號備份（JSON，含憑證）與用量（CSV）共用。
struct AccountExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.fileAttributes[FileAttributeKey.posixPermissions.rawValue] = 0o600
        return wrapper
    }
}
