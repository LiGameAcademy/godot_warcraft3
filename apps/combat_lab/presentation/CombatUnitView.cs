using Godot;
using Rts.Kernel.Combat;

public partial class CombatUnitView : Control
{
    private CombatantState? _state;
    private int _owner;
    private bool _selected;
    private long _frame;
    private Vector2 _facing = Vector2.Right;
    private float _swingRemaining;
    private float _swingDuration;
    private float _flashRemaining;
    private float _deathRemaining;
    private string _damageText = "";
    internal float VisualSpeed { get; set; } = 1;
    internal bool HasHitFlash => _flashRemaining > 0;
    internal bool AttackAnimating => _swingRemaining > 0;
    internal ulong EntityId => _state?.Id.Value ?? 0;

    internal void UpdateState(CombatantState state, int owner, long frame, bool selected, Vector2 facing)
    {
        _state = state;
        _owner = owner;
        _frame = frame;
        _selected = selected;
        _facing = facing;
        QueueRedraw();
    }

    internal void ResetPresentation()
    {
        _swingRemaining = 0;
        _flashRemaining = 0;
        _deathRemaining = 0;
        _damageText = "";
        if (_state is { Alive: true, DamageFrame: { } due } state)
        {
            _swingDuration = state.Definition.Weapon.WindupFrames / 30f + .18f;
            _swingRemaining = (due - _frame) / 30f + .18f;
        }
        QueueRedraw();
    }

    internal void PlayAttack(int windup)
    {
        _swingDuration = Math.Max(.2f, windup / 30f + .18f);
        _swingRemaining = _swingDuration;
    }
    internal void PlayHit(string amount) { _flashRemaining = .25f; _damageText = "-" + amount; }
    internal void EndAttack() => _swingRemaining = 0;
    internal void PlayDeath() { EndAttack(); _flashRemaining = 0; _deathRemaining = .6f; }

    public override void _Process(double delta)
    {
        var elapsed = (float)delta * VisualSpeed;
        _swingRemaining = Math.Max(0, _swingRemaining - elapsed);
        _flashRemaining = Math.Max(0, _flashRemaining - elapsed);
        _deathRemaining = Math.Max(0, _deathRemaining - elapsed);
        if (elapsed > 0) QueueRedraw();
    }

    public override void _Draw()
    {
        if (_state is null) return;
        var center = new Vector2(36, 37);
        var team = _owner == 0 ? new Color("#50bcff") : new Color("#ff806a");
        var color = !_state.Alive ? new Color("#606a75") : _flashRemaining > 0 ? Colors.White : team;
        if (_selected) DrawArc(center, 27, 0, Mathf.Tau, 48, new Color("#f0e5a3"), 2, true);
        DrawCircle(center + new Vector2(0, 5), 19, new Color(0, 0, 0, .3f));
        DrawCircle(center, _state.Alive ? 17 : 13, color);
        DrawArc(center, 17, 0, Mathf.Tau, 32, team.Darkened(.25f), 2, true);
        if (_state.Alive)
        {
            var phase = _swingDuration > 0 ? 1 - _swingRemaining / _swingDuration : 0;
            var angle = _facing.Angle() - .45f + (_swingRemaining > 0 ? Mathf.Sin(phase * Mathf.Pi) * 1.5f : 0);
            var tip = center + Vector2.FromAngle(angle) * 31;
            DrawLine(center, tip, new Color("#e2e9ee"), 4, true);
            DrawCircle(center - _facing * 4, 8, team.Darkened(.35f));
        }
        else
        {
            DrawLine(center - new Vector2(7, 7), center + new Vector2(7, 7), new Color("#c7cbd0"), 2, true);
            DrawLine(center + new Vector2(-7, 7), center + new Vector2(7, -7), new Color("#c7cbd0"), 2, true);
        }
        var fraction = (float)(_state.Health.ToPresentationDouble() / _state.Definition.MaxHealth.ToPresentationDouble());
        DrawRect(new Rect2(5, 4, 62, 6), new Color("#26323d"));
        DrawRect(new Rect2(5, 4, 62 * fraction, 6), team);
        DrawString(GetThemeDefaultFont(), new Vector2(0, 77),
            _state.Alive ? $"{EntityId}  {(_owner == 0 ? "蓝" : "红")}" : $"{EntityId} 阵亡",
            HorizontalAlignment.Center, 72, 13, !_state.Alive ? new Color("#8894a0") : new Color("#dfeaf1"));
        if (_flashRemaining > 0)
            DrawString(GetThemeDefaultFont(), new Vector2(0, -7), _damageText, HorizontalAlignment.Center, 72, 14, new Color("#ffda9a"));
        if (_deathRemaining > 0) DrawArc(center, 22 + (1 - _deathRemaining / .6f) * 12, 0, Mathf.Tau, 32,
            new Color(1, .5f, .4f, _deathRemaining / .6f), 2, true);
    }
}
