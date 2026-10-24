using Godot;
using Rts.Kernel.Combat;

internal static class LabUiChecks
{
    internal static async Task<int> Run(CombatLab lab)
    {
        var checks = 0;
        void Check(bool condition, string message) { checks++; if (!condition) throw new InvalidOperationException(message); }
        await lab.ToSignal(lab.GetTree(), SceneTree.SignalName.ProcessFrame);
        await lab.ToSignal(lab.GetTree(), SceneTree.SignalName.ProcessFrame);
        Check(lab.Arena.Size.X > 400 && lab.Arena.Size.Y > 200, "arena layout is usable");
        lab.SetPaused(true);
        lab.ResetPreset(0);
        void Click(ulong id, MouseButton button)
        {
            var point = lab.Arena.GlobalPosition + lab.Arena.PointFor(id);
            lab.GetViewport().PushInput(new InputEventMouseMotion { Position = point, GlobalPosition = point }, true);
            lab.GetViewport().PushInput(new InputEventMouseButton { ButtonIndex = button, Pressed = true,
                Position = point, GlobalPosition = point }, true);
            lab.GetViewport().PushInput(new InputEventMouseButton { ButtonIndex = button, Pressed = false,
                Position = point, GlobalPosition = point }, true);
            // Coordinates are in the main viewport, independent of window position/stretch.
        }
        lab.SelectUnit(0);
        Click(1, MouseButton.Left);
        Check(lab.Selected == 1, "real left click selects a living unit");
        Click(3, MouseButton.Right);
        lab.StepSimulation();
        Check(lab.Session.ReadStates()[0].Target.Value == 3, "real right click reaches the kernel command boundary");
        Click(5, MouseButton.Right);
        lab.StepSimulation();
        Check(lab.Session.ReadStates()[0].Target.Value == 3 && lab.GetNode<Label>("%Status").Text.Contains("超出射程"),
            "out-of-range command refuses and preserves original attack");
        var savedFrame = lab.Session.Frame;
        var deadline = lab.Session.ReadStates()[0].NextAttackFrame;
        var damageFrame = lab.Session.ReadStates()[0].DamageFrame;
        lab.GetNode<Button>("%SaveButton").EmitSignal(BaseButton.SignalName.Pressed);
        lab.GetNode<Button>("%StopButton").EmitSignal(BaseButton.SignalName.Pressed);
        lab.StepSimulation();
        Check(lab.Session.ReadStates()[0].Stopped && !lab.Arena.ViewFor(1).AttackAnimating, "Stop cancels order and attack presentation");
        Click(4, MouseButton.Right);
        lab.StepSimulation();
        Check(lab.Session.ReadStates()[0].Target.Value == 4 && lab.Session.ReadStates()[0].NextAttackFrame == deadline,
            "retarget keeps reserved cooldown");
        lab.GetNode<Button>("%LoadButton").EmitSignal(BaseButton.SignalName.Pressed);
        Check(lab.Session.Frame == savedFrame && lab.Paused && lab.Selected == 0, "load restores frame and pauses with clean selection");
        Check(lab.Session.ReadStates()[0].DamageFrame == damageFrame && lab.Session.ReadStates()[0].Target.Value == 3,
            "load restores original windup and target");
        Check(!lab.Arena.ViewFor(3).HasHitFlash, "load clears stale hit flash");
        while (lab.Session.Frame < damageFrame) lab.StepSimulation();
        var hit = lab.Session.ReadStates().Single(state => state.Id.Value == 3).Health;
        Check(hit < 130 && lab.Arena.ViewFor(3).HasHitFlash, "damage event updates health and presentation independently");
        lab.GetNode<Button>("%SaveButton").EmitSignal(BaseButton.SignalName.Pressed);
        lab.StepSimulation();
        lab.GetNode<Button>("%LoadButton").EmitSignal(BaseButton.SignalName.Pressed);
        Check(!lab.Arena.ViewFor(3).HasHitFlash, "damage-point restore does not replay hit flash");
        lab.StepSimulation();
        Check(lab.Session.ReadStates().Single(state => state.Id.Value == 3).Health == hit, "post-hit load never repeats damage");
        var frame = lab.Session.Frame;
        await lab.ToSignal(lab.GetTree(), SceneTree.SignalName.PhysicsFrame);
        await lab.ToSignal(lab.GetTree(), SceneTree.SignalName.PhysicsFrame);
        Check(lab.Session.Frame == frame, "paused physics does not advance logical clock");

        lab.ResetPreset(1);
        lab.SetPaused(true);
        lab.GetNode<Button>("%DuelButton").EmitSignal(BaseButton.SignalName.Pressed);
        lab.StepSimulation();
        for (var i = 0; i < 15; i++) lab.StepSimulation();
        Check(lab.Session.ReadStates().All(state => !state.Alive) && lab.Selected == 0, "mutual lethal events clear selection for both corpses");
        lab.SelectUnit(0);
        Click(1, MouseButton.Left);
        Check(lab.Selected == 0, "corpse cannot be selected");
        lab.GetNode<Button>("%SaveButton").EmitSignal(BaseButton.SignalName.Pressed);
        lab.ResetPreset(0);
        lab.GetNode<Button>("%LoadButton").EmitSignal(BaseButton.SignalName.Pressed);
        Check(lab.Session.Configuration.Id == "mutual" && lab.Session.ReadStates().All(state => !state.Alive),
            "save restores original scenario and death tombstones");
        var noEvents = lab.Session.Step();
        Check(!noEvents.Events.Any(), "restored corpses publish no duplicate death events");

        lab.ResetPreset(2);
        lab.SetPaused(true);
        lab.GetNode<HSlider>("%VisualSpeed").Value = 0;
        lab.GetNode<Button>("%DuelButton").EmitSignal(BaseButton.SignalName.Pressed);
        for (var i = 0; i < 19; i++) lab.StepSimulation();
        Check(lab.Session.ReadStates().All(state => state.Health < 130), "frozen visual animation does not delay logical hits");
        Check(lab.Session.Configuration.Entities.Count == 24, "24-unit resource preset is instantiated");
        LabHostChecks.Run(Check);
        return checks;
    }
}
