using Godot;
using Rts.CombatLab;
using Rts.Kernel.Combat;

public partial class CombatLab : Control
{
    [Export] public Godot.Collections.Array<CombatLabPreset> Presets { get; set; } = new();
    private LabConfiguration[] _configurations = [];
    private LabSession _session = null!;
    private LabSaveStore _saveStore = null!;
    private CombatArena _arena = null!;
    private OptionButton _presetChoice = null!;
    private Label _clock = null!;
    private Label _selection = null!;
    private Label _status = null!;
    private Label _saveInfo = null!;
    private Label _speedInfo = null!;
    private RichTextLabel _logView = null!;
    private readonly Queue<string> _history = [];
    private bool _paused;
    private double _stepMs;
    internal ulong Selected { get; private set; }
    internal LabSession Session => _session;
    internal CombatArena Arena => _arena;
    internal bool Paused => _paused;

    public override async void _Ready()
    {
        try
        {
            if (Engine.PhysicsTicksPerSecond != LabSession.TickRate) throw new InvalidOperationException("Laboratory tick rate must be 30.");
            _configurations = Presets.Select(preset => preset.ToConfiguration()).ToArray();
            if (_configurations.Length == 0 || _configurations.Select(config => config.Id).Distinct().Count() != _configurations.Length)
                throw new InvalidOperationException("Unique laboratory presets required.");
            _arena = GetNode<CombatArena>("%Arena");
            _presetChoice = GetNode<OptionButton>("%PresetChoice");
            _clock = GetNode<Label>("%Clock");
            _selection = GetNode<Label>("%Selection");
            _status = GetNode<Label>("%Status");
            _saveInfo = GetNode<Label>("%SaveInfo");
            _speedInfo = GetNode<Label>("%SpeedInfo");
            _logView = GetNode<RichTextLabel>("%EventLog");
            var args = OS.GetCmdlineUserArgs();
            var testing = args.Contains("--self-test");
            _saveStore = new(ProjectSettings.GlobalizePath(testing ? "user://selftest/save.json" : "user://save.json"));
            foreach (var configuration in _configurations) _presetChoice.AddItem(configuration.Title);
            _presetChoice.ItemSelected += index => ResetPreset((int)index);
            _arena.UnitClicked += OnUnitClicked;
            GetNode<Button>("%StopButton").Pressed += StopSelection;
            GetNode<Button>("%DuelButton").Pressed += StartDuels;
            GetNode<Button>("%PauseButton").Pressed += TogglePause;
            GetNode<Button>("%StepButton").Pressed += SingleStep;
            GetNode<Button>("%SaveButton").Pressed += SaveGame;
            GetNode<Button>("%LoadButton").Pressed += LoadGame;
            GetNode<Button>("%ResetButton").Pressed += () => ResetPreset(_presetChoice.Selected);
            GetNode<HSlider>("%VisualSpeed").ValueChanged += value =>
            {
                _arena.SetVisualSpeed((float)value);
                _speedInfo.Text = $"表现速度 ×{value:0.0}（逻辑保持30Hz）";
            };
            ResetPreset(0);
            GD.Print("COMBAT_LAB_READY");
            if (testing)
            {
                _paused = true;
                var checks = await LabUiChecks.Run(this);
                GD.Print($"COMBAT_LAB_SELFTEST_PASS checks={checks}");
                GetTree().Quit();
            }
            else if (Array.IndexOf(args, "--profile") is var profile && profile >= 0)
            {
                _paused = true;
                var checks = 0;
                LabHostChecks.Profile((condition, message) => { checks++; if (!condition) throw new InvalidOperationException(message); },
                    int.Parse(args[profile + 1]));
                GD.Print($"COMBAT_LAB_PROFILE_PASS checks={checks}");
                GetTree().Quit();
            }
            else if (Array.IndexOf(args, "--capture") is var capture && capture >= 0)
            {
                _paused = true;
                await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
                await ToSignal(RenderingServer.Singleton, RenderingServer.SignalName.FramePostDraw);
                var error = GetViewport().GetTexture().GetImage().SavePng(args[capture + 1]);
                if (error != Error.Ok) throw new IOException($"Capture failed: {error}");
                GD.Print("COMBAT_LAB_CAPTURE_PASS");
                GetTree().Quit();
            }
        }
        catch (Exception error)
        {
            GD.PushError(error.ToString());
            GD.Print("COMBAT_LAB_FAILED");
            GetTree().Quit(1);
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        if (_session is not null && !_paused) StepSimulation();
    }

    internal void ResetPreset(int index)
    {
        _session = new(_configurations[index]);
        _presetChoice.Select(index);
        Selected = _session.Configuration.Entities[0].Id.Value;
        _history.Clear();
        _arena.Rebuild(_session.Configuration.Entities);
        _arena.UpdateStates(_session.ReadStates(), _session.Frame, Selected, reset: true);
        _status.Text = "左键选择任意一方，右键另一方即可攻击。远处目标会拒绝，不追击。";
        Refresh();
    }

    internal void SelectUnit(ulong id)
    {
        Selected = _session.ReadStates().Any(state => state.Id.Value == id && state.Alive) ? id : 0;
        _arena.UpdateStates(_session.ReadStates(), _session.Frame, Selected);
        Refresh();
    }

    private void OnUnitClicked(long id, int button)
    {
        if (button == (int)MouseButton.Left) SelectUnit((ulong)id);
        else if (id != 0 && Selected != 0)
        {
            _session.Attack(Selected, (ulong)id);
            _status.Text = $"已下令：{Selected} → {id}，下一逻辑帧处理。";
        }
    }

    private void StopSelection()
    {
        if (Selected == 0) { _status.Text = "请先选择一个存活单位。"; return; }
        _session.Stop(Selected);
        _status.Text = $"已下令：停止 {Selected}。";
    }
    private void StartDuels() { _session.StartDuels(); _status.Text = "已下达双方交战命令；没有自动索敌。"; }
    private void TogglePause() { _paused = !_paused; Refresh(); }
    internal void SetPaused(bool paused) { _paused = paused; Refresh(); }
    private void SingleStep() { _paused = true; StepSimulation(); }

    internal void StepSimulation()
    {
        var started = System.Diagnostics.Stopwatch.GetTimestamp();
        var result = _session.Step();
        _stepMs = System.Diagnostics.Stopwatch.GetElapsedTime(started).TotalMilliseconds;
        var states = _session.ReadStates();
        if (!states.Any(state => state.Id.Value == Selected && state.Alive)) Selected = 0;
        _arena.UpdateStates(states, _session.Frame, Selected);
        _arena.Consume(result.Events);
        foreach (var refused in result.Commands.Where(command => !command.Accepted))
            _status.Text = $"命令被拒绝：{ReasonText(refused.Reason)}";
        foreach (var entry in result.Events.Where(entry => entry.Kind is CombatEventKind.AttackStarted
            or CombatEventKind.DamageApplied or CombatEventKind.UnitDied or CombatEventKind.AttackEnded))
        {
            var message = entry.Kind switch
            {
                CombatEventKind.AttackStarted => $"{entry.Attacker} → {entry.Target} 开始前摇",
                CombatEventKind.DamageApplied => $"{entry.Attacker} → {entry.Target} 扣血 {entry.AppliedDamage.ToPresentationDouble():0.#}",
                CombatEventKind.UnitDied => $"{entry.Target} 阵亡",
                _ => $"{entry.Attacker} 结束攻击：{ReasonText(entry.Reason)}"
            };
            _history.Enqueue($"F{entry.Frame}  {message}");
            while (_history.Count > 9) _history.Dequeue();
        }
        Refresh();
    }

    private void SaveGame()
    {
        try { _saveStore.Save(_session.Save()); _saveInfo.Text = $"已保存：{_session.Configuration.Title} · 帧 {_session.Frame}"; }
        catch (IOException error) { _status.Text = $"保存失败：{error.Message}"; }
        catch (UnauthorizedAccessException error) { _status.Text = $"保存失败：{error.Message}"; }
    }

    private void LoadGame()
    {
        try
        {
            var restored = LabSession.Load(_saveStore.Load(), _configurations);
            _session = restored;
            _paused = true;
            Selected = 0;
            _presetChoice.Select(Array.FindIndex(_configurations, config => config.Id == restored.Configuration.Id));
            _history.Clear();
            _arena.Rebuild(_session.Configuration.Entities);
            _arena.UpdateStates(_session.ReadStates(), _session.Frame, Selected, reset: true);
            _status.Text = $"已恢复帧 {_session.Frame}，当前暂停；按 P 继续。历史伤害不会重播。";
            Refresh();
        }
        catch (InvalidDataException error) { _status.Text = $"存档内容无效：{error.Message}"; }
        catch (IOException error) { _status.Text = $"读档失败：{error.Message}"; }
        catch (UnauthorizedAccessException error) { _status.Text = $"读档失败：{error.Message}"; }
        catch (System.Text.Json.JsonException error) { _status.Text = $"存档格式错误：{error.Message}"; }
    }

    private void Refresh()
    {
        _clock.Text = $"30 Hz  ·  帧 {_session.Frame}  ·  {(_paused ? "暂停" : "运行")}  ·  逻辑 {_stepMs:0.00} ms";
        GetNode<Button>("%PauseButton").Text = _paused ? "继续  P" : "暂停  P";
        var state = _session.ReadStates().FirstOrDefault(unit => unit.Id.Value == Selected);
        _selection.Text = state is null ? "未选择单位" :
            $"单位 {Selected}\n生命 {state.Health.ToPresentationDouble():0.#} / {state.Definition.MaxHealth.ToPresentationDouble():0.#}\n" +
            $"目标 {(state.Target.IsNone ? "无" : state.Target.ToString())}\n" +
            $"冷却剩余 {Math.Max(0, state.NextAttackFrame - _session.Frame) / 30.0:0.00} 秒\n" +
            $"出手倒计时 {(state.DamageFrame is { } due ? ((due - _session.Frame) / 30.0).ToString("0.00") + " 秒" : "—")}";
        _logView.Text = string.Join("\n", _history);
    }

    public override void _UnhandledKeyInput(InputEvent @event)
    {
        if (@event is not InputEventKey { Pressed: true, Echo: false } key) return;
        switch (key.PhysicalKeycode)
        {
            case Key.Space: StopSelection(); break;
            case Key.D: StartDuels(); break;
            case Key.P: TogglePause(); break;
            case Key.N: SingleStep(); break;
            case Key.F5: SaveGame(); break;
            case Key.F9: LoadGame(); break;
            case Key.R: ResetPreset(_presetChoice.Selected); break;
            case Key.Key1: ResetPreset(0); break;
            case Key.Key2: ResetPreset(1); break;
            case Key.Key3: ResetPreset(2); break;
            default: return;
        }
        GetViewport().SetInputAsHandled();
    }

    private static string ReasonText(CombatReason reason) => reason switch
    {
        CombatReason.TargetOutOfRange => "目标超出射程",
        CombatReason.Stopped => "玩家停止",
        CombatReason.Replaced => "换目标",
        CombatReason.Died => "单位死亡",
        CombatReason.TargetLost => "目标已死亡或失效",
        CombatReason.InvalidTarget => "目标同阵营或不能攻击",
        _ => reason.ToString()
    };
}
