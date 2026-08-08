#import "OverlayManager.h"
#import "MHFeatures.h"
#import "MHCommon.h"
#import <mach/mach.h>
#import <QuartzCore/QuartzCore.h>

// ---- 轻量内存读取（真实数据，不依赖游戏符号） ----
static double MHMemoryUsedMB(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
    if (kr != KERN_SUCCESS) return 0;
    return (double)(info.internal + info.compressed) / (1024.0 * 1024.0);
}

// ---- 功能行视图 ----
@interface MHFeatureRowView : UIView
@property (nonatomic, strong) UISwitch *sw;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, weak) OverlayManager *owner;
@end
@implementation MHFeatureRowView
- (void)swChanged:(UISwitch *)s {
    [[MHFeatureManager shared] setEnabled:s.on forIdentifier:self.identifier];
    [self.owner refreshRow:self];
}
@end

@implementation OverlayManager {
    UIWindow *_window;
    UIButton *_pill;
    UILabel *_pillFps;
    UIView *_menuWrap;
    UIView *_card;
    UILabel *_statsLabel;
    NSMutableDictionary<NSString *, MHFeatureRowView *> *_rows;
    CADisplayLink *_link;
    NSTimeInterval _lastStats;
    NSUInteger _frameCount;
    CGPoint _dragOrigin;
    BOOL _menuOpen;
    BOOL _hudEnabled;
}

+ (instancetype)sharedInstance {
    static OverlayManager *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [OverlayManager new]; });
    return s;
}

#pragma mark - 启动

- (void)start {
    if (_window) return;
    UIWindow *w = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    w.windowLevel = UIWindowLevelStatusBar + 100; // 悬浮于游戏之上，但不抢占 key（游戏触摸不受影响）
    w.hidden = NO;
    w.backgroundColor = [UIColor clearColor];
    w.userInteractionEnabled = YES;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor clearColor];
    w.rootViewController = vc;
    _window = w;

    // ---- 悬浮球 ----
    CGFloat size = 54;
    UIButton *pill = [UIButton buttonWithType:UIButtonTypeCustom];
    pill.frame = CGRectMake(w.bounds.size.width - size - 16, w.bounds.size.height * 0.42, size, size);
    pill.layer.cornerRadius = 17;
    pill.layer.borderWidth = 1;
    pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
    pill.backgroundColor = [UIColor colorWithWhite:0.07 alpha:0.82];
    pill.layer.shadowColor = [UIColor blackColor].CGColor;
    pill.layer.shadowOpacity = 0.35;
    pill.layer.shadowRadius = 8;
    pill.layer.shadowOffset = CGSizeMake(0, 3);
    [pill addTarget:self action:@selector(pillTapped) forControlEvents:UIControlEventTouchUpInside];
    _pill = pill;

    UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(0, 9, size, 22)];
    tl.text = @"MH";
    tl.font = [UIFont boldSystemFontOfSize:17];
    tl.textColor = [UIColor whiteColor];
    tl.textAlignment = NSTextAlignmentCenter;
    [pill addSubview:tl];

    _pillFps = [[UILabel alloc] initWithFrame:CGRectMake(0, 30, size, 14)];
    _pillFps.font = [UIFont monospacedDigitSystemFontOfSize:9 weight:UIFontWeightSemibold];
    _pillFps.textColor = [UIColor systemGreenColor];
    _pillFps.textAlignment = NSTextAlignmentCenter;
    _pillFps.text = @"--";
    _pillFps.hidden = YES;
    [pill addSubview:_pillFps];

    [w addSubview:pill];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [pill addGestureRecognizer:pan];

    // 出现动画
    pill.transform = CGAffineTransformMakeScale(0.6, 0.6);
    [UIView animateWithDuration:0.5 delay:0.1 usingSpringWithDamping:0.6 initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{ pill.transform = CGAffineTransformIdentity; }
                     completion:nil];

    _rows = [NSMutableDictionary dictionary];
    [self updateLinkState];
    MHLogPrint(MHLogLevelInfo, "overlay started (pill at %.0f,%.0f)", pill.center.x, pill.center.y);
}

#pragma mark - 悬浮球交互

- (void)pillTapped {
    [self toggleMenu];
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        _dragOrigin = g.view.center;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:_window];
        CGFloat w = _window.bounds.size.width, h = _window.bounds.size.height;
        CGFloat nx = MAX(34, MIN(_dragOrigin.x + t.x, w - 34));
        CGFloat ny = MAX(70, MIN(_dragOrigin.y + t.y, h - 70));
        g.view.center = CGPointMake(nx, ny);
    } else if (g.state == UIGestureRecognizerStateEnded) {
        CGPoint c = g.view.center;
        BOOL left = c.x < _window.bounds.size.width / 2;
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.8
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{ g.view.center = CGPointMake(left ? 46 : _window.bounds.size.width - 46, c.y); }
                         completion:nil];
    }
}

