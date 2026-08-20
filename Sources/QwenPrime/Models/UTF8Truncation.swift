/// UTF-8 byte-bounded text operations that never split a Swift character.
enum UTF8Truncation {
  static func prefix(_ value: String, maximumBytes: Int) -> String {
    guard value.utf8.count > maximumBytes else { return value }
    var byteCount = 0
    var endIndex = value.startIndex

    for index in value.indices {
      let nextIndex = value.index(after: index)
      let characterByteCount = value[index..<nextIndex].utf8.count
      guard byteCount + characterByteCount <= maximumBytes else { break }
      byteCount += characterByteCount
      endIndex = nextIndex
    }

    return String(value[..<endIndex])
  }
}
