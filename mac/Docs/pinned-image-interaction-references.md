# 钉图交互参考（官方资料）

本文只记录 Snipaste、PixPin 与 CleanShot X 的官方产品页和帮助文档中可直接验证的事实。结论用于校验 Zisla 钉图交互；未获官方资料证实的能力不会外推为竞品行为。

## 可证实的交互

| 产品 | 官方证实的行为 | 对本产品的可复用结论 | 来源 |
| --- | --- | --- | --- |
| PixPin | 贴图默认置顶；鼠标拖拽移动；滚轮缩放；`Ctrl + 滚轮`调透明度；锁定后不能移动、缩放或调透明度。 | 图片主体必须是可拖动的命中区，且锁定/鼠标穿透是唯一可以有意禁用该交互的状态。 | [贴图基本使用](https://pixpin.cn/docs/pin/base-use) |
| PixPin | 贴图移出屏幕可视区域时，托盘菜单仍会保留它；“调整贴图确保显示”会把屏幕外贴图移回可见区域。 | 不应以当前屏幕或可见区域限制拖动；需要时提供显式的找回入口，而不是在拖动时截断坐标。 | [贴图基本使用](https://pixpin.cn/docs/pin/base-use) |
| Snipaste | 贴图可缩放、透明、鼠标穿透；缩放方式是滚轮、`+`/`-` 或拖动贴图窗口**边缘**；透明度用 `Ctrl + 滚轮` 或 `Ctrl + +`/`-`。 | 窗口边缘应保持稳定可命中；滚轮类输入可直接应用在贴图主体，不依赖工具栏。 | [基础操作](https://docs.snipaste.com/wiki/%E5%9F%BA%E7%A1%80%E6%93%8D%E4%BD%9C.md)；[Snipaste 产品页](https://www.snipaste.com/) |
| Snipaste | 按住 `Shift` 拖动贴图可在接近对齐时吸附；高级设置含 `magnetic_attach_threshold`。 | 可把跨贴图/屏幕边界的拖动作为连续窗口移动处理；吸附是后续增强，不应替代基础拖动。 | [高级技巧](https://docs.snipaste.com/wiki/%E9%AB%98%E7%BA%A7%E6%8A%80%E5%B7%A7.md)；[高级设置](https://docs.snipaste.com/wiki/%E9%AB%98%E7%BA%A7%E8%AE%BE%E7%BD%AE.md) |
| Snipaste | 官方 FAQ 将“贴图无法移动、右键菜单也出不来”解释为鼠标穿透模式。 | 导航条、图片主体和缩放命中区必须共享穿透状态；非穿透状态下导航条不能吞掉图片的移动、缩放或手势事件。 | [常见问题](https://docs.snipaste.com/wiki/%E5%B8%B8%E8%A7%81%E9%97%AE%E9%A2%98.md) |
| CleanShot X | Floating Screenshots 始终浮于所有窗口之上，支持调大小和透明度；Lock Mode 用于与截图下方的应用交互。 | “始终置顶”与“允许底层交互”应是独立状态，不能为了置顶而关闭钉图交互。 | [CleanShot X Features](https://cleanshot.com/features#floating) |
| CleanShot X | Quick Access Overlay 支持位置、尺寸、多显示器及滑动手势。 | 多显示器与手势是成熟截图工作流的合理基线；具体手势映射仍须由本产品实现和测试保证。 | [CleanShot X Features](https://cleanshot.com/features#quickaccess) |

## 未能证实的项目

- Snipaste、PixPin 和 CleanShot X 的上述官方资料均未明确承诺“触控板双指捏合缩放”。
- 未找到官方资料将“向上滑更不透明、向下滑更透明”列为钉图手势；Snipaste、PixPin 公开的是修饰键加滚轮调透明度。
- Snipaste 官方描述的是拖动**边缘**缩放，不是四角专用缩放；未找到另外两款的官方四角缩放说明。
- 未找到三者针对钉图“可任意跨显示器拖拽”或“跨 Space 持续显示”的明确承诺。Snipaste FAQ 仅表明拖出屏幕上边界属于需要兼容的问题，PixPin 提供将屏幕外贴图移回可见区域的恢复操作。
- CleanShot X 的多显示器与滑动手势说明属于 Quick Access Overlay，官方页未将其明确归属到 Floating Screenshots。

因此，Zisla 的“跨显示器连续拖动、四角缩放、捏合缩放、上下滑透明度、导航条不拦截这些操作”应视为自身的产品设计与回归测试要求，而非竞品官方已证实的行为。