#pragma mark - 菜单

- (void)toggleMenu {
    if (_menuOpen) [self closeMenu]; else [self openMenu];
}

- (void)openMenu {
    if (_menuOpen) return;
    _menuOpen = YES;

    UIWindow *w = _window;
    UIView *wrap = [[UIView alloc] initWithFrame:w.bounds];
    wrap.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0];
    [w addSubview:wrap];
    _menuWrap = wrap;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeMenu)];
    [wrap addGestureRecognizer:tap];

    CGFloat cw = MIN(w.bounds.size.width - 28, 350);
    CGFloat ch = MIN(w.bounds.size.height - 120, 566);
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake((w.bounds.size.width - cw) / 2, (w.bounds.size.height - ch) / 2, cw, ch)];
    card.layer.cornerRadius = 24;
    card.clipsToBounds = YES;
    card.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.96];
    card.layer.borderWidth = 1;
    card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    [wrap addSubview:card];
    _card = card;

    // header
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, cw - 90, 24)];
    title.text = @"MinecraftHelper";
    title.font = [UIFont boldSystemFontOfSize:19];
    title.textColor = [UIColor whiteColor];
    [card addSubview:title];

    UILabel *ver = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, cw - 90, 16)];
    ver.text = [NSString stringWithFormat:@"v%s · 符号探测 · C++ 日志", MH_VERSION];
    ver.font = [UIFont systemFontOfSize:11];
    ver.textColor = [UIColor colorWithWhite:0.85 alpha:0.6];
    [card addSubview:ver];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(cw - 48, 16, 32, 32);
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = [UIColor whiteColor];
    close.layer.cornerRadius = 16;
    close.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    [close addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:close];

    // 实时统计
    _statsLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 64, cw - 40, 20)];
    _statsLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _statsLabel.textColor = [UIColor systemGreenColor];
    _statsLabel.text = @"FPS --    RAM -- MB    符号 0/10";
    [card addSubview:_statsLabel];

    // 功能列表
    CGFloat topY = 92, bottomH = 64;
    UIScrollView *sc = [[UIScrollView alloc] initWithFrame:CGRectMake(0, topY, cw, ch - topY - bottomH)];
    sc.showsVerticalScrollIndicator = NO;
    [card addSubview:sc];

    CGFloat rowH = 56, y = 4;
    for (MHFeature *f in [MHFeatureManager shared].features) {
        MHFeatureRowView *row = [self makeRowForFeature:f width:cw - 28 frame:CGRectMake(14, y, cw - 28, rowH)];
        row.owner = self;
        [sc addSubview:row];
        _rows[f.identifier] = row;
        y += rowH;
    }
    sc.contentSize = CGSizeMake(cw - 28, y + 4);

    // 底部按钮：导出日志 / 复制日志 / 重探符号
    NSArray *btnData = @[
        @[@"square.and.arrow.up", @"导出日志", @0],
        @[@"doc.on.doc", @"复制日志", @1],
        @[@"arrow.clockwise", @"重探符号", @2],
    ];
    CGFloat bw = (cw - 56) / 3;
    for (NSArray *bd in btnData) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(20 + ([bd[2] intValue]) * (bw + 8), ch - 50, bw, 36);
        [b setTitle:bd[1] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
        b.layer.cornerRadius = 10;
        b.tag = [bd[2] intValue];
        [b addTarget:self action:@selector(footerTapped:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:b];
    }

    [self refreshAllRows];
    [self updateLinkState];

    // 弹簧入场
    card.transform = CGAffineTransformMakeScale(0.88, 0.88);
    card.alpha = 0;
    [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.7
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         wrap.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
                         card.transform = CGAffineTransformIdentity;
                         card.alpha = 1;
                     }
                     completion:nil];
    MHLogPrint(MHLogLevelInfo, "menu opened");
}

- (void)closeMenu {
    if (!_menuOpen) return;
    _menuOpen = NO;
    UIView *wrap = _menuWrap, *card = _card;
    _menuWrap = nil; _card = nil; _statsLabel = nil;
    [_rows removeAllObjects];
    [self updateLinkState];
    [UIView animateWithDuration:0.22 animations:^{
        wrap.alpha = 0;
        card.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL done) { [wrap removeFromSuperview]; }];
}

#pragma mark - 功能行

