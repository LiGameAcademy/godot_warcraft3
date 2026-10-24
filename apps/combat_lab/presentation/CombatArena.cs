using Godot;
using Rts.Kernel;
using Rts.Kernel.Combat;

public partial class CombatArena : Control
{
    [Signal] public delegate void UnitClickedEventHandler(long entityId, int button);
    [Export] public PackedScene? UnitScene { get; set; }
    private readonly Dictionary<ulong, CombatUnitView> _views = [];
    private IReadOnlyList<EntityState> _entities = [];
    private Dictionary<ulong, CombatantState> _states = [];
    private readonly Dictionary<ulong, Vector2> _positions = [];
    private ulong _selected;
    private float _scale = 1;
    private float _visualSpeed = 1;

    public override void _Ready() => Resized += Relayout;

    internal void Rebuild(IReadOnlyList<EntityState> entities)
    {
        foreach (var view in _views.Values) { RemoveChild(view); view.QueueFree(); }
        _views.Clear();
        _positions.Clear();
        _states.Clear();
        _selected = 0;
        _entities = entities;
        foreach (var entity in entities)
        {
            var view = (UnitScene ?? throw new InvalidOperationException("Unit scene required.")).Instantiate<CombatUnitView>();
            AddChild(view);
            view.VisualSpeed = _visualSpeed;
            _views.Add(entity.Id.Value, view);
        }
        Relayout();
    }

    internal void UpdateStates(IReadOnlyList<CombatantState> states, long frame, ulong selected, bool reset = false)
    {
        _states = states.ToDictionary(state => state.Id.Value);
        _selected = selected;
        foreach (var entity in _entities)
        {
            var state = _states[entity.Id.Value];
            var facing = state.Target.IsNone || !_positions.ContainsKey(state.Target.Value)
                ? (entity.OwnerId == 0 ? Vector2.Right : Vector2.Left)
                : (_positions[state.Target.Value] - _positions[state.Id.Value]).Normalized();
            var view = _views[state.Id.Value];
            view.UpdateState(state, entity.OwnerId, frame, state.Id.Value == selected, facing);
            if (reset) view.ResetPresentation();
        }
        QueueRedraw();
    }

    internal void Consume(IReadOnlyList<CombatEvent> events)
    {
        foreach (var entry in events)
        {
            if (entry.Kind == CombatEventKind.AttackStarted && _views.TryGetValue(entry.Attacker.Value, out var attacker))
                attacker.PlayAttack(_states[entry.Attacker.Value].Definition.Weapon.WindupFrames);
            if (entry.Kind == CombatEventKind.AttackEnded && _views.TryGetValue(entry.Attacker.Value, out var ended)) ended.EndAttack();
            if (entry.Kind == CombatEventKind.DamageApplied && entry.AppliedDamage > 0 && _views.TryGetValue(entry.Target.Value, out var hit))
                hit.PlayHit(entry.AppliedDamage.ToPresentationDouble().ToString("0.#"));
            if (entry.Kind == CombatEventKind.UnitDied && _views.TryGetValue(entry.Target.Value, out var victim)) victim.PlayDeath();
        }
    }

    internal void SetVisualSpeed(float speed)
    {
        _visualSpeed = speed;
        foreach (var view in _views.Values) view.VisualSpeed = speed;
    }
    internal Vector2 PointFor(ulong id) => _positions[id];
    internal CombatUnitView ViewFor(ulong id) => _views[id];

    private void Relayout()
    {
        if (_entities.Count == 0) return;
        var points = _entities.ToDictionary(entity => entity.Id.Value, entity =>
            new Vector2((float)entity.Position.X.ToPresentationDouble(), (float)entity.Position.Y.ToPresentationDouble()));
        var low = new Vector2(points.Values.Min(point => point.X), points.Values.Min(point => point.Y));
        var high = new Vector2(points.Values.Max(point => point.X), points.Values.Max(point => point.Y));
        var span = high - low + Vector2.One * 220;
        _scale = Math.Max(.1f, Math.Min(Size.X / span.X, Size.Y / span.Y));
        var center = (low + high) / 2;
        foreach (var (id, point) in points)
        {
            _positions[id] = Size / 2 + (point - center) * _scale;
            _views[id].Position = _positions[id] - new Vector2(36, 37);
        }
        QueueRedraw();
    }

    public override void _GuiInput(InputEvent @event)
    {
        if (@event is not InputEventMouseButton { Pressed: true } click
            || click.ButtonIndex is not (MouseButton.Left or MouseButton.Right)) return;
        var nearest = _positions.OrderBy(pair => pair.Value.DistanceSquaredTo(click.Position))
            .FirstOrDefault(pair => pair.Value.DistanceSquaredTo(click.Position) <= 30 * 30);
        EmitSignal(SignalName.UnitClicked, checked((long)nearest.Key), (int)click.ButtonIndex);
        AcceptEvent();
    }

    public override void _Draw()
    {
        for (var x = 30; x < Size.X; x += 50) DrawLine(new(x, 0), new(x, Size.Y), new Color(1, 1, 1, .025f));
        for (var y = 30; y < Size.Y; y += 50) DrawLine(new(0, y), new(Size.X, y), new Color(1, 1, 1, .025f));
        if (_selected == 0 || !_states.TryGetValue(_selected, out var selected)) return;
        var origin = _positions[_selected];
        DrawArc(origin, (float)selected.Definition.Weapon.MaxRange.ToPresentationDouble() * _scale,
            0, Mathf.Tau, 96, new Color(.3f, .75f, 1, .28f), 1, true);
        if (!selected.Target.IsNone)
            DrawLine(origin, _positions[selected.Target.Value], new Color(1, .8f, .4f, .5f), 2, true);
    }
}
