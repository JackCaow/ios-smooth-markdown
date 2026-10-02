import XCTest
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import SmoothMarkdown

final class MermaidNativeTreeParserTests: XCTestCase {
    func testScreenshotPieInlineTitleAndShowDataKeepSlices() throws {
        let diagram = try XCTUnwrap(MermaidParser.parse("""
        pie title 浏览器份额
          "Chrome" : 65
          "Safari" : 20
          "Edge" : 15
        """))
        XCTAssertEqual(diagram.kind, .pie)
        XCTAssertEqual(diagram.title, "浏览器份额")
        XCTAssertEqual(diagram.pieSlices, [.init(label: "Chrome", value: 65), .init(label: "Safari", value: 20), .init(label: "Edge", value: 15)])
        XCTAssertFalse(diagram.showData)
        let show = try XCTUnwrap(MermaidParser.parse("pie showData title 份额\n\"A\": 2\n\"B\": 1"))
        XCTAssertTrue(show.showData)
        XCTAssertEqual(show.title, "份额")
        XCTAssertEqual(MermaidParser.parse("pie\ntitle Existing title\n\"A\": 1")?.title, "Existing title")
        XCTAssertNil(MermaidParser.parse("pie title Empty"))
    }

    func testUnicodeSequenceIDsWhitespaceAliasesMessagesAndSelfLoops() throws {
        let diagram = try XCTUnwrap(MermaidParser.parse("""
        sequenceDiagram
          actor 用户 as 客户端 😀
          participant 服务器 as Remote Server
          用户  ->>  服务器 : 请求 😀
          服务器 -->> 用户: 返回结果
          用户 -x 用户: 取消
        """))
        XCTAssertEqual(diagram.nodes.map(\.id), ["用户", "服务器"])
        XCTAssertEqual(diagram.node("用户")?.label, "客户端 😀")
        XCTAssertEqual(diagram.node("用户")?.participantType, .actor)
        XCTAssertEqual(diagram.node("服务器")?.label, "Remote Server")
        XCTAssertEqual(diagram.edges.map(\.label), ["请求 😀", "返回结果", "取消"])
        XCTAssertEqual(diagram.edges.map(\.line), [.solid, .dotted, .solid])
        XCTAssertEqual(diagram.edges.map(\.arrow), [.arrow, .arrow, .cross])
        XCTAssertEqual(diagram.edges.last?.from, diagram.edges.last?.to)
        let combining = "e\u{301}"
        let implicit = try XCTUnwrap(MermaidParser.parse("sequenceDiagram\n\(combining) ->> B: hi\nactor B as 后声明\nB -->> \(combining): done"))
        XCTAssertEqual(implicit.nodes.first?.id, combining)
        XCTAssertEqual(implicit.node("B")?.participantType, .actor)
        XCTAssertEqual(implicit.node("B")?.label, "后声明")
        XCTAssertNotNil(MermaidParser.parse("sequenceDiagram\nparticipant A as Alone"))
        for source in ["sequenceDiagram", "sequenceDiagram\nnot a message", "sequenceDiagram\nA ->> : missing", "sequenceDiagram\nA->>B: valid\nbogus syntax"] {
            XCTAssertNil(MermaidParser.parse(source), source)
        }
    }

    func testScreenshotGitBranchesMergeAndCommitMetadataFormAcyclicHistory() throws {
        let source = """
        gitGraph
          commit id: "初始化"
          branch feature
          checkout feature
          commit id: "新功能"
          checkout main
          merge feature
        """
        let diagram = try XCTUnwrap(MermaidParser.parse(source))
        XCTAssertEqual(diagram.kind, .gitGraph)
        XCTAssertEqual(diagram.direction, .leftToRight)
        XCTAssertEqual(diagram.gitCommits.map(\.id), ["初始化", "新功能", "commit-1"])
        XCTAssertEqual(diagram.gitCommits.map(\.branch), ["main", "feature", "main"])
        XCTAssertEqual(diagram.gitCommits.map(\.parents), [[], ["初始化"], ["初始化", "新功能"]])
        XCTAssertEqual(diagram, MermaidParser.parse(source))
        XCTAssertEqual(diagram, MermaidParser.parse(source.replacingOccurrences(of: "\n", with: "\r\n")))
        let positions = Dictionary(uniqueKeysWithValues: diagram.nodes.enumerated().map { ($0.element.id, $0.offset) })
        for edge in diagram.edges {
            XCTAssertLessThan(try XCTUnwrap(positions[edge.from]), try XCTUnwrap(positions[edge.to]), "Parents must precede commits; no cycle may be synthesized")
        }
        let decorated = try XCTUnwrap(MermaidParser.parse("""
        gitGraph TB:
          init
          commit id:"base" tag:"v1 😀" type:NORMAL
          branch "feature branch"
          commit id:"changed" type:REVERSE
          switch main
          merge "feature branch" id:"merged" type:HIGHLIGHT tag:"v2"
        """))
        XCTAssertEqual(decorated.direction, .topToBottom)
        XCTAssertEqual(decorated.gitCommits.map(\.type), [.normal, .reverse, .highlight])
        XCTAssertEqual(decorated.gitCommits.map(\.tag), ["v1 😀", nil, "v2"])
        XCTAssertEqual(decorated.gitCommits.last?.parents, ["base", "changed"])
        XCTAssertEqual(decorated.nodes.last?.shape, .rectangle)
    }

