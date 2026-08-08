# MinecraftHelper v1.0.0

iOS Minecraft Bedrock（`com.mojang.minecraftpe`）多功能辅助 tweak：悬浮窗 UI、10 符号探测、12 项功能、C++ 日志收集与导出。

## 产物

| 文件 | 用途 |
|---|---|
| `MinecraftHelper_1.0.0_iphoneos-arm64.deb` | 越狱安装（rootless，palera1n/Dopamine 等） |
| `MinecraftHelper_1.0.0_iphoneos-arm.deb`  | 越狱安装（rootful，unc0ver/checkra1n 旧式） |
| `MinecraftHelper.dylib` | **iGameGod 直接导入用**（deb 内同款） |

## 安装

### 方式 A：越狱（deb）
用 Sileo / Zebra / Filza 安装对应 deb，重启 Minecraft 即可。postinst 已做 plist 完整性校验。

### 方式 B：iGameGod（非越狱）
1. 从 deb 中解出 `MinecraftHelper.dylib`（或用 CI 产出的独立 dylib 工件）
2. iGameGod → **Tweaks 标签** → ➕ → Create New Folder → 进入文件夹 → ➕ → **Import Tweak** → 选择 dylib
3. 用 iGameGod 启动游戏。无 substrate 时 hooks 自动休眠，悬浮窗/日志/HUD 照常工作，**不会闪退**

## 功能（12 项）

| 功能 | 说明 | 状态机制 |
|---|---|---|
| 无敌模式 | 拦截 Player::hurt | 符号命中→已生效 |
| 一击必杀 | Actor::hurt 伤害×50，建议与无敌同开 | 符号命中→已生效 |
| 移速增强 ×2 | 放大 Actor::setSpeed | 符号命中→已生效 |
| 自动疾跑/飞行/自动跳跃 | 需玩家对象运行时数据 | 待数据 |
| 防击退 | 拦截 Mob::knockback | 符号命中→已生效 |
| 无坠落伤害 | 需伤害来源识别 | 待数据 |
| 自动攻击 | Mob::attack 挂钩 | 符号命中→已生效 |
| 全亮度 | 屏幕亮度拉满 | **直接生效** |
| 性能 HUD | 悬浮球实时 FPS / 内存 / 符号命中数 | **直接生效** |
| 计时加速 | MinecraftClient::tick 挂钩 | 符号命中→已生效 |

> 状态显示：🟢已生效 / 🟠符号缺失 / ⚪待数据。
> iOS MCPE 二进制符号被剥离，probe 未命中属预期；命中即自动绑定 hook —— 这正是"不依赖偏移"的按符号 hook 路径。

## 日志

- 落盘：游戏沙盒 `Documents/MinecraftHelper.log`（ring buffer 512 行 + 文件追加）
- 菜单内 **导出日志**（系统分享面板）/ **复制日志**（剪贴板）
- 启动即记录：注入时间、10 符号探测结果（HIT/MISS）、plist 双路径校验、hook 绑定情况

## 符号探测（%ctor）

```
probe[00] _ZN6Player4hurtERK17ActorDamageSourceibb => HIT/MISS
probe[01] _ZN5Actor4hurtERK17ActorDamageSourceibb  => HIT/MISS
probe[02] _ZN5Actor8setSpeedEf                     => HIT/MISS
probe[03] _ZN3Mob6attackER5Actor                   => HIT/MISS
probe[04] _ZN15MinecraftClient4tickEv              => HIT/MISS
probe[05] _ZN3Mob9knockbackER5Actoriffffff         => HIT/MISS
probe[06] _ZN6Player12getAbilitiesEv               => HIT/MISS
probe[07] _ZN6Player5swingEv                       => HIT/MISS
probe[08] _ZN6Player11getPositionEv                => HIT/MISS
probe[09] _ZN6Player13addExperienceEi              => HIT/MISS
```

签名基于公开反编译推测，随游戏版本变化；悬浮窗内可随时"重探符号"。

## 防闪退设计

- substrate/ellekit 运行时 `dlopen` 探测，找不到则 hooks 全部休眠（iGameGod 场景）
- 所有 hook 均空指针安全，MSFindSymbol 返回 NULL 不装 hook
- 悬浮窗不抢占 key window，游戏触摸输入不受影响
- CADisplayLink 仅 HUD/菜单开启时运行，A11（iPhone 8/8+/X）轻松 60fps
- 全部 UI 主线程 + ARC + frame 布局（无 AutoLayout 开销）

## 自建

GitHub Actions（`.github/workflows/build.yml`）：push 后 `macos-latest` 上自动编译 rootless + rootful 双 deb 与 dylib，工件可直接下载。

## 免责声明

仅限单机/自用测试。多人服务器使用辅助可能违反服务条款并被封号，风险自负。
