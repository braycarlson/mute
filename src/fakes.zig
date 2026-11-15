const kalymma = @import("kalymma");
const mantra = @import("mantra");
const nimble = @import("nimble");
const umbra = @import("umbra");

pub const App = umbra.AppType(umbra.Fake);
pub const Client = nimble.RuntimeType(nimble.Fake).Client;
pub const Mixer = mantra.MixerType(mantra.Fake);
pub const Runtime = kalymma.RuntimeType(kalymma.Fake);
