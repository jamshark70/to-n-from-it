~dir = thisProcess.nowExecutingPath.dirname;

s.waitForBoot {
	b.free;
	b = Array.fill(2, { |i| Buffer.readChannel(s, (~dir +/+ "samp/04-g9.aiff"), channels: [i]) });
	m = MixerChannel(\test, s, 2, 2, level: -25.dbamp);
	MixingBoard(\x, nil, m);
};

ChuckableBrowser.newWindow;

MT(1).gui;

b[0].numFrames

~saveaddr = s.addr;
~debugaddr = DebugNetAddr("127.0.0.1", 57110);

s.addr = ~debugaddr;
s.addr = ~saveaddr;

s.stopAliveThread;
s.startAliveThread;

a = m.play {
	var	bufFr = BufFrames.ir(b[0]),
		trig = Dust.kr(12),
		dur = TExpRand.kr(0.07, 0.8, trig),
		rate = Demand.kr(trig, 0, Dswitch1([
			Dwhite(4.0, 8.0, inf),
			Dwhite(1.0, 1.4, inf),
			Dwhite(0.2, 0.5, inf)
		], Dwrand(#[0, 1, 2], #[0.6, 0.3, 0.1], inf))),
		pos = TRand.kr(0, bufFr - (rate * dur * BufSampleRate.ir(b[0])), trig) / bufFr;
	GrainBuf.ar(1, trig, dur, b, rate, pos, interp: 2, pan: 0, envbufnum: ~eb);
}.play;

a.free;


g = GenericGlobalControl(\test, nil, 0); g.gui;

// quite nice -- keep the start pos moving!!
a = m.play({ |dratio = 0.25, bufnum, rate = 1, /*start = 0,*/ sustain = 1|
	var	bufFr = BufFrames.kr(bufnum),
		freq = SinOsc.kr(0.09, 0).range(6, 18),
		trig = Impulse.ar(freq),
		start = MouseX.kr(0, 1, 0, 0.1) + SinOsc.kr(0.1, 0, 0.01),
		// start = SinOsc.kr(0.1, 0, 0.45, 0.45),
		dur = min(freq.reciprocal * 20, (1.0 - start) / rate * BufDur.kr(bufnum)),
		sig = GrainBuf.ar(2, trig, dur, bufnum, rate,
			start, // / bufFr, // SinOsc.kr(0.1, 0, 441, start) / bufFr,
			envbufnum: -1 // ~eb
		),
		sr = SampleRate.ir;
	// SendTrig.kr(Impulse.kr(20), 0, start);
	sig = Latch.ar(sig, Impulse.ar(sr * dratio));
	sig = LPF.ar(sig.round(0.01), sr * 0.45);
	sig
}, [bufnum: b[0], start: 20000, dratio: 0.05, rate: 1]);
// o.free;
// o = OSCFunc({ |msg| defer { g.value = msg[3] } }, ['/tr', a.nodeID], s.addr);

a.trace;

a.free;

b[0].plot



SynthDef(\buzz, { |bufnum, tfreq, start, gdur = 0.1, rate = 1, pan,
	dratio = 0.25, lpfreq = 19000, releaseTime = 2, gate = 1, out|
	var	// bufFr = BufFrames.kr(bufnum),
		// tfreq = SinOsc.kr(0.09, 0).range(6, 18),
		trig = Impulse.ar(tfreq),
		// start = MouseX.kr(0, 1, 0, 0.1) + SinOsc.kr(0.1, 0, 0.01),
		// start = SinOsc.kr(0.1, 0, 0.45, 0.45),
		graindur = min(gdur, (1.0 - start) / rate * BufDur.kr(bufnum)),
		sig = GrainBuf.ar(2, trig, graindur, bufnum, rate,
			start, pan: pan, envbufnum: -1 // ~eb
		),
		sr = SampleRate.ir;
	sig = Latch.ar(sig, Impulse.ar(sr * dratio));
	sig = LPF.ar(sig.round(0.01), lpfreq)
		* EnvGen.kr(Env.asr(0.01, 1, releaseTime, -7), gate, doneAction: 2);
	Out.ar(out, sig)
}).add;

(
var dur = 40, release = 5;
if(t.tryPerform(\isRunning) ? false) { t.stop };
t = TLSequenceIterator([
	{
		~tfreq = GenericGlobalControl(\tfreq, nil, 18, #[1, 20]);
		~start = GenericGlobalControl(\start, nil, 0.05);
		~dur = GenericGlobalControl(\dur, nil, 1, #[0.1, 5]);
		~pan = GenericGlobalControl(\pan, nil, 0, \bipolar);
		~dratio = GenericGlobalControl(\dratio, nil, 0.25);
		~lpfreq = GenericGlobalControl(\lpfreq, nil, 19000, \freq);
		0
	},
	gcAutoSynthCmd: (gc: e { ~start }, outName: \out,
		/*name: \ctlEnv,*/ time: { ~dur ? 1 }, connect: 0, dur: dur + release,
		// env: Env(#[0.6, 0.01, 0.1], #[0.9, 0.1], \sin)
		id: \startctl,
		name: {
			max(0, EnvGen.kr(Env(#[0.6, 0.2, 0.0, 0.1], [dur - 0.5, 0.4, release + 0.1], \sin))
				+ LFDNoise1.kr(LFNoise1.kr(1.2).range(0.2, 3), 0.03))
		}
	),
	gcAutoSynthCmd: (gc: e { ~pan }, outName: \out,
		name: { LFNoise1.kr(7) * XLine.kr(0.01, 1, dur, doneAction: 2) }
	),
	gcAutoSynthCmd: (gc: e { ~dratio }, outName: \outbus,
		name: \ctlEnv, time: { ~dur ? 1 }, connect: 0, dur: dur + release,
		env: Env(#[0.8, 0.08], #[1], 4)
	),
	gcAutoSynthCmd: (gc: e { ~tfreq }, outName: \outbus,
		name: \ctlEnv, time: { ~dur ? 1 }, connect: 0, dur: dur,
		env: Env(#[6, 18], #[1], \sin)
	),
	gcAutoSynthCmd: (gc: e { ~dur }, outName: \out,
		name: { (topEnvironment[\tfreq].kr * 20) }
	),
	// gcAutoSynthCmd: (gc: e { ~start }, outName: \outbus,
	// 	name: \ctlEnv, time: { ~dur ? 1 }, connect: 0,
	// 	env: 
	// ),
	{
		// damn lazy init
		PR(\synthCmd).copy.putAll((
			id: \bz, name: \buzz, target: m.synthgroup, out: m.inbus, bufnum: b[0],
			tfreq: ~tfreq.asMap, start: ~start.asMap, gdur: ~dur.asMap, pan: ~pan.asMap,
			dratio: ~dratio.asMap, lpfreq: ~lpfreq.asMap,
			dur: dur, releaseTime: release
		))
	},
	// synthCmd ends after 'dur' beats, but I need to wait until the synth is gone
	funcCmd: (
		setDoneSignal: {
			~doneSignal = SimpleController(~iterator.findActive(\bz).node)
				.put(\n_end, e { ~stop.() });
		},
		clearDoneSignal: { ~doneSignal.remove }
	),
	\cmdSync,
	funcCmd: (func: {
		"done".postln;
		~iterator.activeCmds.copy.do { |cmd|
			if(cmd !== currentEnvironment) { cmd.stop };
		};
	})
]).play;
u.remove;
u = SimpleController(t).put(\done, {
	u.remove;
	"freeing gcs".debug;
	[~tfreq, ~start, ~dur, ~pan, ~dratio, ~lpfreq].free;
});
)

#[startctl, bz].do { |key| t.findActive(key).node.trace };

t.stop;

s.addr = ~debugaddr;
s.addr = ~saveaddr;

Error.debug = true;
Error.debug = false;


PR(\gcAutoSynthCmd).openFile;
PR(\gcAutoSynthCmd).listMethods;
PR(\gcAutoSynthCmd).v[\superFire].postcs
PR(\gcAutoSynthCmd).v[\fire].postcs

BusDict


m.play((instrument: \bufGrainPan, time: b[0].duration, bufnum: b[0], amp: 1));
