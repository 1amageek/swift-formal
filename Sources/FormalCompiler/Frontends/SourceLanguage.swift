public enum SourceLanguage: String, Codable, Sendable, CaseIterable {
    case swift, rust, c, cpp, go, typescript, javascript, python, java, bun
    public var isJavaScriptFamily: Bool { [.typescript, .javascript, .bun].contains(self) }
    public var profile: String { "\(rawValue)-scalar-v\(isJavaScriptFamily ? 2 : 1)" }
    public var assumptions: [String] {
        switch self {
        case .rust: ["Rust 2021; overflow checks enabled; primitive i64/u64/bool only"]
        case .c: ["C11; int64_t/uint64_t/bool; no macros except standard includes; signed overflow is undefined behavior"]
        case .cpp: ["C++20; int64_t/uint64_t/bool; no overloads or user-defined declarations; signed overflow is undefined behavior"]
        case .go: ["Go; int64/uint64/bool; standalone pure functions"]
        case .swift: ["Swift; Int64/UInt64/Bool; unlabeled arguments; checked arithmetic"]
        case .typescript: ["TypeScript; monomorphic number/bigint/boolean; binary64 Number; no implicit coercion"]
        case .javascript: ["ECMAScript; monomorphic scalar inputs inferred from use; unconstrained numeric inputs use the selected default (Number unless overridden); no implicit coercion"]
        case .java: ["Java; one class of static int/long/boolean methods; 32/64-bit wrapping arithmetic; no implicit width conversions; long literals require L/l"]
        case .bun: ["Bun JavaScript/TypeScript; inferred number/bigint/boolean; unconstrained numeric inputs use the selected default (Number unless overridden); no implicit coercion; only listed pure numeric builtins"]
        case .python: ["Python 3; annotations specify exact built-in int/bool inputs, excluding subclasses; no dynamic rebinding"]
        }
    }
}
