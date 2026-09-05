# 多语言适配清单

macOS 界面和官网共用同一套 17 种语言。触及用户可见文案的改动要在同一个补丁里覆盖全部语言；漏语言不会报错，只会在运行时静默显示成另一种语言。

## 语言集合的唯一来源

- macOS：`AppLanguage`（`mac/Sources/ZislaKit/AppLanguageStore.swift`），`allCases` 即全量语言，`isRightToLeft` 只有 `ar` 为真。
- 官网：`siteLocales`（`web/src/locales.ts`），按文件注释与 `AppLanguage` 保持同一集合；`localeNativeNames`、`localeDirection`、`openGraphLocales` 都以它为键。
- 增删语言必须两端同步，并在交付中说明；不要只改一端。

## macOS 界面

1. 文案不写死在视图里。Zisla 用 `AppLocalization.text/string/format`、`AppLocalizedText`、`AppLocalizedFormatText`（`mac/Sources/ZislaKit/AppLocalization.swift`）；KeyboardKit 用 `L10n`（`mac/Sources/KeyboardKit/KeyboardLocalization.swift`）。需要按指定语言渲染而不是跟随环境时，传 `locale:`，不要读全局当前语言。
2. key 就是简体中文原文，译文写进 `mac/Resources/Localization/<语言>.lproj/Localizable.strings`。新增 key 要同时写入全部 17 张表，包括把中文 key 显式映射到自身的 `zh-Hans`。
3. 缺 key 时 `localizedString(forKey:value:table:)` 以 key 兜底，界面直接显示中文原文，没有编译错误也没有警告。漏翻译只能靠测试发现。
4. 带占位符的 key，译文里 `%@`、`%ld`、`%.1f` 的类型和个数必须与 key 一致，且不要调整顺序。不一致会让 `String(format:)` 输出错乱或崩溃。
5. `zh-Hans` 表的条目当前少于其他表，缺的部分靠 key 兜底成中文，界面是正确的。这是历史遗留，不要在本次改动里顺手补全。

## 官网

1. 可见字符串只来自 `web/src/i18n/<语言>.ts` 的 catalog。id、顺序、锚点链接等与语言无关的结构留在 `web/src/content.ts`，不要复制进 catalog。
2. 新增字段先扩展 `SiteContent`（`web/src/content.ts`）和 `web/src/i18n/en.ts`（英文是合并基准），再补齐其余 16 个 catalog。
3. catalog 有两种写法，漏字段的后果不同，改之前先看目标文件用的是哪种：
   - `export const xx: SiteContent = { ... }`：缺字段会被 `tsc --noEmit` 拦下。
   - `createCatalog({ ... })`：参数是 `DeepPartial<SiteContent>`，缺字段既不报错也不警告，运行时静默回退英文。当前 `ar`、`es`、`id`、`it`、`nl`、`pt-BR`、`ru`、`th`、`tr`、`vi` 属于这一类。
4. 语言相关的元信息随文案一起改：`updateDocumentMetadata`（`web/src/main.ts`）里的 `lang`、`dir`、`title`、`description`、`og:title`、`og:description`、`og:locale`。新增页面级文案要挂到 `content.meta`，否则切语言时不会更新。
5. catalog 按语言拆 chunk（`web/src/i18n/index.ts` 的 `catalogLoaders`）。新增语言只补一个 loader，不要改回静态 import，否则一次访问会下载全部语言。

## 机器可验证的部分

- macOS：在 `mac/Tests/ZislaTests` 写“从源码扫出运行时真正查询的 key，再逐 `AppLanguage.allCases` 核对资源”的测试，断言 key 存在且占位符一致。`BatteryLocalizationTests.everyLanguageTranslatesBatteryKeys` 是可复制的范例：正则从调用点抽字面量、`indirectKeys` 补间接传入的 key、`NSDictionary(contentsOf:)` 读 `.strings`、比对占位符集合。同时对关键文案断言具体译文，确保按 locale 取值这条链路真的生效。
- 官网：`npm --prefix web run typecheck` 只覆盖完整类型写法的 catalog。`createCatalog` 语言需要另写断言：逐 locale 调用 `loadCatalog`，检查本次新增字段存在且不等于英文基准值。`web/package.json` 目前没有 `test` 脚本，Web CI 的 `npm run test --if-present` 会空过，所以这类断言要以一次性脚本形式跑出结果并写进交付，或在补丁里补上测试入口。
- 不要用“构建通过”“截图看着正常”代替上述断言。

## 交给开发者亲验的部分

字号、截断、换行、RTL 镜像、字体缺字和语气是否自然只能人工确认。按 [developer-experience-acceptance.md](developer-experience-acceptance.md) 列为待亲验项，不要预填通过。

## 不算适配完成

- 只改中文或只改英文，其余语言留待后续补。
- 用 `TODO`、占位符、直接复制英文当译文填满其他语言。
- 把新文案写死在视图或模板里，绕过 key 与 catalog。
- 以“其他语言用户少”“后续统一处理”为理由跳过。确实无法给出可靠译文时，列出具体 key 与原因请开发者决定，不要留半成品。