    func testIllegalGitCommandsAndReferencesAreRejectedWithoutPartialDiagram() {
        for body in ["", "init", "checkout missing", "branch main", "merge main", "commit id:\"same\"\ncommit id:\"same\"", "commit\nmerge missing", "branch feature\ncheckout main\nmerge feature", "commit\nbranch feature\ncheckout main\nmerge feature", "commit\ninit", "commit id:\"unclosed", "commit type:UNKNOWN", "commit\ncherry-pick id:\"unknown\"", "commit\nbranch feature\nbranch feature"] {
            XCTAssertNil(MermaidParser.parse("gitGraph\n" + body), body)
        }
        XCTAssertNil(MermaidParser.parse("gitGraph\n" + Array(repeating: "commit", count: 501).joined(separator: "\n")))
    }

    func testScreenshotMindmapIndentationPreservesSingleTreeAndLabels() throws {
        let diagram = try XCTUnwrap(MermaidParser.parse("""
        mindmap
          root((项目))
            前端
              页面
              组件
            后端
              API
              数据库
        """))
        XCTAssertEqual(diagram.kind, .mindmap)
        XCTAssertEqual(MermaidParser.parse("mindmap\r\n  root((项目))\r\n    前端\r\n")?.nodes.map(\.label), ["项目", "前端"])
        XCTAssertEqual(diagram.nodes.map(\.label), ["项目", "前端", "页面", "组件", "后端", "API", "数据库"])
        XCTAssertEqual(diagram.nodes.first?.id, "root")
        XCTAssertEqual(diagram.nodes.first?.shape, .circle)
        XCTAssertEqual(diagram.edges.count, diagram.nodes.count - 1)
        let label = Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, $0.label) })
        XCTAssertEqual(diagram.edges.map { "\(label[$0.from]!)→\(label[$0.to]!)" }, ["项目→前端", "前端→页面", "前端→组件", "项目→后端", "后端→API", "后端→数据库"])
        let tabs = try XCTUnwrap(MermaidParser.parse("mindmap\n\troot((Root 😀))\n\t\tchild[Child]\n\t\t\tleaf(Leaf)\n\t\tother{{Other}}"))
        XCTAssertEqual(tabs.nodes.map(\.shape), [.circle, .rectangle, .rounded, .hexagon])
        XCTAssertEqual(tabs.edges.map(\.from), ["root", "child", "root"])
        let named = try XCTUnwrap(MermaidParser.parse("mindmap\nroot((Root))\n  anonymous\n  mindmap-1[Named]"))
        XCTAssertEqual(named.nodes.map(\.label), ["Root", "anonymous", "Named"])
        XCTAssertNotNil(named.node("mindmap-1"), "Generated IDs must not shadow a later authored identifier")
    }

    func testSpecialtyLayoutsContainLongLabelsTallSiblingSubtreesAndFilterDanglingEdges() throws {
        let longRoot = String(repeating: "项目Root😀", count: 22)
        let longChild = String(repeating: "高节点Child", count: 12)
        let tree = try XCTUnwrap(MermaidParser.parse("mindmap\nroot((" + longRoot + "))\n  first((" + longChild + "))\n    leafA[First leaf]\n  second((" + longChild + "))\n    leafB[Second leaf]"))
        let treeLayout = MermaidLayout.compute(tree)
        let treeCanvas = CGRect(origin: .zero, size: treeLayout.size)
        XCTAssertEqual(treeLayout.nodes.count, tree.nodes.count)
        for frame in treeLayout.nodes.values { XCTAssertTrue(treeCanvas.contains(frame), "Tall node must remain inside its canvas") }
        let root = try XCTUnwrap(treeLayout.nodes["root"])
        XCTAssertGreaterThanOrEqual(root.minY, 32)
        let first = try XCTUnwrap(treeLayout.nodes["first"])
        let second = try XCTUnwrap(treeLayout.nodes["second"])
        XCTAssertFalse(first.intersects(second), "Sibling subtree allocation must account for the parent's own height")
        XCTAssertGreaterThanOrEqual(second.minY - first.maxY, 24)
        XCTAssertFalse(try XCTUnwrap(treeLayout.nodes["leafA"]).intersects(try XCTUnwrap(treeLayout.nodes["leafB"])))

        let manual = MermaidDiagram(kind: .mindmap, direction: .leftToRight,
            nodes: [.init(id: "root", label: "Root"), .init(id: "child", label: "Child")],
            edges: [.init(from: "root", to: "child"), .init(from: "root", to: "missing"), .init(from: "missing", to: "root")])
        let manualLayout = MermaidLayout.compute(manual)
        XCTAssertEqual(Set(manualLayout.nodes.keys), ["root", "child"])
        XCTAssertEqual(manualLayout.edges.map(\.edge), [manual.edges[0]], "Public models may contain dangling references; valid content must still render")
        XCTAssertTrue(manualLayout.nodes.values.allSatisfy { CGRect(origin: .zero, size: manualLayout.size).contains($0) })

        func annotation(_ text: String, points: CGFloat, weight: String, at leading: CGPoint) -> CGRect {
            #if canImport(UIKit)
            let font = UIFont.systemFont(ofSize: points, weight: weight == "semibold" ? .semibold : weight == "medium" ? .medium : .regular)
            #else
            let font = NSFont.systemFont(ofSize: points, weight: weight == "semibold" ? .semibold : weight == "medium" ? .medium : .regular)
            #endif
            let size = (text as NSString).size(withAttributes: [.font: font])
            return CGRect(x: leading.x, y: leading.y - size.height / 2, width: size.width, height: size.height)
        }
        let branch = String(repeating: "feature-long-分支", count: 7)
        let baseID = String(repeating: "初始化base😀", count: 9)
        let childID = String(repeating: "新功能change", count: 9)
        let tag = String(repeating: "版本v1😀", count: 12)
        for direction in ["TB", "BT"] {
            let history = try XCTUnwrap(MermaidParser.parse("gitGraph " + direction + "\ncommit id:\"" + baseID + "\" tag:\"" + tag + "\"\nbranch \"" + branch + "\"\ncommit id:\"" + childID + "\" tag:\"" + tag + "\"\ncheckout main\nmerge \"" + branch + "\""))
            let layout = MermaidLayout.compute(history)
            let canvas = CGRect(origin: .zero, size: layout.size)
            XCTAssertEqual(layout.nodes.count, history.nodes.count)
            XCTAssertEqual(layout.edges.count, history.edges.count)
            XCTAssertTrue(layout.nodes.values.allSatisfy(canvas.contains))
            var branchLabels: [CGRect] = []
            var seen: Set<String> = []
            for commit in history.gitCommits {
                let frame = try XCTUnwrap(layout.nodes[commit.id])
                let idFrame = annotation(commit.id, points: 12, weight: "regular", at: CGPoint(x: frame.maxX + 4, y: frame.midY))
                XCTAssertTrue(canvas.contains(idFrame), direction + " commit label outside canvas")
                if let tag = commit.tag {
                    let tagFrame = annotation(tag, points: 11, weight: "medium", at: CGPoint(x: frame.maxX + 4, y: frame.midY + 18))
                    XCTAssertTrue(canvas.contains(tagFrame), direction + " tag outside canvas")
                    XCTAssertFalse(idFrame.intersects(tagFrame), "Commit ID and tag must remain separate")
                }
                if seen.insert(commit.branch).inserted {
                    let label = annotation(commit.branch, points: 13, weight: "semibold", at: CGPoint(x: frame.midX + 12, y: 16))
                    XCTAssertTrue(canvas.contains(label), direction + " branch label outside canvas")
                    branchLabels.append(label)
                }
            }
            XCTAssertFalse(branchLabels[0].intersects(branchLabels[1]), "Long vertical branch labels must occupy separate lanes")
            let start = try XCTUnwrap(layout.nodes[baseID])
            let next = try XCTUnwrap(layout.nodes[childID])
            if direction == "TB" { XCTAssertLessThan(start.midY, next.midY) }
            else { XCTAssertGreaterThan(start.midY, next.midY) }
        }
    }

    func testMindmapCyclesMultipleRootsAndUnsupportedSyntaxAreRejected() {
        for body in ["", "root((Root))\nother[Second root]", "root((Root))\n  root[Cycle]", "root((Root))\n  same[Child]\n  same[Second parent]", "root((unclosed)", "root((Root))\n  ::icon(fa fa-book)", "root((Root))\n  A --> B"] {
            XCTAssertNil(MermaidParser.parse("mindmap\n" + body), body)
        }
        XCTAssertNil(MermaidParser.parse("mindmap\nroot((Root))\n  " + String(repeating: "x", count: 50_000)))
    }
}