- (MHFeatureRowView *)makeRowForFeature:(MHFeature *)f width:(CGFloat)w frame:(CGRect)frame {
    MHFeatureRowView *row = [[MHFeatureRowView alloc] initWithFrame:frame];
    row.identifier = f.identifier;

    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(2, 14, 28, 28)];
    UIImage *img = [UIImage systemImageNamed:f.iconName];
    if (!img) img = [UIImage systemImageNamed:@"circle"];
    iv.image = img;
    iv.tintColor = [UIColor systemTealColor];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    [row addSubview:iv];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(38, 8, w - 150, 20)];
    title.text = f.title;
    title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    title.textColor = [UIColor whiteColor];
    [row addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(38, 28, w - 150, 18)];
    sub.text = f.subtitle;
    sub.font = [UIFont systemFontOfSize:10.5];
    sub.textColor = [UIColor colorWithWhite:0.85 alpha:0.55];
    sub.lineBreakMode = NSLineBreakByTruncatingTail;
    [row addSubview:sub];

    UILabel *st = [[UILabel alloc] initWithFrame:CGRectMake(w - 128, 18, 62, 18)];
    st.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightSemibold];
    st.textAlignment = NSTextAlignmentRight;
    [row addSubview:st];
    row.stateLabel = st;

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(w - 60, 11, 51, 31)];
    sw.transform = CGAffineTransformMakeScale(0.78, 0.78);
    [sw addTarget:row action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];
    row.sw = sw;

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, frame.size.height - 0.5, w, 0.5)];
    sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    [row addSubview:sep];
    return row;
}

- (void)refreshRow:(id)row {
    MHFeatureRowView *r = (MHFeatureRowView *)row;
    MHFeature *f = [[MHFeatureManager shared] featureWithIdentifier:r.identifier];
    r.sw.on = f.isEnabled;
    NSString *txt; UIColor *col;
    switch (f.state) {
        case MHFeatureStateActive:   txt = @"已生效";   col = [UIColor systemGreenColor];  break;
        case MHFeatureStateNoSymbol: txt = @"符号缺失"; col = [UIColor systemOrangeColor]; break;
        default:                     txt = @"待数据";   col = [UIColor secondaryLabelColor]; break;
    }
    r.stateLabel.text = txt;
    r.stateLabel.textColor = col;
}

- (void)refreshAllRows {
    for (MHFeatureRowView *r in _rows.allValues) [self refreshRow:r];
}

#pragma mark - 底部按钮

- (void)footerTapped:(UIButton *)b {
    if (b.tag == 0) [self exportLog];
    else if (b.tag == 1) [self copyLog];
    else [self reprobe];
}

- (void)exportLog {
    NSString *path = MHLogExportToFile();
    UIPasteboard.generalPasteboard.string = MHLogContents(); // 兜底：无论分享是否成功都进剪贴板
    UIActivityViewController *avc = [[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    if (_window.rootViewController) {
        [_window.rootViewController presentViewController:avc animated:YES completion:nil];
    }
    [self toast:@"日志已导出"];
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string = MHLogContents();
    [self toast:@"日志已复制到剪贴板"];
}

- (void)reprobe {
    MHProbeSymbols();
    MHInstallHooks();
    [self refreshAllRows];
    [self toast:@"已重新探测符号"];
}

#pragma mark - 性能 HUD（CADisplayLink，仅需要时开启）

- (void)updateLinkState {
    BOOL need = _hudEnabled || _menuOpen;
    if (need && !_link) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(linkTick:)];
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        _lastStats = CACurrentMediaTime();
        _frameCount = 0;
    } else if (!need && _link) {
        [_link invalidate];
        _link = nil;
    }
}

- (void)linkTick:(CADisplayLink *)l {
    _frameCount++;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - _lastStats < 1.0) return;
    double fps = _frameCount / (now - _lastStats);
    _frameCount = 0;
    _lastStats = now;
    double ram = MHMemoryUsedMB();
    int hits = MHProbeHitCount();
    NSString *s = [NSString stringWithFormat:@"FPS %.0f    RAM %.0f MB    符号 %d/10", fps, ram, hits];
    if (_statsLabel) _statsLabel.text = s;
    if (_hudEnabled && _pillFps) _pillFps.text = [NSString stringWithFormat:@"%.0f", fps];
}

- (void)setHudEnabled:(BOOL)enabled {
    _hudEnabled = enabled;
    _pillFps.hidden = !enabled;
    [self updateLinkState];
}

#pragma mark - Toast

- (void)toast:(NSString *)msg {
    UIView *host = _card ?: _window;
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 190, 34)];
    t.center = CGPointMake(host.bounds.size.width / 2, host.bounds.size.height - 86);
    t.text = msg;
    t.font = [UIFont systemFontOfSize:12];
    t.textColor = [UIColor whiteColor];
    t.textAlignment = NSTextAlignmentCenter;
    t.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    t.layer.cornerRadius = 12;
    t.clipsToBounds = YES;
    [host addSubview:t];
    [UIView animateWithDuration:1.6 delay:0.9 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{ t.alpha = 0; }
                     completion:^(BOOL done) { [t removeFromSuperview]; }];
}

@end
