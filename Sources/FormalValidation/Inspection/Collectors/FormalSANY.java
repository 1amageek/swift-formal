import java.util.*;
import tla2sany.drivers.SANY;
import tla2sany.modanalyzer.SpecObj;
import tla2sany.semantic.*;

// Compiled during SDK development against the pinned tla2tools artifact. Runtime
// consumers need only the pinned JRE, never javac or a workspace Java classpath.
public final class FormalSANY {
    private static String q(String text) {
        if (text == null) return "null";
        StringBuilder out = new StringBuilder("\"");
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == '"' || c == '\\') out.append('\\').append(c);
            else if (c < 32) out.append(String.format("\\u%04x", (int)c));
            else out.append(c);
        }
        return out.append('"').toString();
    }
    private static String key(SemanticNode node) { return "symbol:" + node.getUid(); }
    private static void edge(String source, String target, String kind) {
        System.out.println("{\"record\":\"edge\",\"source\":"+q(source)+",\"target\":"+q(target)+",\"kind\":"+q(kind)+"}");
    }
    private static void node(SymbolNode node, String kind) {
        nodeRecord(node,kind,node.getName().toString());
    }
    private static void nodeRecord(SemanticNode node, String kind, String label) {
        var loc = node.getLocation();
        System.out.println("{\"record\":\"node\",\"id\":"+q(key(node))+",\"kind\":"+q(kind)+",\"label\":"+q(label)+",\"module\":"+q(loc.source())+",\"beginLine\":"+loc.beginLine()+",\"beginColumn\":"+loc.beginColumn()+",\"endLine\":"+loc.endLine()+",\"endColumn\":"+loc.endColumn()+"}");
    }
    public static void main(String[] arguments) throws Exception {
        if (arguments.length != 2) throw new IllegalArgumentException("Expected module and visit limit");
        int limit = Integer.parseInt(arguments[1]);
        if (limit < 1) throw new IllegalArgumentException("Invalid visit limit");
        java.io.PrintStream output = System.out;
        System.setOut(System.err);
        util.ToolIO.out = System.err;
        util.ToolIO.err = System.err;
        SpecObj spec = new SpecObj(arguments[0]);
        int result = SANY.frontEndMain(spec, arguments[0], System.err);
        System.setOut(output);
        if (result != 0 || spec.getErrorLevel() != 0 || spec.getRootModule() == null || spec.getSemanticErrors().isFailure()) throw new IllegalStateException("SANY semantic analysis failed");
        ModuleNode root = spec.getRootModule();
        Set<ModuleNode> modules = new HashSet<>();
        ArrayDeque<ModuleNode> moduleQueue = new ArrayDeque<>();
        moduleQueue.add(root);
        Collections.addAll(moduleQueue,spec.getExternalModuleTable().getModuleNodes());
        int moduleVisits = 0;
        while (!moduleQueue.isEmpty()) {
            if (++moduleVisits > limit) throw new IllegalStateException("Module visit budget exhausted");
            ModuleNode module = moduleQueue.removeFirst();
            if (!modules.add(module)) continue;
            moduleQueue.addAll(module.getExtendedModuleSet(false));
            Collections.addAll(moduleQueue,module.getInnerModules());
            for (InstanceNode instance : module.getInstances()) moduleQueue.add(instance.getModule());
        }
        Map<String, SymbolNode> symbols = new TreeMap<>();
        List<ModuleNode> ordered = new ArrayList<>(modules); ordered.sort(Comparator.comparing(m -> m.getName().toString()));
        for (ModuleNode module : ordered) {
            symbols.put(key(module),module); node(module,"module");
            for (OpDeclNode symbol : module.getConstantDecls()) { if (!symbols.containsKey(key(symbol))) { symbols.put(key(symbol),symbol); node(symbol,"constant"); } if (symbol.getOriginallyDefinedInModuleNode() == module) edge(key(module),key(symbol),"defines"); }
            for (OpDeclNode symbol : module.getVariableDecls()) { if (!symbols.containsKey(key(symbol))) { symbols.put(key(symbol),symbol); node(symbol,"variable"); } if (symbol.getOriginallyDefinedInModuleNode() == module) edge(key(module),key(symbol),"defines"); }
            for (OpDefNode symbol : module.getOpDefs()) {
                if (!symbols.containsKey(key(symbol))) { symbols.put(key(symbol),symbol); node(symbol,"operator"); }
                if (symbol.getOriginallyDefinedInModuleNode() == module) edge(key(module),key(symbol),"defines");
            }
            for (ModuleNode imported : module.getExtendedModuleSet(false)) edge(key(module),key(imported),"imports");
            for (ModuleNode inner : module.getInnerModules()) edge(key(module),key(inner),"contains");
            for (InstanceNode instance : module.getInstances()) {
                String label = instance.getName() == null ? "INSTANCE" : instance.getName().toString();
                nodeRecord(instance,"moduleInstance",label);
                edge(key(module),key(instance),"defines");
                edge(key(instance),key(instance.getModule()),"instantiates");
                if (++moduleVisits > limit) throw new IllegalStateException("Instance budget exhausted");
            }
            if (symbols.size() > limit) throw new IllegalStateException("Symbol budget exhausted");
        }
        int visits = 0;
        for (SymbolNode symbol : symbols.values()) if (symbol instanceof OpDefNode definition) {
            ArrayDeque<SemanticNode> pending = new ArrayDeque<>();
            if (definition.getBody() != null) pending.add(definition.getBody());
            Set<Integer> seen = new HashSet<>(); Set<String> refs = new TreeSet<>();
            while (!pending.isEmpty()) {
                SemanticNode current = pending.removeFirst();
                if (!seen.add(current.getUid())) continue;
                if (++visits > limit) throw new IllegalStateException("Semantic visit budget exhausted");
                if (current instanceof OpApplNode application) {
                    SymbolNode operator = application.getOperator();
                    if (operator != null && symbols.containsKey(key(operator))) refs.add(key(operator));
                }
                SemanticNode[] children = current.getChildren();
                if (children != null) for (SemanticNode child : children) if (child != null) pending.addLast(child);
            }
            for (String reference : refs) edge(key(symbol),reference,"references");
        }
        System.out.println("{\"record\":\"complete\",\"module\":"+q(root.getName().toString())+",\"root\":"+q(key(root))+"}");
    }
}
