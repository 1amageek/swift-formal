public enum SourceLanguage: String, Codable, Sendable, CaseIterable {
    case swift, rust, c, cpp, go, typescript, javascript, python
    public var profile: String { "\(rawValue)-scalar-v1" }
    public var assumptions: [String] {
        switch self {
        case .rust: ["Rust 2021; overflow checks enabled; primitive i64/u64/bool only"]
        case .c: ["C11; int64_t/uint64_t/bool; no macros except standard includes; signed overflow is undefined behavior"]
        case .cpp: ["C++20; int64_t/uint64_t/bool; no overloads or user-defined declarations; signed overflow is undefined behavior"]
        case .go: ["Go; int64/uint64/bool; standalone pure functions"]
        case .swift: ["Swift; Int64/UInt64/Bool; unlabeled arguments; checked arithmetic"]
        case .typescript: ["TypeScript; primitive bigint/boolean inputs; no Number or coercion"]
        case .javascript: ["ECMAScript; all parameters/results are primitive BigInts; no Number or coercion"]
        case .python: ["Python 3; annotations specify exact built-in int/bool inputs, excluding subclasses; no dynamic rebinding"]
        }
    }
}
