import Foundation

/// Reconstructed from the eight 2026-10-02 device review screenshots.
/// Pie, Git and mindmap preserve the visible raw syntax; other examples preserve
/// visible labels and diagram structure without claiming to be exported history.
enum MermaidReviewFixtures {
    struct Fixture: Sendable {
        let id: String
        let title: String
        let graph: String
        let label: String
        var kind: String {
            switch id {
            case "sequence": return "sequence"
            case "class": return "classDiagram"
            case "state": return "stateDiagram"
            case "er": return "erDiagram"
            case "git": return "gitGraph"
            default: return id
            }
        }
        var markdown: String { "## \(title)\n\n```mermaid\n\(graph)\n```\n\nDiagram finished. Following paragraph must remain separated." }
    }
    static let all: [Fixture] = [
        .init(id: "flowchart", title: "1. 流程图 flowchart", graph: """
        flowchart TD
          A[开始] --> B{条件判断}
          B -->|是| C[处理A]
          B -->|否| D[处理B]
          C --> E[结束]
          D --> E
        """, label: "开始"),
        .init(id: "sequence", title: "2. 时序图 sequenceDiagram", graph: """
        sequenceDiagram
          participant User as 用户
          participant Server as 服务器
          User->>Server: 发送请求
          Server-->>User: 返回结果
        """, label: "用户"),
        .init(id: "class", title: "3. 类图 classDiagram", graph: """
        classDiagram
          class 动物 {
            +String 名字
            +叫()
          }
          class 猫 {
            +抓老鼠()
          }
          动物 <|-- 猫 : 继承
        """, label: "动物"),
        .init(id: "state", title: "4. 状态图 stateDiagram-v2", graph: """
        stateDiagram-v2
          [*] --> 待机
          待机 --> 运行
          运行 --> 待机 : 停止
          运行 --> 故障 : 出错
          故障 --> 待机 : 修复
          待机 --> [*]
        """, label: "待机"),
        .init(id: "er", title: "5. ER图 erDiagram", graph: """
        erDiagram
          用户 ||--o{ 订单 : 下单
          用户 {
            int id PK
            string 姓名
          }
          订单 {
            int id PK
            float 金额
          }
        """, label: "用户"),
        .init(id: "gantt", title: "6. 甘特图 gantt", graph: """
        gantt
          title 项目计划
          dateFormat YYYY-MM-DD
          section 开发
          需求分析 : a1, 2026-10-01, 5d
          编码 : a2, after a1, 7d
          section 测试
          测试 : a3, after a2, 4d
        """, label: "需求分析"),
        .init(id: "pie", title: "7. 饼图 pie", graph: """
        pie title 浏览器份额
          "Chrome" : 65
          "Safari" : 20
          "Edge" : 15
        """, label: "Chrome"),
        .init(id: "git", title: "8. Git图 gitGraph", graph: """
        gitGraph
          commit id: "初始化"
          branch feature
          checkout feature
          commit id: "新功能"
          checkout main
          merge feature
        """, label: "main"),
        .init(id: "mindmap", title: "9. 思维导图 mindmap", graph: """
        mindmap
          root((项目))
            前端
              页面
              组件
            后端
              API
              数据库
        """, label: "项目"),
        .init(id: "timeline", title: "10. 时间轴 timeline", graph: """
        timeline
          title 发布历史
          2025 : v1.0 发布
          2026 : v2.0 发布
        """, label: "2025"),
    ]
}
