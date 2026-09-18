public enum StoreError: Error, Equatable, Sendable {
  case sqlite(code: Int32, message: String)
  case conflict
  case corruption(String)
  case unsupportedSchema(Int64)
  case noticeNotFound(String)
  case noticeDismissed(String)
  case noticeNoLongerApplicable(String)
  case invalidSnooze
  case activeSnoozeConflict
  case revisionOverflow
}
