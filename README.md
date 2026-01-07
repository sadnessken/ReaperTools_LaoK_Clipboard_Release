# LaoK Clipboard 用户操作手册（V0.13）
简单好用的Reaper夸工程搜索与常驻复制粘贴工具！！！
使用说明：直接在Reapack订阅https://raw.githubusercontent.com/sadnessken/ReaperTools_LaoK_Clipboard_Release/master/index.xml
之后安装LaoK_Clipboard即可
请务必按照初次使用教程设置

v0.12新增功能：
- 支持Pin迁移至其他Tag的操作
- 右键pin会多出move选项，选择后会有二级窗口
- 搜索栏增加悬浮显示，长名友好
- PC字体调优
- 搜索栏结果选中，Reaper最大高亮为1，不会出现复选情况
- 新增搜索过滤快捷指令：
  - `-i `：仅搜索 Item（输入 `-i` 后加空格即可进入该模式）
  - `-t `：仅搜索 Track（输入 `-t` 后加空格即可进入该模式）
  - 进入对应模式成功后，搜索栏中最右边会有图形显示

v0.13新增功能：
- 优化代码结构，提高运行效率
- 按钮添加左上角圆形角标，T表示Track，I表示Item
- 搜索模式新增 `-r ` / `-m `（Region/Marker）并显示对应徽标。
- 美化布局
- 限制Pin与Tag按钮最大文本长度
## 依赖与文件清单

- 依赖：
  - REAPER 7.x
  - SWS Extension（用于全局启动）
  - ReaImGui（界面所需）
  - JS_ReaScriptAPI
- 脚本清单：
  - `LaoK_Clipboard_Main.lua`（主界面）
  - `LaoK_Clipboard_Action_Pin.lua`（Pin）
  - `LaoK_Clipboard_Action_Paste.lua`（Paste）
  - `LaoK_Clipboard_Toolbar_Toggle.lua`（工具栏切换显示/隐藏）
  - `LaoK_Clipboard_Shared.lua`（共享库）

## 初次设置教程

### 1) 导入脚本到 Action List（如果订阅Repack可忽略）
1. 打开 REAPER：`Actions -> Show action list...`
2. 点击 `ReaScript: Load...`
3. 依次选择并加载所有脚本（不再枚举）：
   - `LaoK_Clipboard_Main.lua`
   - `LaoK_Clipboard_Action_Pin.lua`
   - `LaoK_Clipboard_Action_Paste.lua`
   - `LaoK_Clipboard_Toolbar_Toggle.lua`
   - `LaoK_Clipboard_Shared.lua`

### 2) 设置 Main 为全局启动（SWS）【必做！】
1. 菜单进入：`Extensions -> Startup actions -> Set global startup actions...`
2. 点击 `Add`
3. 在 Action 列表中找到 `Script: LaoK_Clipboard_Main.lua`，添加并确认
4. 以后 REAPER 启动时 Main 会自动常驻运行

### 3) 主工具栏添加图标（MainBar）
1. 右键主工具栏空白处 -> `Customize toolbar...`
2. 点击 `Add`
3. 搜索并选择 `Script: LaoK_Clipboard_Toolbar_Toggle.lua`
4. 选择一个你喜欢的图标并确认
5. 该按钮用于显示/隐藏主窗口（脚本常驻时再次点击会切换显示）

### 4) 为 Pin / Paste 设置快捷键（推荐）【强烈建议快捷键shift+C/V，体验很舒适！】
1. 打开 Action List
2. 搜索并选中：
   - `Script: LaoK_Clipboard_Action_Pin.lua`
   - `Script: LaoK_Clipboard_Action_Paste.lua`
3. 分别点击 `Add...` 设置快捷键

### 5) 首次运行与用户数据创建
完成以上设置后，建议重启 REAPER，以触发标准启动流程。
1. 重启后脚本会自动常驻运行
2. 如未看到窗口，点击工具栏上的 `LaoK_Clipboard_Toolbar_Toggle.lua` 按钮显示主界面
2. 若未找到用户数据，会弹出 `User Data Setup` 窗口：
   - 点击 `新建`：选择保存位置
   - 按提示创建用户名
3. 系统会生成：`用户名_ClipUserData.json`
4. 用户数据与日志文件位于同一目录：
   - `用户名_ClipUserData.json`
   - `userdata.log`
5. 所有数据自动保存，无需手动保存

## 日常操作说明（详细）

### 1) 窗口显示/隐藏
- 主窗口右上角 `-` 为隐藏按钮
- 再次点击主工具栏上的 Main 图标可重新显示
- 脚本常驻运行，不需要手动关闭

### 2) 标签（Tag）管理
- 左侧是标签列，点击切换当前标签
- `+ Add Tag` 添加标签
- 右键标签：
  - `Rename` 重命名
  - `Delete` 删除（其下 Pin 会自动归到 Default）

### 3) Pin 管理
- 右侧为 Pin 按钮网格
- 点击 Pin 可选中
- 右键 Pin：
  - `Rename` 重命名
  - `Delete` 删除

### 4) Pin 操作（保存）
#### Pin 轨道
1. 选择需要保存的一组轨道（含子轨道）
2. 运行 `Pin` 脚本
3. 将保存：
   - 轨道结构与 FX
   - 轨道上的 Items（含 take_fx / item_fx / 包络等）
   - 媒体文件路径（自动绝对化）

#### Pin Items
1. 选择需要保存的 Items
2. 运行 `Pin` 脚本
3. Items 会按相对偏移保存，便于后续粘贴对齐

### 5) Paste 操作（粘贴）
1. 在主界面选中一个 Pin
2. 将编辑光标放到目标位置
3. 运行 `Paste` 脚本

#### Track Pin 的粘贴行为
- 在当前选中轨道处插入新轨道（未选中则追加到末尾）
- 恢复轨道结构 + FX + Items
- 仅保留 Pin 内部轨道间的路由

#### Item Pin 的粘贴行为
- 若当前有选中轨道：以该轨道为基准粘贴
- 若无选中轨道：自动新建轨道

#### 媒体缺失时
- 工具仍会创建 Items
- REAPER 会以缺失/离线媒体状态呈现
- 可在 `userdata.log` 查看详细提示

### 6) 搜索与定位
- 搜索框支持模糊搜索 Tracks / Items / Media / Regions / Markers
- 结果列表为三列（Name / Type / Project）
- 双击结果可跳转到工程中的目标

### 7) 设置（Settings）
点击主窗口右上角齿轮打开设置：
- 用户区域：
  - 显示当前用户名与路径
  - `Switch User` 切换用户数据
  - `Rename` 修改用户名（同时重命名 JSON）
- 功能区域：
  - `Debounce (ms)`：搜索防抖
  - `Max results`：最大搜索结果数

## 常见问题定位

1. Pin 后没看到按钮：
   - 确认当前 Tag 是否正确
   - 查看 `userdata.log` 是否记录保存成功
2. 粘贴后缺失媒体：
   - 检查源媒体路径是否存在
   - 查看 `userdata.log` 中的 missing 记录
3. 搜索无结果：
   - 尝试增大 `Max results`
   - 减小 `Debounce` 或等待索引刷新
