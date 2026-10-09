import Foundation
import Darwin
import RecipeMacNative

// Compile against the same RecipeMacNative module as the app, then run with:
// MallocStackLogging=1 leaks --atExit -- <probe> <model> <request.json> [cycles]
// Uses only supplied test files; no application database, Keychain or cloud.
func residentBytes() -> UInt64 {
  var info = mach_task_basic_info()
  var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)
  let status = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
    }
  }
  return status == KERN_SUCCESS ? info.resident_size : 0
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fatalError("Pass model and request JSON paths") }
let request = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: arguments[2]))) as! [String: Any]
let schema = String(decoding: try JSONSerialization.data(withJSONObject: request["schema"]!), as: UTF8.self)
let cycles = arguments.count > 3 ? (Int(arguments[3]) ?? 3) : 3
print("Baseline resident bytes: \(residentBytes())")
for cycle in 1...max(1, cycles) {
  try autoreleasepool {
    let job = RecipeModelJob()
    let outputs = try job.extract(
      modelPath: arguments[1], instruction: request["instruction"] as! String,
      chatTemplate: request["chatTemplate"] as! String, schema: schema,
      fragments: request["fragments"] as! [String])
    guard !outputs.isEmpty else { fatalError("No inference output") }
    for output in outputs {
      _ = try JSONSerialization.jsonObject(with: Data(output.utf8))
    }
  }
  print("Cycle \(cycle) completed; resident bytes after engine release: \(residentBytes())")
}
