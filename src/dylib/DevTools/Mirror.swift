// Dev tools: what a Swift object holds, for finding the fields a patch can read. Objective-C sees Dia's Swift classes
// but not their stored properties; Mirror does.
import Foundation

private func DPMirrorLines(_ value: Any, _ label: String, _ depth: Int, _ maxDepth: Int, _ seen: inout Set<ObjectIdentifier>, _ out: inout [String]) {
    let mirror = Mirror(reflecting: value)
    let indent = String(repeating: "  ", count: depth)
    var summary = String(describing: type(of: value))
    if mirror.children.isEmpty || mirror.displayStyle == .enum || mirror.displayStyle == .optional {
        summary += " = " + String(String(describing: value).prefix(300))
    }
    out.append("\(indent)\(label): \(summary)")
    if mirror.displayStyle == .class, let object = value as AnyObject? {
        if seen.contains(ObjectIdentifier(object)) { out.append("\(indent)  (seen)"); return }
        seen.insert(ObjectIdentifier(object))
    }
    guard depth < maxDepth else { return }
    var current: Mirror? = mirror
    while let m = current {
        for (index, child) in m.children.prefix(60).enumerated() {
            DPMirrorLines(child.value, child.label ?? "[\(index)]", depth + 1, maxDepth, &seen, &out)
        }
        current = m.superclassMirror
        if let name = current.map({ String(describing: $0.subjectType) }), name.hasPrefix("NS") { break }
    }
}

@_cdecl("DPMirrorDescription")
public func DPMirrorDescription(_ object: AnyObject, _ maxDepth: Int) -> NSString {
    var seen = Set<ObjectIdentifier>()
    var out: [String] = []
    DPMirrorLines(object, "root", 0, maxDepth, &seen, &out)
    return out.joined(separator: "\n") as NSString
}
