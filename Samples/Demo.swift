import Foundation

/// TextLens 语法高亮测试
struct Greeting: Codable {
    let name: String
    let score: Double

    func message() -> String {
        // 中英文混排，看看注释颜色
        let template = "你好，\(name)！得分：\(score)"
        return template
    }
}

let sample = Greeting(name: "透镜", score: 99.5)
print(sample.message())
