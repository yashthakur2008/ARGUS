public enum StoreError: Error, Equatable, Sendable {
  case sqlite(code: Int32, message: String)
  case conflict
  case corruption(String)
  case unsupportedSchema(Int64)
  case revisionOverflow
}
