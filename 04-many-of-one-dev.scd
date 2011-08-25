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
		* EnvGen.kr(Env.asr(0.01, 1, releaseTime), gate, doneAction: 2);
	Out.ar(out, sig)
}).add;

(
if(t.isRunning) { t.stop };
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
	{
		// damn lazy init
		PR(\synthCmd).copy.putAll((
			id: \bz, name: \buzz, target: m.synthgroup, out: m.inbus, bufnum: b[0],
			tfreq: ~tfreq.asMap, start: ~start.asMap, gdur: ~dur.asMap, pan: ~pan.asMap,
			dratio: ~dratio.asMap, lpfreq: ~lpfreq.asMap,
			dur: 3
		))
	},
	// another ugly hack - maybe i'd be better off with the BP
	funcCmd: (
		setDoneSignal: {
			~doneSignal = SimpleController(~iterator.findActive(\bz).node)
				.put(\n_end, e { ~stop.() });
		},
		clearDoneSignal: { ~doneSignal.remove }
	),
	\cmdSync,
	{
		"done".postln;
		0
	}
]).play;
u.remove;
u = SimpleController(t).put(\done, {
	u.remove;
	"freeing gcs".debug;
	[~tfreq, ~start, ~dur, ~pan, ~dratio, ~lpfreq].free;
});
)

t.stop;