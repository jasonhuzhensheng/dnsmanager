# DNS Manager

域名续费台账，Mac 和 iPhone / iPad 本地 App。跨平台（阿里云、腾讯云、Cloudflare、GoDaddy、Namecheap……）记录域名、DNS 解析套餐、SSL 证书的付费周期，到期前发系统通知，Mac 端还能发邮件提醒。

## 功能

- **台账**：域名 / 名称、类型、付费平台、DNS 解析商、下次到期日、付费周期（每月到每 10 年）、续费价格和币种（CNY / USD / EUR / HKD）、是否自动续费、备注。
- **概况**：已过期数、提醒期内到期数、条目数和平台数、折合人民币的年化总支出；按平台汇总年化支出。
- **已续费**：左滑或右键「已续费」，到期日顺延一个周期，并留一条续费记录。
- **批量导入**：从表格粘贴 `域名, 平台, 到期日, 周期(月), 价格, 币种`，后三项可省略。
- **系统通知**（Mac 和 iOS）：提醒期开始、到期前 7 天、3 天、1 天、当天各一次；过期后每天提醒。提醒天数和每天的提醒时刻可以在设置里改。App 图标角标显示需要处理的条目数。
- **邮件提醒**（Mac）：App 常驻菜单栏，每 30 分钟检查一次；过了提醒时刻、且有条目进入新的提醒阶段时，发一封汇总邮件。Mac 睡眠错过几天，醒来也只补发一封。
- **iCloud 同步**：SwiftData + CloudKit 私有库，Mac 和 iPhone 自动同步。设置项（汇率、提醒时间、邮件配置）每台设备各存一份。

## 第一次在 Mac 上运行

前提：Xcode 16 或更新版本、Homebrew、付费 Apple 开发者账号（iCloud 同步要用）。

```sh
git clone https://github.com/jasonhuzhensheng/dnsmanager.git
cd dnsmanager
scripts/bootstrap.sh        # 装 xcodegen，问一次开发者团队 ID，生成并打开 DNSManager.xcodeproj
```

然后在 Xcode 里：

1. 选 `DNSManager-macOS` 方案，目标选「My Mac」，⌘R 运行。第一次会请求通知权限。
2. 选 `DNSManager-iOS` 方案，目标选你的 iPhone（或模拟器），⌘R 运行。
3. 如果签名报 iCloud 容器相关的错：打开目标的 **Signing & Capabilities › iCloud**，勾选 `iCloud.com.jasonhu.dnsmanager`（没有就点 + 新建同名容器）。两个目标都要勾。

模拟器上 iCloud 同步要先在模拟器的「设置」里登录 Apple ID；通知在模拟器上也能弹。

### 设置邮件提醒（Mac）

菜单栏图标 › 齿轮 › 「邮件提醒」：

| 邮箱 | 服务器 | 端口 | 密码 |
|---|---|---|---|
| Gmail | smtp.gmail.com | 465 | 开启两步验证后，在 myaccount.google.com/apppasswords 生成的应用专用密码 |
| QQ 邮箱 | smtp.qq.com | 465 | 邮箱设置里开启 SMTP 后得到的授权码 |
| 163 邮箱 | smtp.163.com | 465 | 授权码 |
| iCloud 邮件 | smtp.mail.me.com | 465 | appleid.apple.com 生成的 App 专用密码 |

填好后点「保存」把密码存进钥匙串，再点「发送测试邮件」。建议同时打开「登录时自动启动」，否则 Mac 重启后要手动打开 App 才会继续检查。

## 命令行检查

```sh
cd LedgerCore && swift test     # 核心逻辑测试（状态判断、通知排期、邮件阶段、导入解析、SMTP 协议）
scripts/check.sh                # 测试 + 不签名编译两个平台，日志在 build/check.log
```

## 代码结构

| 路径 | 内容 |
|---|---|
| `LedgerCore/` | 纯逻辑 Swift 包，不依赖 UI 和存储：状态判断、年化金额、通知排期（`ReminderPlanner`）、邮件阶段与正文（`DigestPlanner`）、粘贴导入、MIME 和最小 SMTP 客户端 |
| `App/Model/Renewal.swift` | SwiftData 模型（兼容 CloudKit：所有属性有默认值、无唯一约束） |
| `App/Services/` | 数据容器（iCloud 失败时退回本地）、通知排期、Mac 邮件提醒、钥匙串、设置项 |
| `App/Views/` | 主界面、编辑、导入、设置、Mac 菜单栏 |
| `project.yml` | XcodeGen 工程描述，生成 iOS 和 macOS 两个目标，共用 `App/` 的代码 |

## 已知限制

- **iPhone 不发邮件**：iOS 不允许 App 在后台静默发邮件，邮件只由 Mac 发。
- **iPhone 上的通知依赖 App 被唤醒**：在 Mac 上新加的条目，要等 iPhone 打开 App，或系统在后台唤醒 App（每天若干次，时间由系统决定）后，才会排进 iPhone 的通知。
- **iOS 最多排 60 条待发通知**（系统上限 64），条目很多时只排最近的 60 条，打开 App 时会续排。
- **SMTP 只支持 465 端口的 SSL 直连**，不支持 587 端口的 STARTTLS。
- 不连接各注册商的 API，到期日需要手动录入或批量导入。

## 当前状态（2026-10-20）

- 代码在没有 Swift 工具链的 Linux 容器里写成，**尚未在 Mac 上编译过**。第一次运行 `scripts/check.sh` 可能会有少量编译错误，把 `build/check.log` 末尾贴回来即可修。
- 待确定：App 图标、正式名称。
