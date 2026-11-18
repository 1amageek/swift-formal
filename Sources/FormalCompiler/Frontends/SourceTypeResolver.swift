struct SourceTypeResolver {
    let language: SourceLanguage
    let defaultNumeric: SourceNumericDefault
    private var parents: [Int] = []
    private var ranks: [Int] = []
    private var kinds: [Int: ScalarType] = [:]
    private var signatures: [String: (parameters: [Int], result: Int)] = [:]
    private var position = SourceToken(text: "", line: 1, column: 1)

    init(language: SourceLanguage, defaultNumeric: SourceNumericDefault) { self.language = language; self.defaultNumeric = defaultNumeric }
    private func error(_ message: String) -> SourceDiagnostic { .init(language: language, line: position.line, column: position.column, message: message) }
    private mutating func fresh(_ kind: ScalarType? = nil) throws -> Int {
        guard parents.count < 200_000 else { throw error("Type inference exceeds 200000 scalar nodes") }
        let id = parents.count; parents.append(id); ranks.append(0)
        if let kind { kinds[id] = kind }
        return id
    }
    private mutating func root(_ id: Int) -> Int {
        var top = id
        while parents[top] != top { top = parents[top] }
        var next = id
        while parents[next] != next { let old = parents[next]; parents[next] = top; next = old }
        return top
    }
    private mutating func unify(_ left: Int, _ right: Int) throws {
        var a = root(left); var b = root(right)
        if a == b { return }
        if let x = kinds[a], let y = kinds[b], x != y { throw error("Conflicting scalar types; implicit coercion is unsupported") }
        if ranks[a] < ranks[b] { swap(&a, &b) }
        parents[b] = a
        if ranks[a] == ranks[b] { ranks[a] += 1 }
        if kinds[a] == nil { kinds[a] = kinds[b] }
        kinds.removeValue(forKey: b)
    }
    private mutating func constrain(_ id: Int, _ kind: ScalarType) throws {
        let target = try fresh(kind); try unify(id, target)
    }
    mutating func resolve(_ parsed: [ParsedSourceFunction]) throws -> [SourceFunction] {
        if !language.isJavaScriptFamily {
            return try parsed.map { function in
                guard let result = function.result else { throw error("Explicit result type required") }
                let parameters = try function.parameters.map { name, kind in
                    guard let kind else { throw error("Explicit parameter type required") }; return (name, kind)
                }
                return .init(position: function.position, range: function.range, name: function.name, parameters: parameters, result: result, body: function.body)
            }
        }
        for function in parsed {
            position = function.position
            guard signatures[function.name] == nil, !SourceNumberBuiltin.reserved(function.name) else { throw error("Duplicate function or shadowed builtin") }
            let parameters = try function.parameters.map { try fresh($0.1) }
            let result = try fresh(function.result)
            signatures[function.name] = (parameters, result)
        }
        for function in parsed {
            position = function.position
            guard let signature = signatures[function.name] else { throw error("Unresolved signature") }
            var environment: [String: Int] = [:]
            for ((name, _), id) in zip(function.parameters, signature.parameters) {
                guard environment[name] == nil, !SourceNumberBuiltin.reserved(name) else { throw error("Duplicate parameter or shadowed builtin") }
                environment[name] = id
            }
            try statements(function.body, environment: environment, result: signature.result)
        }
        var output: [SourceFunction] = []
        for function in parsed {
            guard let signature = signatures[function.name] else { throw error("Unresolved signature") }
            let parameters = zip(function.parameters, signature.parameters).map { parameter, id in (parameter.0, kinds[root(id)] ?? defaultNumeric.scalarType) }
            let result = kinds[root(signature.result)] ?? defaultNumeric.scalarType
            output.append(.init(position: function.position, range: function.range, name: function.name, parameters: parameters, result: result, body: function.body))
        }
        return output
    }
    private mutating func statements(_ body: [SourceStatement], environment initial: [String: Int], result: Int) throws {
        var environment = initial
        for statement in body {
            switch statement.kind {
            case .binding(let name, let kind, let value):
                guard environment[name] == nil, !SourceNumberBuiltin.reserved(name) else { throw error("Rebinding or shadowed builtin") }
                let id = try expression(value, environment: environment)
                if let kind { try constrain(id, kind) }
                environment[name] = id
            case .returned(let value):
                let id = try expression(value, environment: environment); try unify(id, result)
            case .conditional(let condition, let left, let right):
                _ = try expression(condition, environment: environment)
                try statements(left, environment: environment, result: result)
                try statements(right, environment: environment, result: result)
            }
        }
    }
    private mutating func expression(_ value: SourceExpression, environment: [String: Int]) throws -> Int {
        switch value.kind {
        case .literal(let text):
            return try fresh(["true", "false"].contains(text) ? .boolean : text.hasSuffix("n") ? .integer : .number)
        case .variable(let name):
            if let id = environment[name] { return id }
            if name == "NaN" || name == "Infinity" { return try fresh(.number) }
            throw error("Unknown variable '\(name)'")
        case .unary(let operation, let value):
            let operand = try expression(value, environment: environment)
            if operation == "+" { try constrain(operand, .number) }
            return operation == "!" ? try fresh(.boolean) : operand
        case .binary(let operation, let left, let right):
            let a = try expression(left, environment: environment)
            let b = try expression(right, environment: environment)
            try unify(a, b)
            return ["==", "!=", "===", "!==", "<", "<=", ">", ">="].contains(operation) ? try fresh(.boolean) : a
        case .call(let name, let values):
            if let operation = SourceNumberBuiltin.operation(name) {
                guard values.count == SourceNumberBuiltin.arity(name) else { throw error("Builtin argument count mismatch") }
                for value in values { let id = try expression(value, environment: environment); try constrain(id, .number) }
                return try fresh(operation.returnsFlag ? .boolean : .number)
            }
            guard let target = signatures[name], target.parameters.count == values.count else { throw error("Unresolved call or argument count") }
            for (value, parameter) in zip(values, target.parameters) { let id = try expression(value, environment: environment); try unify(id, parameter) }
            return target.result
        }
    }
}
