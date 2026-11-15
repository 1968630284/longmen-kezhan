# UI-01 验收工具：从 src/00_header.ps1 解析双主题色板，按 WCAG 2.2 公式验算对比度。
# 只读，不修改任何文件。退出码 0 表示全部达标。
import io, os, re, sys

ROOT = r'D:\tmp\nailong'
HEADER = os.path.join(ROOT, 'src', '00_header.ps1')
s = io.open(HEADER, 'rb').read().decode('utf-8-sig')

def parse(name):
    m = re.search(r'\$script:%s = @\{(.*?)\n\}' % name, s, re.S)
    if not m:
        raise SystemExit('palette not found: ' + name)
    return dict(re.findall(r"(\w+)\s*=\s*'(#[0-9A-Fa-f]{6,8})'", m.group(1)))

light, dark = parse('UiLight'), parse('UiDark')

def lum(h):
    h = h.lstrip('#')
    if len(h) == 8:  # AARRGGBB：忽略 alpha，按不透明底色近似
        h = h[2:]
    r, g, b = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)

def cr(a, b):
    x, y = lum(a), lum(b)
    hi, lo = max(x, y), min(x, y)
    return (hi + 0.05) / (lo + 0.05)

# (说明, 前景键, 背景键, 门槛)
cases = [
    ('主文字 / 窗口底',      'Ink',       'Surface',     4.5),
    ('主文字 / 卡片',        'Ink',       'Card',        4.5),
    ('次要文字 / 窗口底',    'Meta',      'Surface',     4.5),
    ('提示文字 / 卡片',      'Hint',      'Card',        4.5),
    ('提示文字 / 输入框',    'Hint',      'Input',       4.5),
    ('输入正文 / 输入框',    'Ink',       'Input',       4.5),
    ('次级文字 / 卡片',      'Ink2',      'Card',        4.5),
    ('按钮白字 / 主色',      'AccentInk', 'Accent',      4.5),
    ('自己气泡文字',         'SelfInk',   'SelfBg',      4.5),
    ('组件描边 / 卡片',      'Stroke',    'Card',        3.0),
    ('焦点环 / 卡片',        'Focus',     'Card',        3.0),
    ('在线绿 / 窗口底',      'LiveGreen', 'Surface',     3.0),
]

fails = 0
for theme, pal in (('浅色', light), ('深色', dark)):
    print('--- %s主题 ---' % theme)
    for label, fg, bg, need in cases:
        a, b = pal.get(fg), pal.get(bg)
        if not a or not b:
            print('  [SKIP] %-20s 缺键 %s/%s' % (label, fg, bg))
            continue
        v = cr(a, b)
        ok = v >= need
        if not ok:
            fails += 1
        print('  [%s] %-20s %6.2f:1 (需 %.1f)  %s / %s' %
              ('PASS' if ok else 'FAIL', label, v, need, a, b))
print('\n总计不达标 =', fails)
sys.exit(1 if fails else 0)
