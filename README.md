# PostData

原生 Swift / SwiftUI 编写的 macOS API 调试客户端，功能对标 Postman 的核心体验。

![icon](PostData/Assets.xcassets/AppIcon.appiconset/icon_128x128.png)

## 功能

- **请求编辑**：任意 HTTP 方法；URL 与 Params 表格双向同步；Headers；Body 支持 none / form-data（含文件）/ x-www-form-urlencoded / raw（JSON、Text、XML、HTML、JavaScript）/ binary；JSON 一键美化
- **认证**：Bearer Token、Basic Auth、API Key（Header 或 Query），支持沿文件夹 → 集合逐级继承
- **响应查看**：状态码、耗时（DNS / TCP / TLS / TTFB / 下载明细，以及重定向链路）、大小；连接自动复用（keep-alive）；Body 支持 Pretty（JSON 高亮，保留 key 顺序）、Raw、Preview（HTML 渲染、图片）；Headers、Cookies 表格；⌘F 查找；保存到文件
- **集合**：文件夹树、右键新建 / 重命名 / 复制 / 移动 / 删除、集合变量与默认认证
- **环境变量**：`{{变量}}` 替换，优先级 Globals < 集合变量 < 当前环境；支持嵌套引用和 `{{$guid}}`、`{{$timestamp}}`、`{{$isoTimestamp}}`、`{{$randomInt}}` 等动态变量；URL 下方提示未定义的变量
- **历史记录**：按天分组，点击即可重新打开
- **导入 / 导出**：Postman Collection v2.0 / v2.1、Postman Environment / Globals；粘贴 cURL 命令（也可直接粘贴到 URL 栏）
- **代码生成**：cURL、Swift (URLSession)、JavaScript (fetch)、Python (requests)
- 多标签页，未保存修改提示，重启后恢复标签页与草稿；支持深色模式

## 环境要求

- macOS 26 或更高
- Xcode 26 或更高（开发使用 Xcode 27 / Swift 6.4）

## 构建与运行

用 Xcode 打开 `PostData.xcodeproj`，选择 `PostData` scheme 后运行（⌘R）。

命令行构建：

```bash
xcodebuild -project PostData.xcodeproj -scheme PostData -configuration Release -derivedDataPath build/DerivedData build
```

```bash
open build/DerivedData/Build/Products/Release/PostData.app
```

## 测试

核心逻辑都在 `PostDataKit` 中，不依赖 UI，可以直接用 SwiftPM 运行测试：

```bash
swift test --package-path PostDataKit
```

在 Xcode 中按 ⌘U 运行的是同一套测试。

## 项目结构

```
PostData.xcodeproj      Xcode 工程（使用文件夹同步组，新增文件自动纳入编译）
Config/Info.plist       ATS 配置：允许 http:// 与局域网请求
PostData/               App（SwiftUI）
  State/                AppModel（动作与弹窗状态）、AppStore（持久化数据）、TabsModel、RequestTabState
  Views/                侧边栏、标签栏、请求编辑器、响应视图、弹窗、设置
PostDataKit/            逻辑层（Swift Package）
  Models/               HTTPRequest、RequestCollection、APIEnvironment 等 Codable 模型
  Collections/          集合树操作与认证继承
  Variables/            {{变量}} 解析
  Networking/           RequestBuilder、Multipart 编码、HTTPClient（URLSession）
  Formatting/           保序 JSON 格式化、语法高亮分词、响应类型识别
  Import/               cURL 解析、Postman v2.1 导入导出
  CodeGen/              代码片段生成
  Persistence/          JSON 文件存储
```

## 数据存储

所有数据以 JSON 文件形式保存在 `~/Library/Application Support/PostData/`：

| 文件 | 内容 |
| --- | --- |
| `collections/<id>.json` | 每个集合一个文件 |
| `environments.json` | Globals、环境和当前选中的环境 |
| `history.json` | 历史记录 |
| `session.json` | 打开的标签页（含未保存草稿） |

启动参数 `-PostDataDataDirectory <路径>` 可以指定其他数据目录，便于测试或使用独立的工作区。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| ⌘T | 新建请求标签 |
| ⌘↩ | 发送请求 |
| ⌘. | 取消请求 |
| ⌘S / ⇧⌘S | 保存 / 另存为 |
| ⌘O | 导入 |
| ⇧⌘C | 生成代码 |
| ⌘W | 关闭当前标签 |
| ⇧⌘] / ⇧⌘[ | 下一个 / 上一个标签 |
| ⌘F | 在响应或 Body 中查找 |

## 已知限制

- 不支持 Pre-request / Tests 脚本、Postman 路径变量（`:id`）以及 OAuth 2.0、Digest 等认证方式；导入时会列出未导入的内容
- 暂不支持 WebSocket 和 GraphQL（导入的 GraphQL 请求会转换为 raw JSON body）
- GET / HEAD 请求不会发送 Body（URLSession 的限制）
- URLSession 不保留响应头的原始顺序，因此响应头按名称排序显示
